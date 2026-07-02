<#
.SYNOPSIS
  JRA(中央) 妙味カード。地方で確立した統合ロジック(拮抗×乗替穴軸∩地力, トラジェクトリ信頼/危険ラベル)をJRAへ。
  ★TOP騎手は「昨年の同競馬場・同時期(±45日)の複勝率順位」と「現在の過去4ヶ月のJRA全体の複勝率順位」を
   パーセンタイルで総合評価(各0.5)。現役判定として過去4ヶ月の騎乗(>=50)を必須=引退/不在騎手を自動除外。
  当日開催の全JRA場を処理。★JRAは複数場が同レース番号で開催→全結合に開催場所を必須化。
.PARAMETER Date     対象日(既定=今日)
.PARAMETER Geriki   地力: '≤6'(既定)/'4-6'/'全'
.PARAMETER SDThresh 拮抗の指数SD閾値(0=場別中央値を自動算出)
.PARAMETER ExportBets 買い目CSV(任意)
#>
[CmdletBinding()]
param([string]$Date=(Get-Date).ToString('yyyy-MM-dd'),[ValidateSet('≤6','4-6','全')][string]$Geriki='≤6',[double]$SDThresh=0,[string]$ExportBets='')
$ErrorActionPreference='Stop'
$cs=(Get-Content 'C:\jra\共通\appsettings.json' -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
$cn=New-Object System.Data.SqlClient.SqlConnection $cs; $cn.Open()
function JQ($sql,$p){ $cmd=$cn.CreateCommand(); $cmd.CommandText=$sql; if($p){foreach($k in $p.Keys){[void]$cmd.Parameters.AddWithValue($k,$p[$k])}}; $da=New-Object System.Data.SqlClient.SqlDataAdapter($cmd); $dt=New-Object System.Data.DataTable; $da.Fill($dt)|Out-Null; ,$dt }
function NN($x){ $x -ne $null -and $x -ne [DBNull]::Value }
function Traj($i0,$i1,$i2){ if($null -eq $i0 -or $null -eq $i1){return ''}; $d1=$i0-$i1; $d2= if($null -ne $i2){$i1-$i2}else{$null}
  if($null -ne $d2 -and $d1 -ge 4 -and $d2 -ge 4){'↑↑信頼(連続上昇)'} elseif($d1 -ge 4){'↑信頼(直近上昇)'}
  elseif($null -ne $d2 -and $d1 -le -4 -and $d2 -le -4){'↓↓危険(連続下降)'} elseif($d1 -le -4){'↓警戒(直近下降)'} else{''} }
# --- 総合評価TOP ---
function Get-CombinedTop($v){
  $A=@{}; foreach($x in (JQ "SELECT ri.騎手 j,COUNT(*) c,SUM(CASE WHEN k.着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END) p FROM 競走結果 k JOIN レース情報 ri ON ri.開催場所=k.開催場所 AND ri.開催日=k.開催日 AND ri.レース番号=k.レース番号 AND ri.馬番=k.馬番 WHERE k.開催場所=@v AND k.着順>=1 AND k.開催日 BETWEEN DATEADD(day,-45,DATEADD(year,-1,@d)) AND DATEADD(day,45,DATEADD(year,-1,@d)) GROUP BY ri.騎手" @{'@v'=$v;'@d'=$Date}).Rows){ if([int]$x.c -ge 10){ $A["$($x.j)".Trim()]=[double]$x.p/[double]$x.c } }
  $B=@{}; foreach($x in (JQ "SELECT ri.騎手 j,COUNT(*) c,SUM(CASE WHEN k.着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END) p FROM 競走結果 k JOIN レース情報 ri ON ri.開催場所=k.開催場所 AND ri.開催日=k.開催日 AND ri.レース番号=k.レース番号 AND ri.馬番=k.馬番 WHERE k.着順>=1 AND k.開催日 BETWEEN DATEADD(month,-4,@d) AND @d GROUP BY ri.騎手" @{'@d'=$Date}).Rows){ if([int]$x.c -ge 50){ $B["$($x.j)".Trim()]=[double]$x.p/[double]$x.c } }
  if($B.Count -eq 0){ return ,@() }
  # パーセンタイル(0=最良)
  function Pct($h){ $o=@{}; $ks=@($h.Keys|Sort-Object {$h[$_]} -Descending); $n=$ks.Count; for($i=0;$i -lt $n;$i++){ $o[$ks[$i]]= if($n -gt 1){$i/($n-1)}else{0} }; $o }
  $pB=Pct $B; $pA=Pct $A
  $score=@{}; foreach($j in $B.Keys){ $score[$j]= 0.5*$pB[$j] + 0.5*$(if($pA.ContainsKey($j)){$pA[$j]}else{0.5}) }
  ,@($score.Keys|Sort-Object {$score[$_]}|Select-Object -First 10)
}
# 当日開催のJRA場
$tracks=@((JQ "SELECT DISTINCT 開催場所 v FROM コンピ指数 WHERE 開催日=@d" @{'@d'=$Date}).Rows | %{ "$($_.v)".Trim() })
if($tracks.Count -eq 0){ Write-Host "[$Date] JRA出走データなし"; $cn.Close(); return }
$bets=@()
foreach($V in $tracks){
  $TOP=Get-CombinedTop $V
  if($TOP.Count -eq 0){ Write-Host "[$V] TOP騎手算出不可"; continue }
  # SD中央値(過去2年, 場別)
  $thr=$SDThresh
  if($thr -le 0){ $sds=@((JQ "WITH c AS (SELECT 開催日 d,レース番号 r,馬番 u,指数,ROW_NUMBER() OVER(PARTITION BY 開催日,レース番号,馬番 ORDER BY 取得日時 DESC) sn FROM コンピ指数 WHERE 開催場所=@v AND 指数 IS NOT NULL AND 開催日>=DATEADD(year,-2,@d) AND 開催日<@d) SELECT STDEVP(CAST(指数 AS float)) sd FROM c WHERE sn=1 GROUP BY d,r HAVING COUNT(*)>=6" @{'@v'=$V;'@d'=$Date}).Rows | %{[double]$_.sd} | Sort-Object); $thr= if($sds.Count){$sds[[int]($sds.Count/2)]}else{12.0} }
  $rows=@((JQ @"
WITH cmp AS (SELECT 開催場所 v,開催日 d,レース番号 r,馬番 u,馬名 h,指数 idx,指数順位 rk, ROW_NUMBER() OVER(PARTITION BY 開催場所,開催日,レース番号,馬番 ORDER BY 取得日時 DESC) sn FROM コンピ指数 WHERE 指数 IS NOT NULL AND 開催日<=@d),
c2 AS (SELECT v,d,r,u,h,idx,rk FROM cmp WHERE sn=1),
ri AS (SELECT 開催場所 v,開催日 d,レース番号 r,馬番 u,MAX(騎手) jk FROM レース情報 GROUP BY 開催場所,開催日,レース番号,馬番),
b AS (SELECT c2.*, ri.jk FROM c2 LEFT JOIN ri ON ri.v=c2.v AND ri.d=c2.d AND ri.r=c2.r AND ri.u=c2.u),
g AS (SELECT *, LAG(rk) OVER(PARTITION BY h ORDER BY d,r) pRk, LAG(rk,2) OVER(PARTITION BY h ORDER BY d,r) p2Rk, LAG(jk) OVER(PARTITION BY h ORDER BY d,r) pJk, LAG(idx) OVER(PARTITION BY h ORDER BY d,r) i1, LAG(idx,2) OVER(PARTITION BY h ORDER BY d,r) i2 FROM b)
SELECT r,u,h,idx,i1,i2,rk,jk,pRk,p2Rk,pJk FROM g WHERE v=@v AND d=@d ORDER BY r,rk
"@ @{'@v'=$V;'@d'=$Date}).Rows)
  if($rows.Count -eq 0){ continue }
  $byR=@{}; foreach($x in $rows){ if(-not $byR.ContainsKey([int]$x.r)){$byR[[int]$x.r]=@()}; $byR[[int]$x.r]+=$x }
  Write-Host "==== JRA $V 妙味カード $Date (地力=$Geriki/拮抗SD<=$([Math]::Round($thr,1))/TOP=$($TOP -join ',')) ===="
  foreach($rno in ($byR.Keys|Sort-Object)){ $fld=$byR[$rno]
    $idxs=@($fld|?{NN $_.idx}|%{[double]$_.idx}); if($idxs.Count -lt 2){continue}
    $mn=($idxs|Measure-Object -Average).Average; $vv=0.0; foreach($z in $idxs){$vv+=($z-$mn)*($z-$mn)}; $sd=[Math]::Sqrt($vv/$idxs.Count)
    if($sd -gt $thr){ continue }
    $axes=@(); foreach($h in $fld){ if(-not (NN $h.rk) -or [int]$h.rk -lt 4){continue}; if($TOP -notcontains "$($h.jk)".Trim()){continue}
      if(-not (NN $h.pJk) -or "$($h.pJk)".Trim() -eq '' -or "$($h.pJk)".Trim() -eq "$($h.jk)".Trim()){continue}
      $pr= if(NN $h.pRk){[int]$h.pRk}else{$null}; $p2= if(NN $h.p2Rk){[int]$h.p2Rk}else{$null}
      $best= if($null -ne $pr -and $null -ne $p2){[Math]::Min($pr,$p2)}elseif($null -ne $pr){$pr}elseif($null -ne $p2){$p2}else{$null}
      $gOK= switch($Geriki){ '全'{$true} '≤6'{$null -ne $best -and $best -le 6} '4-6'{$null -ne $best -and $best -ge 4 -and $best -le 6} }
      if(-not $gOK){continue}
      $tj=Traj $(if(NN $h.idx){[double]$h.idx}else{$null}) $(if(NN $h.i1){[double]$h.i1}else{$null}) $(if(NN $h.i2){[double]$h.i2}else{$null})
      $axes+=[pscustomobject]@{u=[int]$h.u;nm="$($h.h)";rk=[int]$h.rk;jk="$($h.jk)".Trim();best=$best;pr=$pr;traj=$tj} }
    if($axes.Count -lt 1){ continue }
    $aite=@($fld|?{(NN $_.rk) -and [int]$_.rk -ge 1 -and [int]$_.rk -le 3}|%{[pscustomobject]@{u=[int]$_.u;rk=[int]$_.rk;traj=(Traj $(if(NN $_.idx){[double]$_.idx}else{$null}) $(if(NN $_.i1){[double]$_.i1}else{$null}) $(if(NN $_.i2){[double]$_.i2}else{$null}))}})
    foreach($ax in $axes){ $ao=@($aite|?{$_.u -ne $ax.u})
      $aiteStr= if($ao.Count){ ($ao|%{ "{0}番(コンピ{1}位{2})" -f $_.u,$_.rk,$(if($_.traj){' '+$_.traj}else{''}) }) -join ', ' }else{'(該当なし=複勝のみ)'}
      Write-Host ("[{0,2}R] 拮抗(SD={1:N1}) ◎穴軸 {2}番 {3}(コンピ{4}位/{5}/前走{6}/地力{7}){8}" -f $rno,$sd,$ax.u,$ax.nm,$ax.rk,$ax.jk,$(if($null -ne $ax.pr){"$($ax.pr)位"}else{'-'}),$(if($null -ne $ax.best){"最高$($ax.best)位"}else{'-'}),$(if($ax.traj){' '+$ax.traj}else{''}))
      Write-Host ("        買い: ①{0}番の複勝  ②ワイド {0}番→{1}" -f $ax.u,$aiteStr)
      $bets+=[pscustomobject]@{venue=$V;date=$Date;race=$rno;type='複勝';axis=$ax.u;aite=''}
      foreach($a in $ao){ $bets+=[pscustomobject]@{venue=$V;date=$Date;race=$rno;type='ワイド';axis=$ax.u;aite=$a.u} } } }
}
$cn.Close()
Write-Host ("`n買い目計: {0}場 複勝{1}点・ワイド{2}点" -f (@($bets|Group-Object venue).Count),(@($bets|?{$_.type -eq '複勝'}).Count),(@($bets|?{$_.type -eq 'ワイド'}).Count))
if($ExportBets -ne ''){ $bets | Export-Csv -Path $ExportBets -NoTypeInformation -Encoding UTF8; Write-Host "CSV: $ExportBets" }
