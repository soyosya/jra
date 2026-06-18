$ErrorActionPreference = 'Stop'
$appsettings = Join-Path $PSScriptRoot '..\共通\appsettings.json'
$connStr = (Get-Content $appsettings -Raw -Encoding UTF8 | ConvertFrom-Json).ConnectionStrings.DefaultConnection
$conn = New-Object System.Data.SqlClient.SqlConnection($connStr); $conn.Open()
function Q($sql){ $cmd=$conn.CreateCommand(); $cmd.CommandTimeout=180; $cmd.CommandText=$sql; $r=$cmd.ExecuteReader(); $t=New-Object System.Data.DataTable; $t.Load($r); return $t }

# 競走結果(着順)と レース情報(馬番/騎手/距離/頭数) を 開催場所+開催日+レース番号+馬番 で結合
# 期間 2022-2025(複数年安定)。From/To は記述目的。
$From='2022-01-01'; $To='2026-06-14'

Write-Host "=== 枠順(馬番相対位置)別 勝率/複勝率  距離別  園田 $From..$To ==="
$sql = @"
WITH j AS (
  SELECT ri.開催日, ri.レース番号, ri.距離, ri.馬番,
         cnt.n AS field,
         CAST(kk.着順 AS int) AS chaku
  FROM レース情報 ri
  JOIN (SELECT 開催日,レース番号,COUNT(*) n FROM レース情報 WHERE 開催場所=N'園田' GROUP BY 開催日,レース番号) cnt
       ON cnt.開催日=ri.開催日 AND cnt.レース番号=ri.レース番号
  JOIN 競走結果 kk ON kk.開催場所=N'園田' AND kk.開催日=ri.開催日 AND kk.レース番号=ri.レース番号 AND kk.馬番=ri.馬番
  WHERE ri.開催場所=N'園田' AND ri.開催日>=@From AND ri.開催日<=@To
    AND ISNUMERIC(kk.着順)=1 AND ri.馬番 IS NOT NULL
),
p AS (
  SELECT 距離,
    CASE WHEN CAST(馬番 AS float)/field <= 0.34 THEN '1内'
         WHEN CAST(馬番 AS float)/field <= 0.67 THEN '2中'
         ELSE '3外' END AS zone,
    chaku
  FROM j WHERE field>=5
)
SELECT 距離, zone,
  COUNT(*) n,
  CAST(100.0*SUM(CASE WHEN chaku=1 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) win,
  CAST(100.0*SUM(CASE WHEN chaku<=3 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) plc
FROM p
WHERE 距離 IN (820,1230,1400,1700,1870)
GROUP BY 距離, zone
ORDER BY 距離, zone
"@
$cmd=$conn.CreateCommand(); $cmd.CommandTimeout=180; $cmd.CommandText=$sql
[void]$cmd.Parameters.AddWithValue('@From',$From); [void]$cmd.Parameters.AddWithValue('@To',$To)
$r=$cmd.ExecuteReader(); $t=New-Object System.Data.DataTable; $t.Load($r); $t | Format-Table -Auto

$conn.Close()
