$ErrorActionPreference = 'Stop'
$appsettings = Join-Path $PSScriptRoot '..\共通\appsettings.json'
$connStr = (Get-Content $appsettings -Raw -Encoding UTF8 | ConvertFrom-Json).ConnectionStrings.DefaultConnection
$conn = New-Object System.Data.SqlClient.SqlConnection($connStr); $conn.Open()
$From='2022-01-01'; $To='2026-06-14'

# 1400m: 騎手ごとの 前付け率(序盤位置top2=逃げ/先行) と 勝率/複勝率
$sql = @"
WITH j AS (
  SELECT ri.騎手, ri.馬番,
         cnt.n AS field,
         CAST(kk.着順 AS int) AS chaku,
         COALESCE(NULLIF(kk.一コーナー,0),NULLIF(kk.二コーナー,0),NULLIF(kk.三コーナー,0),NULLIF(kk.四コーナー,0)) early
  FROM レース情報 ri
  JOIN (SELECT 開催日,レース番号,COUNT(*) n FROM レース情報 WHERE 開催場所=N'園田' GROUP BY 開催日,レース番号) cnt
       ON cnt.開催日=ri.開催日 AND cnt.レース番号=ri.レース番号
  JOIN 競走結果 kk ON kk.開催場所=N'園田' AND kk.開催日=ri.開催日 AND kk.レース番号=ri.レース番号 AND kk.馬番=ri.馬番
  WHERE ri.開催場所=N'園田' AND ri.距離=1400 AND ri.開催日>=@From AND ri.開催日<=@To
    AND ISNUMERIC(kk.着順)=1 AND ri.騎手 IS NOT NULL
),
f AS (
  SELECT 騎手, field, chaku,
    CASE WHEN early IS NOT NULL AND CAST(early AS float)/field <= 0.22 THEN 1 ELSE 0 END AS isLead
  FROM j WHERE field>=6 AND early IS NOT NULL
)
SELECT TOP 25 騎手,
  COUNT(*) rides,
  CAST(100.0*SUM(isLead)/COUNT(*) AS decimal(5,1)) leadPct,
  CAST(100.0*SUM(CASE WHEN chaku=1 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) win,
  CAST(100.0*SUM(CASE WHEN chaku<=3 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) plc
FROM f
GROUP BY 騎手
HAVING COUNT(*)>=150
ORDER BY win DESC
"@
$cmd=$conn.CreateCommand(); $cmd.CommandTimeout=180; $cmd.CommandText=$sql
[void]$cmd.Parameters.AddWithValue('@From',$From); [void]$cmd.Parameters.AddWithValue('@To',$To)
$r=$cmd.ExecuteReader(); $t=New-Object System.Data.DataTable; $t.Load($r)
$out = Join-Path $PSScriptRoot '_sonoda_jockey_front.csv'
$t | Export-Csv -Path $out -NoTypeInformation -Encoding UTF8
Write-Host "saved: $out  rows=$($t.Rows.Count)"

$conn.Close()
