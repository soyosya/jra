<#
.SYNOPSIS
  当日カード(ブレンド版)。OOS検証で最良だった「標準(h2h0.5/脚質0.2/騎手0.2/枠0.1)+コンピ0.5」で軸・相手を選び、
  頭数≤FieldMax かつ コンピ期待的中≥EhMin のレースに限り 3連複 軸1-相手3頭(3点)を推奨します。

.DESCRIPTION
  - h2h/脚質/騎手/枠は axis-backtest と同方式で過去[Date-HistDays..Date-1]から算出(着差=勝ち時計比%±8%, 脚質/枠/騎手は場×距離/場の勝率)。
  - コンピは当日最新スナップショット。順位別勝率(コンピ期待的中の較正)は過去から。当日エントリーは レース情報(出馬表)から。
  - リアルタイムオッズがあれば「軸が3番人気以下=★妙味」を併記。ばんえい除外。馬同定=馬名(h2h)/馬番(コンピ・枠)。
  ※検証: 6場プールOOSで本ブレンドが回収84.7%(コンピ純70.3%)。

.PARAMETER Date/CalFrom/HistDays/RecentN/RecentDays/MinCompare/FieldMax/EhMin/Venue/ExportCsv
#>
[CmdletBinding()]
param(
  [string]$Date = (Get-Date).ToString('yyyy-MM-dd'),
  [string]$CalFrom = '2024-01-01',   # コンピ順位別勝率の較正開始
  [int]$HistDays = 400,              # h2h/脚質/騎手/枠の集計に使う過去日数
  [int]$RecentN = 5,
  [int]$RecentDays = 183,
  [int]$MinCompare = 4,
  [int]$FieldMax = 8,
  [double]$EhMin = 0.55,
  [string]$Venue = '',
  [string]$ExportCsv = '',
  [string]$ExportBets = '',   # RakutenVote用: date,venue,race,axis_uma,axis_name,p1..p4(軸+相手上位4頭)。推奨レースのみ。
  [string]$ExportAll = '',    # 記録用: 全解析レース(推奨外含む)。上記+ eh,推奨(1/0),頭数。
  [switch]$Verify   # 着順と三連複払戻で推奨買い目の的中/回収を検証(過去日)
)
$ErrorActionPreference='Stop'
$appsettings = Join-Path $PSScriptRoot '..\共通\appsettings.json'
$connStr=(Get-Content $appsettings -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
$conn=New-Object System.Data.SqlClient.SqlConnection($connStr); $conn.Open()
$targetDt=[datetime]$Date
$histFrom=$targetDt.AddDays(-$HistDays).ToString('yyyy-MM-dd'); $histTo=$targetDt.AddDays(-1).ToString('yyyy-MM-dd')
$W=@{h=0.5;k=0.2;j=0.2;d=0.1;p=0.5}   # 標準+コンピ0.5

function Median($a){ $s=@($a|Sort-Object); $n=$s.Count; if($n -eq 0){return $null}; if($n%2 -eq 1){return [double]$s[[int](($n-1)/2)]}; return ([double]$s[$n/2-1]+[double]$s[$n/2])/2.0 }
function StyleOf([int]$e,[int]$n){ if($e -le 0 -or $n -le 0){return '?'}; if($e -eq 1){return '逃げ'}; if($e -le $n*0.33){return '先行'}; if($e -le $n*0.66){return '差し'}; return '追込' }
function Zmap($m){ $v=@($m.Values); $z=@{}; if($v.Count -eq 0){return $z}; $mean=($v|Measure-Object -Average).Average; $sd= if($v.Count -gt 1){[Math]::Sqrt((($v|ForEach-Object{($_-$mean)*($_-$mean)})|Measure-Object -Sum).Sum/($v.Count-1))}else{0}; foreach($k in $m.Keys){ $z[$k]= if($sd -gt 0){($m[$k]-$mean)/$sd}else{0.0} }; return $z }
function Rate($h){ if($null -eq $h -or $h.n -eq 0){return $null}; return [double]$h.w/$h.n }

try {
  # ===== 過去ロード(h2h/脚質/騎手/枠) =====
  Write-Host "ロード中..."
  $cmd=$conn.CreateCommand(); $cmd.CommandTimeout=600
  $cmd.CommandText=@"
SELECT kk.開催場所 v, kk.開催日 d, kk.レース番号 rno, kk.馬番 uma, kk.馬名 nm, kk.着順 c, kk.走破時計 t,
  COALESCE(NULLIF(kk.一コーナー,0),NULLIF(kk.二コーナー,0),NULLIF(kk.三コーナー,0),NULLIF(kk.四コーナー,0)) early,
  r.距離 dist, r.騎手 jk
FROM 競走結果 kk LEFT JOIN レース情報 r ON r.開催場所=kk.開催場所 AND r.開催日=kk.開催日 AND r.レース番号=kk.レース番号 AND r.馬番=kk.馬番
WHERE kk.着順>0 AND kk.走破時計>0 AND kk.開催日>=@h AND kk.開催日<=@hto AND kk.開催場所 NOT LIKE '%ば'
"@
  [void]$cmd.Parameters.AddWithValue('@h',$histFrom);[void]$cmd.Parameters.AddWithValue('@hto',$histTo)
  $r=$cmd.ExecuteReader(); $races=@{}; $horseRuns=@{}
  while($r.Read()){
    $v=$r.GetString(0);$d=$r.GetDateTime(1);$rno=$r.GetInt32(2);$uma=$r.GetInt32(3);$nm=$r.GetString(4);$c=$r.GetInt32(5);$t=[double]$r.GetDecimal(6)
    $early= if($r.IsDBNull(7)){0}else{[int]$r.GetValue(7)}; $dist= if($r.IsDBNull(8)){0}else{[int]$r.GetValue(8)}; $jk= if($r.IsDBNull(9)){''}else{$r.GetString(9)}
    $key='{0}|{1:yyyy-MM-dd}|{2}' -f $v,$d,$rno
    if(-not $races.ContainsKey($key)){ $races[$key]=@{ rows=(New-Object System.Collections.Generic.List[object]); win=[double]::MaxValue; v=$v; dist=$dist } }
    $races[$key].rows.Add(@{ uma=$uma; nm=$nm; c=$c; t=$t; early=$early; jk=$jk })
    if($t -lt $races[$key].win){ $races[$key].win=$t }; if($dist -gt 0 -and $races[$key].dist -eq 0){ $races[$key].dist=$dist }
    if(-not $horseRuns.ContainsKey($nm)){ $horseRuns[$nm]=(New-Object System.Collections.Generic.List[object]) }
    $horseRuns[$nm].Add(@{ date=$d; key=$key })
  }
  $r.Close()
  # コース傾向(場×距離): 脚質別/枠別勝率, 騎手勝率(場)
  $styleWin=@{}; $drawWin=@{}; $jWin=@{}
  foreach($key in $races.Keys){ $rc=$races[$key]; if($rc.dist -le 0){continue}; $n=$rc.rows.Count; $ck="$($rc.v)|$($rc.dist)"
    if(-not $styleWin.ContainsKey($ck)){ $styleWin[$ck]=@{}; $drawWin[$ck]=@{} }
    foreach($row in $rc.rows){ $st=StyleOf $row.early $n
      if($st -ne '?'){ if(-not $styleWin[$ck].ContainsKey($st)){$styleWin[$ck][$st]=@{n=0;w=0}}; $styleWin[$ck][$st].n++; if($row.c -eq 1){$styleWin[$ck][$st].w++} }
      $g= if($row.uma -le 4){'内'}elseif($row.uma -le 8){'中'}else{'外'}; if(-not $drawWin[$ck].ContainsKey($g)){$drawWin[$ck][$g]=@{n=0;w=0}}; $drawWin[$ck][$g].n++; if($row.c -eq 1){$drawWin[$ck][$g].w++}
      if($row.jk -ne ''){ $jk="$($rc.v)|$($row.jk)"; if(-not $jWin.ContainsKey($jk)){$jWin[$jk]=@{n=0;w=0}}; $jWin[$jk].n++; if($row.c -eq 1){$jWin[$jk].w++} }
    } }
  Write-Host ("  過去 {0:N0}レース / {1:N0}頭" -f $races.Count,$horseRuns.Count)

  # ===== コンピ順位別勝率(過去, 期待的中の較正) =====
  $cmd=$conn.CreateCommand(); $cmd.CommandTimeout=600
  $cmd.CommandText=@"
WITH s AS (SELECT k.開催日,k.開催場所,k.レース番号,k.馬番,k.指数,kk.着順,ROW_NUMBER() OVER(PARTITION BY k.開催日,k.開催場所,k.レース番号,k.馬番 ORDER BY k.取得日時 DESC) rn
  FROM コンピ指数 k JOIN 競走結果 kk ON kk.開催場所=k.開催場所 AND kk.開催日=k.開催日 AND kk.レース番号=k.レース番号 AND kk.馬番=k.馬番
  WHERE k.開催日>=@cf AND k.開催日<=@hto AND k.指数 IS NOT NULL AND kk.着順>0 AND k.開催場所 NOT LIKE '%ば')
SELECT 開催場所,開催日,レース番号,馬番,指数,着順 FROM s WHERE rn=1
"@
  [void]$cmd.Parameters.AddWithValue('@cf',$CalFrom);[void]$cmd.Parameters.AddWithValue('@hto',$histTo)
  $r=$cmd.ExecuteReader(); $ch=@{}
  while($r.Read()){ $key='{0}|{1:yyyy-MM-dd}|{2}' -f $r.GetString(0),$r.GetDateTime(1),$r.GetInt32(2); if(-not $ch.ContainsKey($key)){$ch[$key]=@{}}; $ch[$key][[int]$r.GetInt32(3)]=@{s=[int]$r.GetInt32(4);c=[int]$r.GetInt32(5)} }
  $r.Close()
  $MR=20;$cc=@(0)*($MR+1);$cw=@(0)*($MR+1)
  foreach($key in $ch.Keys){ $R=@($ch[$key].GetEnumerator()|Sort-Object @{e={$_.Value.s};Descending=$true},@{e={[int]$_.Key};Descending=$false}|ForEach-Object{[int]$_.Key})
    for($i=0;$i -lt $R.Count -and ($i+1) -le $MR;$i++){ $cc[$i+1]++; if($ch[$key][$R[$i]].c -eq 1){$cw[$i+1]++} } }
  $winRate=@(0.0)*($MR+1); for($i=1;$i -le $MR;$i++){ if($cc[$i] -gt 0){$winRate[$i]=[double]$cw[$i]/$cc[$i]} }

  # ===== 当日エントリー(レース情報) + 当日コンピ + オッズ =====
  $venSql= if($Venue -ne ''){"AND 開催場所=@v"}else{"AND 開催場所 NOT LIKE '%ば'"}
  $cmd=$conn.CreateCommand(); $cmd.CommandTimeout=300
  $cmd.CommandText="SELECT 開催場所,レース番号,馬番,馬名,騎手,距離 FROM レース情報 WHERE 開催日=@d $venSql"
  [void]$cmd.Parameters.AddWithValue('@d',$targetDt); if($Venue -ne ''){[void]$cmd.Parameters.AddWithValue('@v',$Venue)}
  $r=$cmd.ExecuteReader(); $today=@{}
  while($r.Read()){ $rk='{0}|{1}' -f $r.GetString(0),$r.GetInt32(1); if(-not $today.ContainsKey($rk)){$today[$rk]=@{dist=0;ents=@{}}}
    $today[$rk].ents[[int]$r.GetInt32(2)]=@{ nm=$r.GetString(3); jk=$(if($r.IsDBNull(4)){''}else{$r.GetString(4)}) }
    if($today[$rk].dist -eq 0 -and -not $r.IsDBNull(5)){ $today[$rk].dist=[int]$r.GetValue(5) } }
  $r.Close()
  $cmd=$conn.CreateCommand(); $cmd.CommandTimeout=120
  $cmd.CommandText=@"
WITH s AS (SELECT 開催場所,レース番号,馬番,馬名,指数,ROW_NUMBER() OVER(PARTITION BY 開催日,開催場所,レース番号,馬番 ORDER BY 取得日時 DESC) rn
  FROM コンピ指数 WHERE 開催日=@d AND 指数 IS NOT NULL)
SELECT 開催場所,レース番号,馬番,馬名,指数 FROM s WHERE rn=1
"@
  [void]$cmd.Parameters.AddWithValue('@d',$targetDt); $r=$cmd.ExecuteReader(); $compi=@{}
  while($r.Read()){ $rk='{0}|{1}' -f $r.GetString(0),$r.GetInt32(1); if(-not $compi.ContainsKey($rk)){$compi[$rk]=@{}}; $compi[$rk][[int]$r.GetInt32(2)]=@{s=[int]$r.GetInt32(4); nm=$r.GetString(3)} }
  $r.Close()
  $odds=@{}; $cmd=$conn.CreateCommand(); $cmd.CommandTimeout=120
  $cmd.CommandText="WITH o AS (SELECT 開催場所,レース番号,馬番,単勝オッズ,人気,ROW_NUMBER() OVER(PARTITION BY 開催場所,レース番号,馬番 ORDER BY 日時 DESC) rn FROM リアルタイムオッズ WHERE 開催日=@d) SELECT 開催場所,レース番号,馬番,単勝オッズ,人気 FROM o WHERE rn=1"
  [void]$cmd.Parameters.AddWithValue('@d',$targetDt)
  try{ $r=$cmd.ExecuteReader(); while($r.Read()){ $rk='{0}|{1}' -f $r.GetString(0),$r.GetInt32(1); if(-not $odds.ContainsKey($rk)){$odds[$rk]=@{}}; $odds[$rk][[int]$r.GetInt32(2)]=@{ tan=$(if($r.IsDBNull(3)){$null}else{[double]$r.GetValue(3)}); pop=$(if($r.IsDBNull(4)){$null}else{[int]$r.GetValue(4)}) } }; $r.Close() }catch{}
  # 検証用(過去日): 着順 + 三連複払戻
  $kekka=@{}; $fuku=@{}
  if($Verify){
    $cmd=$conn.CreateCommand(); $cmd.CommandTimeout=120
    $cmd.CommandText="SELECT 開催場所,レース番号,馬番,着順 FROM 競走結果 WHERE 開催日=@d AND 着順>0"
    [void]$cmd.Parameters.AddWithValue('@d',$targetDt); $r=$cmd.ExecuteReader()
    while($r.Read()){ $rk='{0}|{1}' -f $r.GetString(0),$r.GetInt32(1); if(-not $kekka.ContainsKey($rk)){$kekka[$rk]=@{}}; $kekka[$rk][[int]$r.GetInt32(2)]=[int]$r.GetInt32(3) }; $r.Close()
    $cmd=$conn.CreateCommand(); $cmd.CommandTimeout=120
    $cmd.CommandText="SELECT 開催場所,レース番号,組番,金額 FROM 払戻金 WHERE 馬券=N'三連複' AND 開催日=@d"
    [void]$cmd.Parameters.AddWithValue('@d',$targetDt); $r=$cmd.ExecuteReader()
    while($r.Read()){ $rk='{0}|{1}' -f $r.GetString(0),$r.GetInt32(1); $k=([string]$r.GetValue(2)).Trim(); if($k -eq ''){continue}; $norm=(($k -split '-'|ForEach-Object{[int]$_}|Sort-Object) -join '-'); if(-not $fuku.ContainsKey($rk)){$fuku[$rk]=@{}}; $fuku[$rk][$norm]=[double]$r.GetValue(3) }; $r.Close()
  }
  $conn.Close()
  if($compi.Count -eq 0){ Write-Host "対象日のコンピ指数がありません: $Date (先に fetch-compi)"; return }

  function TrioProb3([double]$pa,[double]$pb,[double]$pc){ $pm=@(@($pa,$pb,$pc),@($pa,$pc,$pb),@($pb,$pa,$pc),@($pb,$pc,$pa),@($pc,$pa,$pb),@($pc,$pb,$pa)); $tt=0.0; foreach($q in $pm){ $d1=1.0-$q[0]; if($d1 -le 0){continue}; $d2=1.0-$q[0]-$q[1]; if($d2 -le 0){continue}; $tt+=$q[0]*($q[1]/$d1)*($q[2]/$d2)}; $tt }

  Write-Host ("`n=== コンピ×独自分析 ブレンド買い目 {0}{1} (標準+コンピ0.5 / 頭数≤{2} & コンピ期待的中≥{3} / 3連複相手3頭) ===" -f $Date,$(if($Venue){" "+$Venue}else{''}),$FieldMax,$EhMin)
  $exp=@(); $bets=@(); $betsAll=@(); $nrec=0; $vN=0; $vHit=0; $vRet=0.0; $vStake=0.0
  foreach($rk in ($compi.Keys|Sort-Object)){
    if(-not $today.ContainsKey($rk)){ continue }
    $cf=$compi[$rk]; $ents=$today[$rk].ents; $dist=$today[$rk].dist
    # フィールド = 当日エントリー(コンピがある馬)。馬名はレース情報優先、無ければコンピの馬名。
    $field=@(); $nameByUma=@{}
    foreach($uma in $cf.Keys){ $nm= if($ents.ContainsKey($uma) -and $ents[$uma].nm){$ents[$uma].nm}else{$cf[$uma].nm}; $jk= if($ents.ContainsKey($uma)){$ents[$uma].jk}else{''}; $field+=@{uma=$uma;nm=$nm;jk=$jk;s=$cf[$uma].s}; $nameByUma[$uma]=$nm }
    if($field.Count -lt 5){ continue }
    $n=$field.Count; $td=$targetDt; $v=$rk.Split('|')[0]; $rno=$rk.Split('|')[1]; $ck="$v|$dist"
    $fieldNames=@($field|ForEach-Object{$_.nm}); $fieldSet=@{}; $fieldNames|ForEach-Object{$fieldSet[$_]=$true}

    # h2h
    $mavg=@{}
    foreach($a in $fieldNames){ $mavg[$a]=@{}; $tmp=@{}
      if($horseRuns.ContainsKey($a)){
        $runs=@($horseRuns[$a]|Where-Object{$_.date -lt $td -and $_.date -ge $td.AddDays(-$RecentDays)}|Sort-Object date -Descending|Select-Object -First $RecentN)
        foreach($run in $runs){ $rr=$races[$run.key]; $wt=$rr.win; if($wt -le 0){continue}; $ta=($rr.rows|Where-Object{$_.nm -eq $a}|Select-Object -First 1).t
          foreach($h in $rr.rows){ if($h.nm -eq $a){continue}; $rel=($h.t-$ta)/$wt*100.0; if($rel -gt 8){$rel=8}elseif($rel -lt -8){$rel=-8}; if(-not $tmp.ContainsKey($h.nm)){$tmp[$h.nm]=New-Object System.Collections.Generic.List[double]}; $tmp[$h.nm].Add($rel) } } }
      foreach($x in $tmp.Keys){ $mavg[$a][$x]=Median $tmp[$x] } }
    function PairM2($a,$b){ $vv=@(); if($mavg[$a].ContainsKey($b)){$vv+=$mavg[$a][$b]}; if($mavg[$b].ContainsKey($a)){$vv+=(-1.0*$mavg[$b][$a])}; if($vv.Count -gt 0){return (($vv|Measure-Object -Average).Average)}
      $common=@($mavg[$a].Keys|Where-Object{$mavg[$b].ContainsKey($_) -and $_ -ne $a -and $_ -ne $b}); if($common.Count -eq 0){return $null}
      $fc=@($common|Where-Object{$fieldSet.ContainsKey($_)}); $use= if($fc.Count -gt 0){$fc}else{$common}; $est=foreach($cc2 in $use){ $mavg[$a][$cc2]-$mavg[$b][$cc2] }; return (Median $est) }
    $h2h=@{}; $cmpCnt=@{}
    foreach($a in $fieldNames){ $ms=@(); foreach($b in $fieldNames){ if($a -ne $b){ $m=PairM2 $a $b; if($null -ne $m){$ms+=$m} } }; $cmpCnt[$a]=$ms.Count; if($ms.Count -ge 1){$h2h[$a]=($ms|Measure-Object -Average).Average} }

    # 脚質・枠・騎手・コンピ
    $kyaku=@{}; $draw=@{}; $jock=@{}; $comp=@{}
    foreach($e in $field){ $a=$e.nm
      $cnt=@{}
      if($horseRuns.ContainsKey($a)){ foreach($run in @($horseRuns[$a]|Where-Object{$_.date -lt $td -and $_.date -ge $td.AddDays(-$RecentDays)}|Sort-Object date -Descending|Select-Object -First $RecentN)){ $rr=$races[$run.key]; $me=($rr.rows|Where-Object{$_.nm -eq $a}|Select-Object -First 1); if($null -eq $me){continue}; $s=StyleOf $me.early $rr.rows.Count; if($s -ne '?'){$cnt[$s]=$cnt[$s]+1} } }
      $st= if($cnt.Count -gt 0){($cnt.GetEnumerator()|Sort-Object Value -Descending|Select-Object -First 1).Key}else{'?'}
      $kr= if($st -ne '?' -and $styleWin.ContainsKey($ck)){ Rate $styleWin[$ck][$st] }else{$null}; $kyaku[$a]= if($null -ne $kr){$kr}else{0.0}
      $g= if($e.uma -le 4){'内'}elseif($e.uma -le 8){'中'}else{'外'}; $dr= if($drawWin.ContainsKey($ck)){ Rate $drawWin[$ck][$g] }else{$null}; $draw[$a]= if($null -ne $dr){$dr}else{0.0}
      $jr= if($e.jk -ne '' -and $jWin.ContainsKey("$v|$($e.jk)")){ $hh=$jWin["$v|$($e.jk)"]; if($hh.n -ge 30){[double]$hh.w/$hh.n}else{$null} }else{$null}; $jock[$a]= if($null -ne $jr){$jr}else{0.0}
      $comp[$a]=[double]$e.s
    }
    $zh=Zmap $h2h; $zk=Zmap $kyaku; $zj=Zmap $jock; $zd=Zmap $draw; $zp=Zmap $comp
    # ブレンドスコアでランキング(全頭)
    $scored=foreach($e in $field){ $a=$e.nm; [PSCustomObject]@{ uma=$e.uma; nm=$a; s=$e.s; score=($W.h*[double]($zh[$a])+$W.k*[double]($zk[$a])+$W.j*[double]($zj[$a])+$W.d*[double]($zd[$a])+$W.p*[double]($zp[$a])) } }
    $rank=@($scored|Sort-Object @{e={$_.score};Descending=$true},@{e={[int]$_.uma};Descending=$false})

    # コンピ期待的中(4相手, コンピ順位別勝率を全頭正規化)で選別
    $Rc=@($field|Sort-Object @{e={$_.s};Descending=$true},@{e={[int]$_.uma};Descending=$false}|ForEach-Object{[int]$_.uma})
    $praw=@{}; $sf=0.0; foreach($uma in $Rc){ $rkk=([array]::IndexOf($Rc,$uma))+1; $pr= if($rkk -ge 1 -and $rkk -le $MR){$winRate[$rkk]}else{0.005}; if($pr -le 0){$pr=0.005}; $praw[$uma]=$pr; $sf+=$pr }
    if($sf -le 0){$sf=1}; $axc=$Rc[0]; $opp4=@($Rc[1..4])
    $eh=0.0; foreach($pr in @(@(0,1),@(0,2),@(0,3),@(1,2),@(1,3),@(2,3))){ $eh += TrioProb3 ($praw[$axc]/$sf) ($praw[$opp4[$pr[0]]]/$sf) ($praw[$opp4[$pr[1]]]/$sf) }
    # 全解析レース(推奨外含む)を記録用に出力。would-be買い目=ブレンド順位の 軸+相手上位4頭。
    $isRec = ($n -le $FieldMax -and $eh -ge $EhMin)
    $axA=$rank[0]; $rel4A=@($rank[1..([Math]::Min(4,$rank.Count-1))])
    $betsAll+=[PSCustomObject]@{ date=$Date; venue=$v; race=$rno; axis_uma=$axA.uma; axis_name=$axA.nm
      p1=$(if($rel4A.Count -ge 1){$rel4A[0].uma}else{''}); p2=$(if($rel4A.Count -ge 2){$rel4A[1].uma}else{''}); p3=$(if($rel4A.Count -ge 3){$rel4A[2].uma}else{''}); p4=$(if($rel4A.Count -ge 4){$rel4A[3].uma}else{''})
      eh=[Math]::Round($eh,3); 推奨=$(if($isRec){1}else{0}); 頭数=$n }
    if(-not $isRec){ continue }
    $nrec++

    $ax=$rank[0]; $rel=@($rank[1..3])
    $oflag=''
    if($odds.ContainsKey($rk) -and $odds[$rk].ContainsKey($ax.uma) -and $null -ne $odds[$rk][$ax.uma].pop){ $ap=$odds[$rk][$ax.uma].pop; $at=$odds[$rk][$ax.uma].tan; $oflag= if($ap -ge 3){" ★妙味(軸{0}番人気 単{1})" -f $ap,$at}else{" (軸{0}番人気)" -f $ap} }
    $relStr=($rel|ForEach-Object{ "{0} {1}(指{2})" -f $_.uma,$_.nm,$_.s }) -join ' / '
    $combos=@(); foreach($pr in @(@(0,1),@(0,2),@(1,2))){ $combos+= ("{0}-{1}-{2}" -f $ax.uma,$rel[$pr[0]].uma,$rel[$pr[1]].uma) }
    $compAx= if($Rc[0] -eq $ax.uma){'(コンピ1位)'}else{ "(コンピ{0}位→h2hで軸入替)" -f (([array]::IndexOf($Rc,$ax.uma))+1) }
    Write-Host ("`n{0} {1}R 頭{2} コンピ期待的中{3}%{4}" -f $v,$rno,$n,([Math]::Round(100*$eh,1)),$oflag)
    Write-Host ("  軸 {0} {1}(指{2}) {3}" -f $ax.uma,$ax.nm,$ax.s,$compAx)
    Write-Host ("  相手 {0}" -f $relStr)
    Write-Host ("  3連複3点: {0}" -f ($combos -join ' / '))
    foreach($cb in $combos){ $exp+=[PSCustomObject]@{ 日付=$Date; 場=$v; レース=$rno; 券種='3連複'; 組番=$cb; 軸馬番=$ax.uma; 期待的中=[Math]::Round($eh,3) } }
    $rel4=@($rank[1..([Math]::Min(4,$rank.Count-1))])
    $bets+=[PSCustomObject]@{ date=$Date; venue=$v; race=$rno; axis_uma=$ax.uma; axis_name=$ax.nm
      p1=$(if($rel4.Count -ge 1){$rel4[0].uma}else{''}); p2=$(if($rel4.Count -ge 2){$rel4[1].uma}else{''}); p3=$(if($rel4.Count -ge 3){$rel4[2].uma}else{''}); p4=$(if($rel4.Count -ge 4){$rel4[3].uma}else{''}) }

    if($Verify -and $kekka.ContainsKey($rk)){
      $vN++; $vStake += 100.0*$combos.Count
      $top=@{}; foreach($u in $kekka[$rk].Keys){ $c=$kekka[$rk][$u]; if($c -ge 1 -and $c -le 3){ $top[$c]=$u } }
      if($top.ContainsKey(1) -and $top.ContainsKey(2) -and $top.ContainsKey(3)){
        $set=@($top[1],$top[2],$top[3]); $oppSet=@{}; $rel|ForEach-Object{$oppSet[$_.uma]=$true}
        $hit= (($set -contains $ax.uma) -and (@($set|Where-Object{$oppSet.ContainsKey($_)}).Count -eq 2))
        $ret=0.0; if($hit){ $sk=(($set|ForEach-Object{[int]$_}|Sort-Object) -join '-'); if($fuku.ContainsKey($rk) -and $fuku[$rk].ContainsKey($sk)){ $ret=$fuku[$rk][$sk] } }
        $vRet += $ret; if($hit){$vHit++}
        Write-Host ("  → {0}" -f $(if($hit){"★的中 配当{0}円 (着順 {1}-{2}-{3})" -f $ret,$top[1],$top[2],$top[3]}else{"不的中 (着順 {0}-{1}-{2})" -f $top[1],$top[2],$top[3]}))
      }
    }
  }
  Write-Host ("`n推奨レース数: {0} / コンピ掲載 {1}レース" -f $nrec,$compi.Count)
  if($Verify -and $vN -gt 0){ Write-Host ("`n===== 検証({0}) ブレンド版 =====" -f $Date); Write-Host ("  対象 {0}レース / 的中 {1} ({2}%) / 投資 {3:N0}円 / 払戻 {4:N0}円 / 回収率 {5}%" -f $vN,$vHit,([Math]::Round(100.0*$vHit/$vN,1)),$vStake,$vRet,([Math]::Round(100.0*$vRet/$vStake,1))) }
  if($Verify){ Write-Host ("VERIFYRAW|blend|{0}|{1}|{2}|{3}" -f $vN,$vHit,[int]$vStake,[int]$vRet) }
  if($ExportCsv -ne '' -and $exp.Count -gt 0){ $exp|Export-Csv -Path $ExportCsv -NoTypeInformation -Encoding UTF8; Write-Host ("買い目CSV: {0} ({1}点)" -f $ExportCsv,$exp.Count) }
  if($ExportBets -ne '' -and $bets.Count -gt 0){ $bets|Export-Csv -Path $ExportBets -NoTypeInformation -Encoding UTF8; Write-Host ("RakutenVote用CSV: {0} ({1}レース)" -f $ExportBets,$bets.Count) }
  if($ExportAll -ne '' -and $betsAll.Count -gt 0){ $betsAll|Export-Csv -Path $ExportAll -NoTypeInformation -Encoding UTF8; Write-Host ("全解析CSV: {0} ({1}レース, 推奨{2})" -f $ExportAll,$betsAll.Count,$nrec) }
}
finally { if($conn.State -eq 'Open'){ $conn.Close() } }
