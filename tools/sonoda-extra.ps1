$ErrorActionPreference='Stop'
$appsettings = Join-Path $PSScriptRoot '..\共通\appsettings.json'
$connStr=(Get-Content $appsettings -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
$conn=New-Object System.Data.SqlClient.SqlConnection($connStr); $conn.Open()
function Run($sql,$csv){ $c=$conn.CreateCommand();$c.CommandTimeout=600;$c.CommandText=$sql;$r=$c.ExecuteReader();$t=New-Object System.Data.DataTable;$t.Load($r); $t|Export-Csv -Path (Join-Path $PSScriptRoot $csv) -NoTypeInformation -Encoding UTF8; Write-Host ("{0}: {1} rows" -f $csv,$t.Rows.Count) }

# (1) 馬場状態別 前残り(1400m, 脚質=序盤位置, 全期間)
Run @"
WITH k AS (
  SELECT r.馬場 baba,
    COALESCE(NULLIF(kk.一コーナー,0),NULLIF(kk.二コーナー,0),NULLIF(kk.三コーナー,0),NULLIF(kk.四コーナー,0)) early,
    COUNT(*) OVER(PARTITION BY kk.開催場所,kk.開催日,kk.レース番号) tou, kk.着順 c
  FROM 競走結果 kk JOIN レース情報 r ON r.開催場所=kk.開催場所 AND r.開催日=kk.開催日 AND r.レース番号=kk.レース番号 AND r.馬番=kk.馬番
  WHERE kk.開催場所=N'園田' AND r.距離=1400 AND kk.着順>0 AND kk.開催日>='2022-01-01')
SELECT ISNULL(baba,N'?') baba,
  CASE WHEN early IS NULL OR early=0 THEN N'?' WHEN early=1 THEN N'逃げ' WHEN early<=tou*0.33 THEN N'先行' WHEN early<=tou*0.66 THEN N'差し' ELSE N'追込' END kyaku,
  COUNT(*) n, CAST(100.0*SUM(CASE WHEN c=1 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) win
FROM k GROUP BY ISNULL(baba,N'?'),
  CASE WHEN early IS NULL OR early=0 THEN N'?' WHEN early=1 THEN N'逃げ' WHEN early<=tou*0.33 THEN N'先行' WHEN early<=tou*0.66 THEN N'差し' ELSE N'追込' END
ORDER BY baba, win DESC
"@ '_x_baba.csv'

# (2) 調教師 (rides>=100, 全期間, 単複回収・逃げ率)
Run @"
SELECT r.調教師 tr, COUNT(*) n,
  CAST(100.0*SUM(CASE WHEN kk.着順=1 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) win,
  CAST(100.0*SUM(CASE WHEN kk.着順<=3 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) plc,
  CAST(100.0*SUM(ISNULL(CASE WHEN kk.着順=1 THEN tan.金額 END,0))/(100.0*COUNT(*)) AS decimal(6,1)) tanROI,
  CAST(100.0*SUM(CASE WHEN COALESCE(NULLIF(kk.一コーナー,0),NULLIF(kk.二コーナー,0),NULLIF(kk.三コーナー,0),NULLIF(kk.四コーナー,0))=1 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) leadPct
FROM レース情報 r
JOIN 競走結果 kk ON kk.開催場所=r.開催場所 AND kk.開催日=r.開催日 AND kk.レース番号=r.レース番号 AND kk.馬番=r.馬番
LEFT JOIN 払戻金 tan ON tan.開催場所=N'園田' AND tan.開催日=r.開催日 AND tan.レース番号=r.レース番号 AND tan.馬券=N'単勝' AND LTRIM(RTRIM(tan.組番))=CAST(r.馬番 AS nvarchar)
WHERE r.開催場所=N'園田' AND kk.着順>0 AND r.開催日>='2022-01-01' AND r.調教師 IS NOT NULL
GROUP BY r.調教師 HAVING COUNT(*)>=100
ORDER BY tanROI DESC
"@ '_x_trainer.csv'

# (3) 馬主 (rides>=80, 単勝回収)
Run @"
SELECT r.馬主 ow, COUNT(*) n,
  CAST(100.0*SUM(CASE WHEN kk.着順=1 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) win,
  CAST(100.0*SUM(ISNULL(CASE WHEN kk.着順=1 THEN tan.金額 END,0))/(100.0*COUNT(*)) AS decimal(6,1)) tanROI,
  CAST(100.0*SUM(CASE WHEN COALESCE(NULLIF(kk.一コーナー,0),NULLIF(kk.二コーナー,0),NULLIF(kk.三コーナー,0),NULLIF(kk.四コーナー,0))=1 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) leadPct
FROM レース情報 r
JOIN 競走結果 kk ON kk.開催場所=r.開催場所 AND kk.開催日=r.開催日 AND kk.レース番号=r.レース番号 AND kk.馬番=r.馬番
LEFT JOIN 払戻金 tan ON tan.開催場所=N'園田' AND tan.開催日=r.開催日 AND tan.レース番号=r.レース番号 AND tan.馬券=N'単勝' AND LTRIM(RTRIM(tan.組番))=CAST(r.馬番 AS nvarchar)
WHERE r.開催場所=N'園田' AND kk.着順>0 AND r.開催日>='2022-01-01' AND r.馬主 IS NOT NULL
GROUP BY r.馬主 HAVING COUNT(*)>=80
ORDER BY tanROI DESC
"@ '_x_owner.csv'

# (4) 減量記号(有無) 年別 単複回収
Run @"
SELECT LEFT(CONVERT(varchar,r.開催日,112),4) yr,
  CASE WHEN r.減量記号 IS NULL OR LTRIM(RTRIM(r.減量記号))='' THEN N'無' ELSE N'減量' END genryo,
  COUNT(*) n, CAST(100.0*SUM(CASE WHEN kk.着順=1 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) win,
  CAST(100.0*SUM(ISNULL(CASE WHEN kk.着順=1 THEN tan.金額 END,0))/(100.0*COUNT(*)) AS decimal(6,1)) tanROI,
  CAST(100.0*SUM(ISNULL(CASE WHEN kk.着順<=3 THEN fuk.金額 END,0))/(100.0*COUNT(*)) AS decimal(6,1)) fukROI
FROM レース情報 r
JOIN 競走結果 kk ON kk.開催場所=r.開催場所 AND kk.開催日=r.開催日 AND kk.レース番号=r.レース番号 AND kk.馬番=r.馬番
LEFT JOIN 払戻金 tan ON tan.開催場所=N'園田' AND tan.開催日=r.開催日 AND tan.レース番号=r.レース番号 AND tan.馬券=N'単勝' AND LTRIM(RTRIM(tan.組番))=CAST(r.馬番 AS nvarchar)
LEFT JOIN 払戻金 fuk ON fuk.開催場所=N'園田' AND fuk.開催日=r.開催日 AND fuk.レース番号=r.レース番号 AND fuk.馬券=N'複勝' AND LTRIM(RTRIM(fuk.組番))=CAST(r.馬番 AS nvarchar)
WHERE r.開催場所=N'園田' AND kk.着順>0 AND r.開催日>='2022-01-01'
GROUP BY LEFT(CONVERT(varchar,r.開催日,112),4), CASE WHEN r.減量記号 IS NULL OR LTRIM(RTRIM(r.減量記号))='' THEN N'無' ELSE N'減量' END
ORDER BY genryo, yr
"@ '_x_genryo.csv'

# (5) 距離替わり & 昇降級(前走比) 年別 単複回収
Run @"
WITH ent AS (
  SELECT r.開催日 d, r.レース番号 rno, r.馬番 uma, r.馬名 nm, r.距離 dist, r.一着賞金 prize, kk.着順 c
  FROM レース情報 r JOIN 競走結果 kk ON kk.開催場所=r.開催場所 AND kk.開催日=r.開催日 AND kk.レース番号=r.レース番号 AND kk.馬番=r.馬番
  WHERE r.開催場所=N'園田' AND kk.着順>0 AND r.開催日>='2022-01-01'),
prev AS (
  SELECT e.d,e.rno,e.uma, pr.距離 p_dist, pr.一着賞金 p_prize,
    ROW_NUMBER() OVER(PARTITION BY e.d,e.rno,e.uma ORDER BY pr.開催日 DESC, pr.レース番号 DESC) seq
  FROM ent e JOIN レース情報 pr ON pr.馬名=e.nm AND pr.開催日<e.d)
SELECT LEFT(CONVERT(varchar,e.d,112),4) yr,
  CASE WHEN p.p_dist IS NULL THEN N'?' WHEN e.dist>p.p_dist THEN N'延長' WHEN e.dist<p.p_dist THEN N'短縮' ELSE N'同距離' END kyori,
  CASE WHEN p.p_prize IS NULL THEN N'?' WHEN e.prize>p.p_prize THEN N'昇級' WHEN e.prize<p.p_prize THEN N'降級' ELSE N'同級' END kurasu,
  COUNT(*) n, CAST(100.0*SUM(CASE WHEN e.c=1 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) win,
  CAST(100.0*SUM(ISNULL(CASE WHEN e.c=1 THEN tan.金額 END,0))/(100.0*COUNT(*)) AS decimal(6,1)) tanROI,
  CAST(100.0*SUM(ISNULL(CASE WHEN e.c<=3 THEN fuk.金額 END,0))/(100.0*COUNT(*)) AS decimal(6,1)) fukROI
FROM ent e
LEFT JOIN prev p ON p.d=e.d AND p.rno=e.rno AND p.uma=e.uma AND p.seq=1
LEFT JOIN 払戻金 tan ON tan.開催場所=N'園田' AND tan.開催日=e.d AND tan.レース番号=e.rno AND tan.馬券=N'単勝' AND LTRIM(RTRIM(tan.組番))=CAST(e.uma AS nvarchar)
LEFT JOIN 払戻金 fuk ON fuk.開催場所=N'園田' AND fuk.開催日=e.d AND fuk.レース番号=e.rno AND fuk.馬券=N'複勝' AND LTRIM(RTRIM(fuk.組番))=CAST(e.uma AS nvarchar)
GROUP BY LEFT(CONVERT(varchar,e.d,112),4),
  CASE WHEN p.p_dist IS NULL THEN N'?' WHEN e.dist>p.p_dist THEN N'延長' WHEN e.dist<p.p_dist THEN N'短縮' ELSE N'同距離' END,
  CASE WHEN p.p_prize IS NULL THEN N'?' WHEN e.prize>p.p_prize THEN N'昇級' WHEN e.prize<p.p_prize THEN N'降級' ELSE N'同級' END
ORDER BY kyori, kurasu, yr
"@ '_x_rotation.csv'

$conn.Close()
