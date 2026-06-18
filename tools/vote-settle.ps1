<#
.SYNOPSIS
  dbo.投票履歴 の未確定行(確定済=0)を、競走結果(着順上位3頭)と払戻金から精算する。
  3連複/3連単マルチ いずれも「軸が上位3着以内 かつ 残り2頭が相手に含まれる」で的中判定。
  払戻は払戻金テーブルの該当式別 金額(100円あたり)×(一点金額/100)。
  モード/結果に関わらず未確定行をすべて精算する(計画/見送りも“買っていたら”の検証として的中・払戻を残す)。
.PARAMETER Date  指定日のみ精算(yyyy-MM-dd)。未指定なら未確定行すべて。
.PARAMETER WhatIf  更新せず判定結果のみ表示。
#>
[CmdletBinding()]
param(
  [string]$Date = '',
  [switch]$WhatIf
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
function E($sql,[hashtable]$p){
  $cn=New-Object System.Data.SqlClient.SqlConnection $connStr; $cn.Open()
  try{ $cmd=$cn.CreateCommand(); $cmd.CommandText=$sql
       if($p){ foreach($k in $p.Keys){ [void]$cmd.Parameters.AddWithValue($k,$p[$k]) } }
       [void]$cmd.ExecuteNonQuery() }
  finally{ $cn.Close() }
}

$where = "確定済=0"
$qp = @{}
if($Date){ $where += " AND 開催日=@d"; $qp['@d']=$Date }
$rows = (Q "SELECT Id,開催日,場名,レース番号,式別,軸馬番,相手馬番,一点金額,結果 FROM dbo.投票履歴 WHERE $where ORDER BY 開催日,場名,レース番号" $qp).Rows
Write-Host ("未確定 {0} 件を精算します{1}" -f $rows.Count, $(if($WhatIf){' (WhatIf=更新なし)'}else{''}))

$settled=0; $pending=0; $hits=0
foreach($r in $rows){
  $id=[int]$r.Id; $ven=[string]$r.場名; $rno=[int]$r.レース番号; $type=[string]$r.式別
  $axis=[int]$r.軸馬番; $unit=[int]$r.一点金額
  $opp = @($r.相手馬番 -split ',' | ForEach-Object { [int]$_ })

  # 着順上位3頭(競走結果)
  $res = (Q "SELECT 馬番 FROM dbo.競走結果 WHERE 開催場所=@v AND 開催日=@d AND レース番号=@r AND 着順 BETWEEN 1 AND 3 ORDER BY 着順" `
            @{ '@v'=$ven; '@d'=$r.開催日; '@r'=$rno }).Rows
  if($res.Count -lt 3){ $pending++; continue }   # まだ結果未確定/未取込
  $top3 = @($res | ForEach-Object { [int]$_.馬番 })

  $others = @($top3 | Where-Object { $_ -ne $axis })
  $hit = ($top3 -contains $axis) -and ($others.Count -eq 2) -and (-not ($others | Where-Object { $opp -notcontains $_ }))

  $pay = 0
  if($hit){
    $pr = (Q "SELECT TOP 1 金額 FROM dbo.払戻金 WHERE 開催場所=@v AND 開催日=@d AND レース番号=@r AND 馬券 LIKE @t ORDER BY 金額 DESC" `
             @{ '@v'=$ven; '@d'=$r.開催日; '@r'=$rno; '@t'="%$type%" }).Rows
    if($pr.Count -ge 1){ $pay = [int]([decimal]$pr[0].金額 * ($unit/100.0)) }
    $hits++
  }
  Write-Host ("  {0} {1}R {2} 軸{3} 相手[{4}] 着順[{5}] → {6}{7}" -f `
    ([datetime]$r.開催日).ToString('MM/dd'),$rno,$type,$axis,($opp -join ','),($top3 -join ','),`
    $(if($hit){'的中'}else{'不的中'}),$(if($hit){" 払戻${pay}円"}else{''}))

  if(-not $WhatIf){
    E "UPDATE dbo.投票履歴 SET 確定済=1,的中=@h,払戻金=@p,確定日時=SYSDATETIME() WHERE Id=@id" `
      @{ '@h'=[int]$hit; '@p'=$pay; '@id'=$id }
  }
  $settled++
}
Write-Host ("=== 精算 {0} 件(的中 {1})/ 結果待ち {2} 件 ===" -f $settled,$hits,$pending)
