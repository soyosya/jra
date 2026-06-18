<#
.SYNOPSIS
  dbo.投票履歴 を集計表示。実投票(結果=投票完了)の回収率と、全推奨の“買っていたら”回収率を出す。
.PARAMETER Date/From/To/Venue  期間・場で絞り込み。未指定なら全件。
.PARAMETER Recent  直近表示行数(既定20)。
#>
[CmdletBinding()]
param(
  [string]$Date='', [string]$From='', [string]$To='', [string]$Venue='', [int]$Recent=20
)
$ErrorActionPreference='Stop'
$root = Split-Path $PSScriptRoot -Parent
$connStr=(Get-Content (Join-Path $root '共通\appsettings.json') -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
function Q($sql,[hashtable]$p){
  $cn=New-Object System.Data.SqlClient.SqlConnection $connStr; $cn.Open()
  try{ $cmd=$cn.CreateCommand(); $cmd.CommandText=$sql
       if($p){ foreach($k in $p.Keys){ [void]$cmd.Parameters.AddWithValue($k,$p[$k]) } }
       $dt=New-Object System.Data.DataTable; (New-Object System.Data.SqlClient.SqlDataAdapter $cmd).Fill($dt)|Out-Null; ,$dt }
  finally{ $cn.Close() }
}
$w="1=1"; $p=@{}
if($Date){ $w+=" AND 開催日=@d"; $p['@d']=$Date }
if($From){ $w+=" AND 開催日>=@f"; $p['@f']=$From }
if($To){   $w+=" AND 開催日<=@t"; $p['@t']=$To }
if($Venue){$w+=" AND 場名=@v"; $p['@v']=$Venue }

Write-Host "===== 投票履歴 サマリ ($w) ====="
# 実投票(結果=投票完了)の回収
$act = (Q "SELECT
   COUNT(*) AS 投票数,
   SUM(CASE WHEN 確定済=1 THEN 1 ELSE 0 END) AS 確定数,
   SUM(CASE WHEN 確定済=1 AND 的中=1 THEN 1 ELSE 0 END) AS 的中数,
   SUM(投票金額) AS 投票額,
   SUM(CASE WHEN 的中=1 THEN 払戻金 ELSE 0 END) AS 払戻額
 FROM dbo.投票履歴 WHERE $w AND 結果=N'投票完了'" $p).Rows
# 推奨(買っていたら=確定済・推奨外を除く)
$cf = (Q "SELECT
   COUNT(*) AS 推奨数,
   SUM(CASE WHEN 的中=1 THEN 1 ELSE 0 END) AS 的中数,
   SUM(投票金額) AS 投票額,
   SUM(CASE WHEN 的中=1 THEN 払戻金 ELSE 0 END) AS 払戻額
 FROM dbo.投票履歴 WHERE $w AND 確定済=1 AND 結果<>N'推奨外'" $p).Rows
# 推奨外(フィルタで除外したレース=買わなかった判断の検証)
$rj = (Q "SELECT
   COUNT(*) AS 推奨外数,
   SUM(CASE WHEN 的中=1 THEN 1 ELSE 0 END) AS 的中数,
   SUM(投票金額) AS 投票額,
   SUM(CASE WHEN 的中=1 THEN 払戻金 ELSE 0 END) AS 払戻額
 FROM dbo.投票履歴 WHERE $w AND 確定済=1 AND 結果=N'推奨外'" $p).Rows

function Pct($n,$d){ if($d -gt 0){ '{0:N1}%' -f (100.0*$n/$d) } else { '-' } }
function Nz($v){ if($null -eq $v -or $v -is [System.DBNull]){ 0 } else { $v } }
$a=$act[0]; $c=$cf[0]; $j=$rj[0]
$aHit=[int](Nz $a.的中数); $aDone=[int](Nz $a.確定数); $aInv=[int](Nz $a.投票額); $aRet=[int](Nz $a.払戻額)
$cHit=[int](Nz $c.的中数); $cRec=[int](Nz $c.推奨数); $cInv=[int](Nz $c.投票額); $cRet=[int](Nz $c.払戻額)
$jHit=[int](Nz $j.的中数); $jRec=[int](Nz $j.推奨外数); $jInv=[int](Nz $j.投票額); $jRet=[int](Nz $j.払戻額)
Write-Host ("[実投票] 投票{0} / 確定{1} / 的中{2} ({3}) / 投票額{4:N0}円 払戻{5:N0}円 回収率 {6}" -f `
  [int](Nz $a.投票数),$aDone,$aHit,(Pct $aHit $aDone),$aInv,$aRet,(Pct $aRet $aInv))
Write-Host ("[推奨]   確定{0} / 的中{1} ({2}) / 投票額{3:N0}円 払戻{4:N0}円 回収率 {5}  ※買っていたら" -f `
  $cRec,$cHit,(Pct $cHit $cRec),$cInv,$cRet,(Pct $cRet $cInv))
Write-Host ("[推奨外] 確定{0} / 的中{1} ({2}) / would-be額{3:N0}円 払戻{4:N0}円 回収率 {5}  ※除外判断の検証" -f `
  $jRec,$jHit,(Pct $jHit $jRec),$jInv,$jRet,(Pct $jRet $jInv))

Write-Host "`n----- 式別 × 結果 別 件数 -----"
(Q "SELECT 式別,結果,COUNT(*) AS 件数,SUM(投票金額) AS 金額 FROM dbo.投票履歴 WHERE $w GROUP BY 式別,結果 ORDER BY 式別,結果" $p).Rows |
  Format-Table 式別,結果,件数,金額 -Auto | Out-String | Write-Host

Write-Host "----- 直近 $Recent 行 -----"
(Q "SELECT TOP $Recent 開催日,場名,レース番号 AS R,式別,軸馬番 AS 軸,相手馬番 AS 相手,投票金額 AS 額,モード,結果,確定済 AS 確,的中,払戻金 AS 払戻 FROM dbo.投票履歴 WHERE $w ORDER BY Id DESC" $p).Rows |
  Format-Table 開催日,場名,R,式別,軸,相手,額,モード,結果,確,的中,払戻 -Auto | Out-String | Write-Host
