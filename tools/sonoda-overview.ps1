$ErrorActionPreference = 'Stop'
$appsettings = Join-Path $PSScriptRoot '..\共通\appsettings.json'
$connStr = (Get-Content $appsettings -Raw -Encoding UTF8 | ConvertFrom-Json).ConnectionStrings.DefaultConnection
$conn = New-Object System.Data.SqlClient.SqlConnection($connStr); $conn.Open()
function Q($sql){ $cmd=$conn.CreateCommand(); $cmd.CommandTimeout=120; $cmd.CommandText=$sql; $r=$cmd.ExecuteReader(); $t=New-Object System.Data.DataTable; $t.Load($r); return $t }

$base = "FROM レース情報 WHERE 開催場所=N'園田' AND 開催日>='2022-01-01'"

Write-Host "=== 距離別 レース数(2022以降) ==="
Q "SELECT 距離, COUNT(DISTINCT CONCAT(開催日,'-',レース番号)) races $base GROUP BY 距離 ORDER BY races DESC" | Format-Table -Auto

Write-Host "=== 条件別 TOP15 ==="
Q "SELECT 条件, COUNT(DISTINCT CONCAT(開催日,'-',レース番号)) races $base GROUP BY 条件 ORDER BY races DESC" | Select-Object -First 15 | Format-Table -Auto

Write-Host "=== 距離x条件 TOP15 ==="
Q "SELECT 距離, 条件, COUNT(DISTINCT CONCAT(開催日,'-',レース番号)) races $base GROUP BY 距離,条件 ORDER BY races DESC" | Select-Object -First 15 | Format-Table -Auto

$conn.Close()
