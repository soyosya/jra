<#
  厩舎の話◎×コンピ下位の単勝+EVの頑健性検証。年別+外れ値除去(大穴1発依存か)+band感応度(コ6+/7+/8+/10+)。
  各厩舎◎馬(コンピ順位≥閾値)の{年,着順,単勝払戻}を収集→単勝回収を年別+上位払戻除外で評価。
#>
[CmdletBinding()] param([string]$From='2023-01-01',[int]$Stake=100)
$ErrorActionPreference='Stop'
try{ [Console]::OutputEncoding=[Text.Encoding]::UTF8 }catch{}
$cs=(Get-Content 'C:\jra\共通\appsettings.json' -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
$conn=New-Object System.Data.SqlClient.SqlConnection($cs);$conn.Open()
function Q($sql){ $c=$conn.CreateCommand();$c.CommandText=$sql;$c.CommandTimeout=300;$dt=New-Object System.Data.DataTable;(New-Object System.Data.SqlClient.SqlDataAdapter $c).Fill($dt)|Out-Null;,$dt.Rows }
function K($v,$d,$r,$x){ '{0}|{1}|{2}|{3}' -f $v,([datetime]$d).ToString('yyyy-MM-dd'),[int]$r,$x }
$maru=@{}; foreach($x in (Q "SELECT DISTINCT 開催場所 v,開催日 d,レース番号 r,馬名 nm FROM dbo.厩舎の話 WHERE 開催日>='$From' AND 印=N'◎'")){ $maru[(K $x.v $x.d $x.r $x.nm)]=$true }
$crk=@{}; foreach($x in (Q "SELECT 開催場所 v,開催日 d,レース番号 r,馬番 no,指数順位 rk FROM (SELECT 開催場所,開催日,レース番号,馬番,指数順位,ROW_NUMBER() OVER(PARTITION BY 開催場所,開催日,レース番号,馬番 ORDER BY 取得日時 DESC) sn FROM dbo.コンピ指数 WHERE 開催日>='$From' AND 指数順位 IS NOT NULL) t WHERE sn=1")){ $crk[(K $x.v $x.d $x.r $x.no)]=[int]$x.rk }
$tan=@{}; foreach($x in (Q "SELECT 開催場所 v,開催日 d,レース番号 r,組番 kb,TRY_CAST(金額 AS int) kin FROM dbo.払戻金 WHERE 開催日>='$From' AND 馬券=N'単勝'")){ $no=0; if([int]::TryParse(("$($x.kb)").Trim(),[ref]$no)){ $tan[(K $x.v $x.d $x.r $no)]=[int]$x.kin } }

# 厩舎◎馬の{年,コンピ順位,着順,単勝払戻}収集
$bets=New-Object System.Collections.Generic.List[object]
foreach($x in (Q "SELECT 開催場所 v,開催日 d,レース番号 r,馬番 no,馬名 nm,TRY_CONVERT(int,着順) ch FROM dbo.競走結果 WHERE 開催日>='$From' AND TRY_CONVERT(int,着順)>0")){
  $knm=(K $x.v $x.d $x.r ([string]$x.nm)); if(-not $maru.ContainsKey($knm)){continue}
  $kf=(K $x.v $x.d $x.r ([int]$x.no)); $rk= if($crk.ContainsKey($kf)){$crk[$kf]}else{$null}; if($null -eq $rk){continue}
  $ch=[int]$x.ch; $bets.Add([pscustomobject]@{ y=([datetime]$x.d).Year; rk=$rk; won=($ch -eq 1); tanp=$(if($ch -eq 1 -and $tan.ContainsKey($kf)){$tan[$kf]}else{0}) })
}
Write-Host ("厩舎◎(コンピ順位あり) 総数: $($bets.Count)")
function Pc($a,$b){ if($b){'{0,6:P1}' -f ($a/$b)}else{'   — '} }
foreach($thr in @(6,7,8,10)){
  $sub=@($bets | Where-Object { $_.rk -ge $thr })
  if($sub.Count -eq 0){ continue }
  $n=$sub.Count; $inv=$n*$Stake; $ret=($sub|Measure-Object tanp -Sum).Sum; $wins=@($sub|Where-Object{$_.won}).Count
  Write-Host ""
  Write-Host ("=== 厩舎◎ × コンピ{0}位以下 : n={1} 勝率{2} 単勝回収{3} ===" -f $thr,$n,(Pc $wins $n),(Pc $ret $inv))
  foreach($y in (2023..2026)){ $ys=@($sub|Where-Object{$_.y -eq $y}); if($ys.Count -eq 0){continue}; $yr=($ys|Measure-Object tanp -Sum).Sum; Write-Host ("   {0}: n={1,4} 勝{2} 単回{3}" -f $y,$ys.Count,(Pc (@($ys|Where-Object{$_.won}).Count) $ys.Count),(Pc $yr ($ys.Count*$Stake))) }
  $sorted=@($sub|Sort-Object tanp -Descending); $top1=$sorted[0].tanp; $top3=(@($sorted|Select-Object -First 3|Measure-Object tanp -Sum).Sum)
  Write-Host ("   最大単勝払戻={0} / 単回(上位1除外)={1} / 単回(上位3除外)={2}" -f $top1,(Pc ($ret-$top1) $inv),(Pc ($ret-$top3) $inv))
}
$conn.Close()
