-- (A)全馬オッズ帯別単回収  (B)精製: コンピ上位6×乖離+3×ミドルオッズ  年別
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
      WHEN 'ODDSALL' THEN (CASE WHEN tan<1.5 THEN N'a_~1.4' WHEN tan<2 THEN N'b_1.5-1.9' WHEN tan<3 THEN N'c_2-2.9' WHEN tan<5 THEN N'd_3-4.9' WHEN tan<7 THEN N'e_5-6.9' WHEN tan<10 THEN N'f_7-9.9' WHEN tan<20 THEN N'g_10-19' WHEN tan<50 THEN N'h_20-49' ELSE N'i_50+' END)
      WHEN 'REFINE' THEN (CASE WHEN idxrank<=6 AND (pop-idxrank)>=3 AND tan>=4 AND tan<20 THEN N'コンピ6位内×乖離3×4-20倍' ELSE NULL END)
      WHEN 'REFINE2' THEN (CASE WHEN idxrank<=6 AND (pop-idxrank)>=2 AND tan>=3 AND tan<15 THEN N'コンピ6位内×乖離2×3-15倍' ELSE NULL END)
    END grp, sgrp sec
  FROM dbo.tk_bt
  CROSS JOIN (VALUES('ODDSALL'),('REFINE'),('REFINE2')) s(sgrp)
) x
WHERE grp IS NOT NULL
GROUP BY sec, grp
HAVING COUNT(1)>=50
ORDER BY sec, grp;
