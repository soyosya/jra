-- 全出走馬。市場過小評価(コンピ順位 < 人気順位)で単勝+EVが出るか。年別。
-- valuegap = 人気 - 指数順位(正=コンピ評価より人気薄=妙味候補)
SELECT sec, grp,
 COUNT(1) n,
 CAST(100.0*SUM(CASE WHEN fin=1 THEN 1.0 ELSE 0 END)/COUNT(1) AS decimal(4,1)) 勝率,
 CAST(100.0*SUM(CASE WHEN fin<=3 THEN 1.0 ELSE 0 END)/COUNT(1) AS decimal(4,1)) 複率,
 CAST(100.0*SUM(CASE WHEN fin=1 THEN tan ELSE 0 END)/COUNT(1) AS decimal(5,0)) 単回収,
 CAST(100.0*SUM(CASE WHEN fin=1 AND yy=2022 THEN tan ELSE 0 END)/NULLIF(SUM(CASE WHEN yy=2022 THEN 1 ELSE 0 END),0) AS decimal(5,0)) y22,
 CAST(100.0*SUM(CASE WHEN fin=1 AND yy=2023 THEN tan ELSE 0 END)/NULLIF(SUM(CASE WHEN yy=2023 THEN 1 ELSE 0 END),0) AS decimal(5,0)) y23,
 CAST(100.0*SUM(CASE WHEN fin=1 AND yy=2024 THEN tan ELSE 0 END)/NULLIF(SUM(CASE WHEN yy=2024 THEN 1 ELSE 0 END),0) AS decimal(5,0)) y24,
 CAST(100.0*SUM(CASE WHEN fin=1 AND yy=2025 THEN tan ELSE 0 END)/NULLIF(SUM(CASE WHEN yy=2025 THEN 1 ELSE 0 END),0) AS decimal(5,0)) y25
FROM (
  SELECT *,
    CASE sgrp
      WHEN 'GAP' THEN (CASE WHEN (pop-idxrank)>=5 THEN N'1_乖離+5以上' WHEN (pop-idxrank)>=3 THEN N'2_乖離+3~4' WHEN (pop-idxrank)>=1 THEN N'3_乖離+1~2' WHEN (pop-idxrank)=0 THEN N'4_一致' ELSE N'5_負(過大評価)' END)
      WHEN 'TOP3GAP' THEN (CASE WHEN idxrank<=3 AND (pop-idxrank)>=3 THEN N'コンピ上位3×人気薄+3' ELSE N'他' END)
      WHEN 'DUP' THEN (CASE WHEN idxrank<=4 AND compidelta>=4 THEN N'コンピ上位4×Δ+4以上' ELSE N'他' END)
    END grp, sgrp sec
  FROM dbo.tk_bt
  CROSS JOIN (VALUES('GAP'),('TOP3GAP'),('DUP')) s(sgrp)
) x
WHERE grp IS NOT NULL AND grp NOT IN(N'他')
GROUP BY sec, grp
HAVING COUNT(1)>=60
ORDER BY sec, grp;
