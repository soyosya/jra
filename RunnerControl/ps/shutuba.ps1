# 出馬表(JSON・馬柱形式)。JRA版(地方 shutuba.ps1 移植・JRAスキーマ適応)。読み取り専用。
#  各馬: 枠/馬番/父/母(母父)/性齢/騎手/斤量/馬体重(増減)/調教師/馬主/生産/印(ipat_bets)/指数/コンピ順位/h2h順位/確定単勝/持時計 ＋過去5走。
#  過去走=競走結果(着順/着差タイム/走破時計/上り3F/上り順位/通過[一〜四コーナー])＋レース情報(距離/騎手/斤量/条件/競走名/枠/体重)＋競走成績(前半3F・ある分のみ)＋頭数。-Dateで過去日対応。
#  ※JRA差異: 馬情報は現状0件→父母等は空表示。通過順は競走結果の一〜四コーナー列を直接使用(地方は競走成績)。前半3Fのみ競走成績から補完。印はC:\temp\ipat_bets_<ymd>.csv(axis/partners)。
param([string]$Venue='',[int]$Race=0,[string]$Date='',[string]$Umas='')   # Umas=選択馬番(カンマ区切り)指定時はその馬だけの馬柱
$OutputEncoding=[Console]::OutputEncoding=[System.Text.Encoding]::UTF8
$ErrorActionPreference='SilentlyContinue'
# venue/race は未指定でも可: その開催日の先頭場/先頭レースに解決する(セレクタ・日付変更対応)。
if($Date -and ($Date -replace '[^\d]','').Length -eq 8){ $dt=[datetime]::ParseExact(($Date -replace '[^\d]',''),'yyyyMMdd',$null) } else { $dt=Get-Date }
$date=$dt.ToString('yyyy-MM-dd'); $ymd=$dt.ToString('yyyyMMdd')
$RecentN=5; $RecentDays=365
function Median($a){ $s=@($a|Sort-Object); $n=$s.Count; if($n -eq 0){return $null}; if($n%2 -eq 1){return [double]$s[[int](($n-1)/2)]}; return ([double]$s[$n/2-1]+[double]$s[$n/2])/2.0 }

$cs=(Get-Content 'C:\jra\共通\appsettings.json' -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
$cn=New-Object System.Data.SqlClient.SqlConnection $cs; $cn.Open()
function Q1([string]$sql,[hashtable]$p){ $c=$cn.CreateCommand(); $c.CommandText=$sql; foreach($k in $p.Keys){[void]$c.Parameters.AddWithValue($k,$p[$k])}; $d=New-Object System.Data.DataTable; (New-Object System.Data.SqlClient.SqlDataAdapter $c).Fill($d)|Out-Null; ,$d }

# セレクタ用リスト + 場/レースを解決(日付変更で当該場が非開催なら先頭場/先頭レースに補正)
$dates=@(); foreach($x in (Q1 "SELECT DISTINCT TOP 90 開催日 FROM dbo.コンピ指数 ORDER BY 開催日 DESC" @{}).Rows){ $dates+=([datetime]$x.開催日).ToString('yyyy-MM-dd') }
$venues=@(); foreach($x in (Q1 "SELECT DISTINCT 開催場所 FROM dbo.コンピ指数 WHERE 開催日=@d ORDER BY 開催場所" @{'@d'=$date}).Rows){ $venues+=[string]$x.開催場所 }
if($venues.Count -and ($Venue -eq '' -or ($venues -notcontains $Venue))){ $Venue=$venues[0] }
$races=@(); foreach($x in (Q1 "SELECT DISTINCT レース番号 FROM dbo.コンピ指数 WHERE 開催日=@d AND 開催場所=@v ORDER BY レース番号" @{'@d'=$date;'@v'=$Venue}).Rows){ $races+=[int]$x.レース番号 }
if($races.Count -and ($Race -le 0 -or ($races -notcontains $Race))){ $Race=$races[0] }
$idxr=[array]::IndexOf($races,$Race)
$prevRace=$(if($idxr -gt 0){$races[$idxr-1]}else{0}); $nextRace=$(if($idxr -ge 0 -and $idxr -lt $races.Count-1){$races[$idxr+1]}else{0})

# 印(ipat_bets CSV: axis=◎ / partners=○▲△押)。当日のみ存在。
$mark=@{}
$betCsv="C:\temp\ipat_bets_$ymd.csv"
if(Test-Path $betCsv){
  $prow=@(Import-Csv $betCsv -Encoding UTF8 | Where-Object { $_.venue -eq $Venue -and [int]$_.race -eq $Race })[0]
  if($prow){
    if("$($prow.axis)" -ne ''){ $mark[[int]$prow.axis]='◎' }
    $pl=@(("$($prow.partners)" -split '\|') | Where-Object{ $_ -ne '' }); $pm=@('○','▲','△','押')
    for($i=0;$i -lt $pl.Count -and $i -lt 4;$i++){ $u=[int]$pl[$i]; if(-not $mark.ContainsKey($u)){ $mark[$u]=$pm[$i] } }
  }
}

$hd=Q1 @"
WITH cur AS (SELECT 馬番,馬名,指数,指数順位, ROW_NUMBER() OVER(PARTITION BY 馬番 ORDER BY 取得日時 DESC) sn FROM dbo.コンピ指数 WHERE 開催日=@d AND 開催場所=@v AND レース番号=@r)
SELECT cur.馬番,cur.馬名,cur.指数,cur.指数順位, ri.枠番,ri.性別,ri.馬齢,ri.騎手,ri.斤量,ri.馬体重,ri.馬体重増減,ri.調教師,ri.馬主,ri.距離,ri.発走時刻,ri.競走名,ri.条件,ri.コース種別, kr.枠番 frame2
FROM cur OUTER APPLY (SELECT TOP 1 枠番,性別,馬齢,騎手,斤量,馬体重,馬体重増減,調教師,馬主,距離,発走時刻,競走名,条件,コース種別 FROM dbo.レース情報 WHERE 開催場所=@v AND 開催日=@d AND レース番号=@r AND 馬番=cur.馬番) ri
OUTER APPLY (SELECT TOP 1 枠番 FROM dbo.競走結果 WHERE 開催場所=@v AND 開催日=@d AND レース番号=@r AND 馬番=cur.馬番) kr
WHERE cur.sn=1 ORDER BY cur.指数順位
"@ @{'@d'=$date;'@v'=$Venue;'@r'=$Race}
$field=@($hd.Rows | ForEach-Object { [string]$_.馬名 })
$compiRk=@{}; foreach($r in $hd.Rows){ $compiRk[[string]$r.馬名]=[int]$r.指数順位 }

# 確定単勝オッズ(リアルタイムオッズ最新スナップショット)
$tan=@{}
foreach($x in (Q1 "WITH t AS (SELECT 馬番,単勝オッズ,ROW_NUMBER() OVER(PARTITION BY 馬番 ORDER BY 日時 DESC) rn FROM dbo.リアルタイムオッズ WHERE 開催日=@d AND 開催場所=@v AND レース番号=@r) SELECT 馬番,単勝オッズ o FROM t WHERE rn=1" @{'@d'=$date;'@v'=$Venue;'@r'=$Race}).Rows){ $tan[[int]$x.馬番]=[double]("0"+"$($x.o)") }

# 今走着順
$chOf=@{}
foreach($x in (Q1 "SELECT 馬番,TRY_CONVERT(int,着順) ch FROM dbo.競走結果 WHERE 開催場所=@v AND 開催日=@d AND レース番号=@r" @{'@d'=$date;'@v'=$Venue;'@r'=$Race}).Rows){ if($x.ch -isnot [DBNull] -and $null -ne $x.ch){ $chOf[[int]$x.馬番]=[int]$x.ch } }

# === h2h順位(近走着差の対戦比較。buyme.ps1と同方式) ===
$dmin=([datetime]$date).AddDays(-$RecentDays).ToString('yyyy-MM-dd')
$fieldSet=@{}; $field|ForEach-Object{$fieldSet[$_]=$true}
$recentKeys=@{}; $allKeys=@{}
foreach($h in $field){
  $rk=Q1 "SELECT TOP ($RecentN) 開催場所,開催日,レース番号 FROM dbo.競走結果 WHERE 馬名=@h AND 開催日<@d AND 開催日>=@dmin AND 走破時計>0 ORDER BY 開催日 DESC,レース番号 DESC" @{'@h'=$h;'@d'=$date;'@dmin'=$dmin}
  $keys=@(); foreach($x in $rk.Rows){ $kk=[string]$x.開催場所+'|'+([datetime]$x.開催日).ToString('yyyy-MM-dd')+'|'+[string]([int]$x.レース番号); $keys+=$kk; if(-not $allKeys.ContainsKey($kk)){$allKeys[$kk]=@{v=[string]$x.開催場所;d=([datetime]$x.開催日).ToString('yyyy-MM-dd');r=[int]$x.レース番号}} }
  $recentKeys[$h]=$keys
}
$raceRows=@{}; foreach($kk in $allKeys.Keys){ $info=$allKeys[$kk]; $m2=@{}; foreach($row in (Q1 "SELECT 馬名,走破時計 FROM dbo.競走結果 WHERE 開催場所=@v AND 開催日=@d AND レース番号=@r AND 走破時計>0 AND 着順>0" @{'@v'=$info.v;'@d'=$info.d;'@r'=$info.r}).Rows){ $m2[[string]$row.馬名]=[double]$row.走破時計 }; $raceRows[$kk]=$m2 }
$raceWin=@{}; foreach($kk in $raceRows.Keys){ $vals=@($raceRows[$kk].Values); if($vals.Count){ $raceWin[$kk]=($vals|Measure-Object -Minimum).Minimum } }
$mavg=@{}
foreach($a in $field){ $mavg[$a]=@{}; $tmp=@{}
  foreach($kk in $recentKeys[$a]){ $rr=$raceRows[$kk]; if($null -eq $rr -or -not $rr.ContainsKey($a)){continue}; $ta=$rr[$a]; $wt=$raceWin[$kk]; if(-not $wt){continue}
    foreach($x in $rr.Keys){ if($x -eq $a){continue}; $rel=($rr[$x]-$ta)/$wt*100.0; if($rel -gt 8){$rel=8}elseif($rel -lt -8){$rel=-8}; if(-not $tmp.ContainsKey($x)){$tmp[$x]=New-Object System.Collections.Generic.List[double]}; $tmp[$x].Add([double]$rel) } }
  foreach($x in $tmp.Keys){ $mavg[$a][$x]=Median $tmp[$x] } }
function PairM2($a,$b){ $vv=@(); if($mavg[$a].ContainsKey($b)){$vv+=$mavg[$a][$b]}; if($mavg[$b].ContainsKey($a)){$vv+=(-1.0*$mavg[$b][$a])}; if($vv.Count -gt 0){return (($vv|Measure-Object -Average).Average)}
  $common=@($mavg[$a].Keys|Where-Object{$mavg[$b].ContainsKey($_) -and $_ -ne $a -and $_ -ne $b}); if($common.Count -eq 0){return $null}
  $fc=@($common|Where-Object{$fieldSet.ContainsKey($_)}); $use=if($fc.Count -gt 0){$fc}else{$common}; $est=foreach($cc in $use){$mavg[$a][$cc]-$mavg[$b][$cc]}; return (Median $est) }
$h2hScore=@{}; foreach($a in $field){ $ms=@(); foreach($b in $field){ if($a -ne $b){ $mm=PairM2 $a $b; if($null -ne $mm){$ms+=$mm} } }; if($ms.Count -ge 1){$h2hScore[$a]=($ms|Measure-Object -Average).Average} }
$h2hRkNm=@{}; $hi=1; foreach($kv in ($h2hScore.GetEnumerator()|Sort-Object Value -Descending)){ $h2hRkNm[$kv.Key]=$hi; $hi++ }

# 過去5走を全頭まとめて1クエリで取得(逐次×頭数=重い→馬名IN+ROW_NUMBERでrn<=5に絞ってからAPPLY)。馬名→行配列。[[jra 高速化]]
$pastByHorse=@{}
if($field.Count -gt 0){
  $inp=@(); $php=@{'@d'=$date}; for($i=0;$i -lt $field.Count;$i++){ $inp+=('@ph'+$i); $php['@ph'+$i]=$field[$i] }
  $pastSql=@"
WITH base AS (
  SELECT cr.馬名,cr.開催日,cr.開催場所,cr.レース番号,cr.着順,cr.着差,cr.先着馬着差タイム,cr.後着馬着差タイム,cr.走破時計,cr.上り3F,cr.枠番 crframe,
    cr.一コーナー,cr.二コーナー,cr.三コーナー,cr.四コーナー,
    ROW_NUMBER() OVER(PARTITION BY cr.馬名 ORDER BY cr.開催日 DESC,cr.レース番号 DESC) rn
  FROM dbo.競走結果 cr WHERE cr.馬名 IN ($($inp -join ',')) AND cr.開催日<@d AND cr.着順>0)
SELECT b.馬名,b.開催日,b.開催場所,b.レース番号,b.着順,b.着差,b.先着馬着差タイム,b.後着馬着差タイム,b.走破時計,b.上り3F,b.crframe,
  b.一コーナー,b.二コーナー,b.三コーナー,b.四コーナー,
  (SELECT COUNT(*) FROM dbo.競走結果 z WHERE z.開催日=b.開催日 AND z.開催場所=b.開催場所 AND z.レース番号=b.レース番号 AND z.上り3F>0 AND z.上り3F<b.上り3F) agari_rk,
  ri.距離,ri.騎手,ri.斤量,ri.競走名,ri.条件,ri.コース種別,ri.枠番,ri.馬体重,
  ss.前半3F,
  (SELECT COUNT(*) FROM dbo.競走結果 x WHERE x.開催日=b.開催日 AND x.開催場所=b.開催場所 AND x.レース番号=b.レース番号 AND x.着順>0) tousu
FROM base b
OUTER APPLY (SELECT TOP 1 距離,騎手,斤量,競走名,条件,コース種別,枠番,馬体重 FROM dbo.レース情報 WHERE 開催日=b.開催日 AND 開催場所=b.開催場所 AND レース番号=b.レース番号 AND 馬名=b.馬名) ri
OUTER APPLY (SELECT TOP 1 前半3F FROM dbo.競走成績 WHERE 馬名=b.馬名 AND 開催日=b.開催日 AND 場名=b.開催場所 AND レース番号=b.レース番号) ss
WHERE b.rn<=5 ORDER BY b.馬名,b.開催日 DESC,b.レース番号 DESC
"@
  foreach($p in (Q1 $pastSql $php).Rows){ $hn=[string]$p.馬名; if(-not $pastByHorse.ContainsKey($hn)){$pastByHorse[$hn]=@()}; $pastByHorse[$hn]+=$p }
}

$dist=0; $post=''; $rn2=''; $kind=''
$horses=@()
foreach($r in $hd.Rows){
  $u=[int]$r.馬番; $nm="$($r.馬名)"
  $td= if($r.距離 -is [DBNull]){0}else{[int]$r.距離}; if($td -gt 0){$dist=$td}
  if($r.発走時刻 -isnot [DBNull] -and $post -eq ''){ $post=([datetime]$r.発走時刻).ToString('HH:mm') }
  if($r.競走名 -isnot [DBNull] -and $rn2 -eq ''){ $rn2="$($r.競走名)" }
  if($r.コース種別 -isnot [DBNull] -and $kind -eq ''){ $kind="$($r.コース種別)" }
  # 父母(母父)/生産牧場: 馬情報(JRAは現状0件→空)。
  $ped=Q1 "SELECT TOP 1 父,母,母父,生産牧場 FROM dbo.馬情報 WHERE 馬名=@h ORDER BY 更新日 DESC" @{'@h'=$nm}
  $chichi='';$haha='';$bofu='';$bokujo=''
  if($ped.Rows.Count){ $pr0=$ped.Rows[0]; $chichi=if($pr0.父 -is [DBNull]){''}else{"$($pr0.父)"}; $haha=if($pr0.母 -is [DBNull]){''}else{"$($pr0.母)"}; $bofu=if($pr0.母父 -is [DBNull]){''}else{"$($pr0.母父)"}; $bokujo=if($pr0.生産牧場 -is [DBNull]){''}else{"$($pr0.生産牧場)"} }
  # 持時計(距離別ベスト走破時計)
  $jit=@()
  foreach($j in (Q1 @"
SELECT ri.距離 d, MIN(cr.走破時計) t FROM dbo.競走結果 cr
OUTER APPLY (SELECT TOP 1 距離 FROM dbo.レース情報 WHERE 開催日=cr.開催日 AND 開催場所=cr.開催場所 AND レース番号=cr.レース番号 AND 馬名=cr.馬名) ri
WHERE cr.馬名=@h AND cr.着順>0 AND cr.走破時計>0 AND ri.距離>0 GROUP BY ri.距離 ORDER BY ri.距離
"@ @{'@h'=$nm}).Rows){ $jit += [ordered]@{ dist=[int]$j.d; t=[double]$j.t } }
  # 過去5走(全頭バッチ取得済み $pastByHorse から。列は従来の逐次クエリと同一)
  $past=@()
  foreach($p in @($pastByHorse[$nm])){ if($null -eq $p){continue}
    $ag=$(if($p.上り3F -is [DBNull] -or [double]("0"+"$($p.上り3F)") -le 0){''}else{"$($p.上り3F)"})
    # 通過: 競走結果の一〜四コーナー(0は未通過=除外)。
    $corner=''
    $cps=@($p.一コーナー,$p.二コーナー,$p.三コーナー,$p.四コーナー | ForEach-Object { if($_ -is [DBNull]){0}else{[int]("0"+"$_")} } | Where-Object { $_ -gt 0 })
    if($cps.Count){ $corner=($cps -join '-') }
    $past += [ordered]@{
      d=([datetime]$p.開催日).ToString('M/d'); fd=([datetime]$p.開催日).ToString('yyyy-MM-dd'); ven="$($p.開催場所)"; race=[int]$p.レース番号
      chaku=[int]$p.着順; tousu=[int]("0"+"$($p.tousu)")
      margin=$(if($p.走破時計 -is [DBNull] -or [double]("0"+"$($p.走破時計)") -le 0){''}else{ $mt= if([int]$p.着順 -eq 1){ if($p.後着馬着差タイム -is [DBNull]){0.0}else{[double]$p.後着馬着差タイム} }else{ if($p.先着馬着差タイム -is [DBNull]){0.0}else{[double]$p.先着馬着差タイム} }; ("{0:0.0}" -f $mt) })
      dist=$(if($p.距離 -is [DBNull]){0}else{[int]$p.距離}); kind=$(if($p.コース種別 -is [DBNull]){''}else{"$($p.コース種別)"})
      cond=$(if($p.条件 -is [DBNull]){''}else{("$($p.条件)" -replace 'サラブレッド系','' -replace '　',' ').Trim()})
      name=$(if($p.競走名 -is [DBNull]){''}else{"$($p.競走名)"})
      time=$(if($p.走破時計 -is [DBNull]){''}else{"$($p.走破時計)"})
      zen3f=$(if($p.前半3F -is [DBNull] -or [double]("0"+"$($p.前半3F)") -le 0){''}else{"$($p.前半3F)"})
      agari=$ag; agariRk=$(if($ag -ne ''){[int]("0"+"$($p.agari_rk)")+1}else{0})
      corner=$corner
      jk=$(if($p.騎手 -is [DBNull]){''}else{"$($p.騎手)"}); kin=$(if($p.斤量 -is [DBNull]){0}else{[double]$p.斤量})
      frame=$(if($p.crframe -isnot [DBNull] -and [int]("0"+"$($p.crframe)") -gt 0){[int]("0"+"$($p.crframe)")}elseif($p.枠番 -isnot [DBNull]){[int]("0"+"$($p.枠番)")}else{0}); wt=$(if($p.馬体重 -is [DBNull]){0}else{[int]("0"+"$($p.馬体重)")})
    }
  }
  $horses += [ordered]@{
    rk=[int]$r.指数順位; uma=$u; name=$nm; idx=[int]$r.指数; mark=$(if($mark.ContainsKey($u)){$mark[$u]}else{''})
    h2hRk=$(if($h2hRkNm.ContainsKey($nm)){$h2hRkNm[$nm]}else{0}); tan=$(if($tan.ContainsKey($u)){$tan[$u]}else{0})
    frame=$(if($r.枠番 -isnot [DBNull] -and [int]("0"+"$($r.枠番)") -gt 0){[int]("0"+"$($r.枠番)")}elseif($r.frame2 -isnot [DBNull]){[int]("0"+"$($r.frame2)")}else{0})
    sex=$(if($r.性別 -is [DBNull]){''}else{"$($r.性別)"}); age=$(if($r.馬齢 -is [DBNull]){0}else{[int]("0"+"$($r.馬齢)")})
    jk=$(if($r.騎手 -is [DBNull]){''}else{"$($r.騎手)"}); kin=$(if($r.斤量 -is [DBNull]){0}else{[double]$r.斤量})
    wt=$(if($r.馬体重 -is [DBNull]){0}else{[int]("0"+"$($r.馬体重)")}); wd=$(if($r.馬体重増減 -is [DBNull]){''}else{"$($r.馬体重増減)".Trim()})
    trainer=$(if($r.調教師 -is [DBNull]){''}else{"$($r.調教師)"}); owner=$(if($r.馬主 -is [DBNull]){''}else{"$($r.馬主)"})
    chichi=$chichi; haha=$haha; bofu=$bofu; bokujo=$bokujo
    jitokei=$jit; chaku=$(if($chOf.ContainsKey($u)){$chOf[$u]}else{0}); past=$past
  }
}
$cn.Close()
$horses=@($horses | Sort-Object {[int]$_.uma})
# 選択馬フィルタ(Umas指定時): データは全馬で計算済み(h2h/過去走は正確)、表示だけ選択馬に絞る。
if($Umas.Trim() -ne ''){ $sel=@{}; foreach($x in ($Umas -split ',')){ $n=0; if([int]::TryParse($x.Trim(),[ref]$n) -and $n -gt 0){$sel[$n]=$true} }; if($sel.Count -gt 0){ $horses=@($horses | Where-Object { $sel.ContainsKey([int]$_.uma) }) } }
$finished=($chOf.Count -gt 0)
[ordered]@{ date=$date; venue=$Venue; race=$Race; post=$post; dist=$dist; kind=$kind; raceName=$rn2; finished=$finished; dates=$dates; venues=$venues; races=$races; prevRace=$prevRace; nextRace=$nextRace; horses=$horses } | ConvertTo-Json -Depth 7 -Compress
