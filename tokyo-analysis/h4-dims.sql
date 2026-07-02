SELECT sec, grp,
 COUNT(1) n,
 CAST(100.0*SUM(CASE WHEN fin=1 THEN 1.0 ELSE 0 END)/COUNT(1) AS decimal(4,1)) 勝率,
 CAST(100.0*SUM(CASE WHEN fin=1 THEN tan ELSE 0 END)/COUNT(1) AS decimal(5,0)) 単回収,
 CAST(100.0*SUM(CASE WHEN fin=1 AND yy=2022 THEN tan ELSE 0 END)/NULLIF(SUM(CASE WHEN yy=2022 THEN 1 ELSE 0 END),0) AS decimal(5,0)) y22,
 CAST(100.0*SUM(CASE WHEN fin=1 AND yy=2023 THEN tan ELSE 0 END)/NULLIF(SUM(CASE WHEN yy=2023 THEN 1 ELSE 0 END),0) AS decimal(5,0)) y23,
 CAST(100.0*SUM(CASE WHEN fin=1 AND yy=2024 THEN tan ELSE 0 END)/NULLIF(SUM(CASE WHEN yy=2024 THEN 1 ELSE 0 END),0) AS decimal(5,0)) y24,
 CAST(100.0*SUM(CASE WHEN fin=1 AND yy=2025 THEN tan ELSE 0 END)/NULLIF(SUM(CASE WHEN yy=2025 THEN 1 ELSE 0 END),0) AS decimal(5,0)) y25
FROM (
  SELECT *,
   CASE sgrp
    WHEN 'CLS' THEN cls
    WHEN 'AGE' THEN (CASE WHEN age<=2 THEN N'2歳' WHEN age=3 THEN N'3歳' WHEN age=4 THEN N'4歳' WHEN age=5 THEN N'5歳' ELSE N'6歳+' END)
    WHEN 'SEX' THEN sex
    WHEN 'ROT' THEN (CASE WHEN rotdays IS NULL THEN N'x_初' WHEN rotdays<=14 THEN N'1_連闘2週' WHEN rotdays<=28 THEN N'2_3-4週' WHEN rotdays<=56 THEN N'3_5-8週' WHEN rotdays<=120 THEN N'4_9-17週' ELSE N'5_休明18週+' END)
    WHEN 'DIST' THEN (CASE WHEN distdiff IS NULL THEN N'x' WHEN distdiff<=-400 THEN N'1_大幅短縮' WHEN distdiff<0 THEN N'2_短縮' WHEN distdiff=0 THEN N'3_同距離' WHEN distdiff<400 THEN N'4_延長' ELSE N'5_大幅延長' END)
    WHEN 'WAKU' THEN N'枠'+CAST(waku AS nvarchar)
   END grp, sgrp sec
  FROM dbo.tk_bt2
  CROSS JOIN (VALUES('CLS'),('AGE'),('SEX'),('ROT'),('DIST'),('WAKU')) s(sgrp)
) x
WHERE grp IS NOT NULL
GROUP BY sec, grp
HAVING COUNT(1)>=120
ORDER BY sec, grp;
