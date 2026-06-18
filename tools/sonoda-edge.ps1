$ErrorActionPreference = 'Stop'
$appsettings = Join-Path $PSScriptRoot '..\共通\appsettings.json'
$connStr = (Get-Content $appsettings -Raw -Encoding UTF8 | ConvertFrom-Json).ConnectionStrings.DefaultConnection

# 園田 妙味探索: 各出走馬に前走・前々走と単複払戻を結合し、シグナル別に 年×単勝回収/複勝回収/勝率 を算出。
# リーク無し(各馬の過去走と当該レースの実払戻のみ使用)。母数確保のため全距離・field>=7。
$sql = @"
WITH ent AS (
  SELECT r.開催日,r.レース番号,r.馬番,r.馬名,r.騎手,r.馬体重,r.馬体重増減,
         kk.着順 chaku,
         COUNT(*) OVER(PARTITION BY r.開催日,r.レース番号) field
  FROM レース情報 r
  JOIN 競走結果 kk ON kk.開催場所=N'園田' AND kk.開催日=r.開催日 AND kk.レース番号=r.レース番号 AND kk.馬番=r.馬番
  WHERE r.開催場所=N'園田' AND r.開催日>='2022-01-01' AND ISNUMERIC(kk.着順)=1 AND kk.着順>0
),
prev AS (
  SELECT e.開催日,e.レース番号,e.馬番,
    pr.開催日 p_date, pr.騎手 p_jk, pr.馬体重増減 p_dwt,
    ROW_NUMBER() OVER (PARTITION BY e.開催日,e.レース番号,e.馬番 ORDER BY pr.開催日 DESC,pr.レース番号 DESC) seq
  FROM ent e JOIN レース情報 pr ON pr.馬名=e.馬名 AND pr.開催日<e.開催日
),
j AS (
  SELECT e.*, p.p_date, p.p_jk, p.p_dwt,
    tan.金額 tanpay, fuk.金額 fukpay
  FROM ent e
  LEFT JOIN prev p ON p.開催日=e.開催日 AND p.レース番号=e.レース番号 AND p.馬番=e.馬番 AND p.seq=1
  LEFT JOIN 払戻金 tan ON tan.開催場所=N'園田' AND tan.開催日=e.開催日 AND tan.レース番号=e.レース番号 AND tan.馬券=N'単勝' AND LTRIM(RTRIM(tan.組番))=CAST(e.馬番 AS nvarchar)
  LEFT JOIN 払戻金 fuk ON fuk.開催場所=N'園田' AND fuk.開催日=e.開催日 AND fuk.レース番号=e.レース番号 AND fuk.馬券=N'複勝' AND LTRIM(RTRIM(fuk.組番))=CAST(e.馬番 AS nvarchar)
  WHERE e.field>=7
)
SELECT
  LEFT(CONVERT(varchar,開催日,112),4) yr,
  sig,
  COUNT(*) n,
  CAST(100.0*SUM(CASE WHEN chaku=1 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) win,
  CAST(100.0*SUM(ISNULL(CASE WHEN chaku=1 THEN tanpay ELSE 0 END,0))/(100.0*COUNT(*)) AS decimal(6,1)) tanROI,
  CAST(100.0*SUM(ISNULL(CASE WHEN chaku<=3 THEN fukpay ELSE 0 END,0))/(100.0*COUNT(*)) AS decimal(6,1)) fukROI
FROM (
  SELECT 開催日,chaku,tanpay,fukpay, sig FROM j
  CROSS APPLY (VALUES
    (N'00_all'),
    (CASE WHEN 馬体重増減<=-10 THEN N'01_今走減10以上' END),
    (CASE WHEN 馬体重増減<=-10 AND p_dwt<=-10 THEN N'02_2走連続減10' END),
    (CASE WHEN 馬体重増減>=10 THEN N'03_今走増10以上' END),
    (CASE WHEN p_jk IS NOT NULL AND p_jk<>騎手 THEN N'04_乗替' END),
    (CASE WHEN p_date IS NOT NULL AND DATEDIFF(day,p_date,開催日)>=43 THEN N'05_休養明け43+' END),
    (CASE WHEN 騎手=N'吉村智' THEN N'06_吉村智' END)
  ) v(sig)
  WHERE sig IS NOT NULL
) z
GROUP BY LEFT(CONVERT(varchar,開催日,112),4), sig
ORDER BY sig, yr
"@
$conn = New-Object System.Data.SqlClient.SqlConnection($connStr); $conn.Open()
$cmd=$conn.CreateCommand(); $cmd.CommandTimeout=600; $cmd.CommandText=$sql
$r=$cmd.ExecuteReader(); $t=New-Object System.Data.DataTable; $t.Load($r)
$out = Join-Path $PSScriptRoot '_sonoda_edge.csv'
$t | Export-Csv -Path $out -NoTypeInformation -Encoding UTF8
Write-Host "saved: $out  rows=$($t.Rows.Count)"
$conn.Close()
