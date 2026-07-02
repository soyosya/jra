-- 軸=コンピ1位 の単勝回収。人気乖離/オッズ帯/コンピΔ/コース/馬場 で年別。
-- 単勝控除率≒80%。pooled>100かつ年別一貫を狙う。
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
    CASE
      WHEN sgrp='POP' THEN (CASE WHEN pop=1 THEN N'1_人気1' WHEN pop=2 THEN N'2_人気2' WHEN pop=3 THEN N'3_人気3' ELSE N'4_人気4+' END)
      WHEN sgrp='ODDS' THEN (CASE WHEN tan<2 THEN N'a_~1.9' WHEN tan<3 THEN N'b_2-2.9' WHEN tan<4 THEN N'c_3-3.9' WHEN tan<6 THEN N'd_4-5.9' WHEN tan<10 THEN N'e_6-9.9' ELSE N'f_10+' END)
      WHEN sgrp='DELTA' THEN (CASE WHEN compidelta IS NULL THEN N'x_無' WHEN compidelta>=5 THEN N'1_+5以上' WHEN compidelta>=1 THEN N'2_+1~4' WHEN compidelta=0 THEN N'3_0' WHEN compidelta>=-4 THEN N'4_-1~-4' ELSE N'5_-5以下' END)
      WHEN sgrp='SURF' THEN surf
      WHEN sgrp='BABA' THEN baba
    END grp, sgrp AS sec
  FROM dbo.tk_bt
  CROSS JOIN (VALUES('POP'),('ODDS'),('DELTA'),('SURF'),('BABA')) AS s(sgrp)
  WHERE idxrank=1
) x
GROUP BY sec, grp
HAVING COUNT(1)>=40
ORDER BY sec, grp;
