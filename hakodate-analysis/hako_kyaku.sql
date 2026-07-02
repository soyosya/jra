SET NOCOUNT ON;
IF OBJECT_ID('tempdb..#t') IS NOT NULL DROP TABLE #t;
SELECT k.着順 fin, k.四コーナー c4, ri.コース種別 surf, ri.距離 dist, YEAR(k.開催日) y,
  COUNT(1) OVER(PARTITION BY k.開催日,k.レース番号) fld
INTO #t
FROM 競走結果 k
JOIN レース情報 ri ON ri.開催場所=k.開催場所 AND ri.開催日=k.開催日 AND ri.レース番号=k.レース番号 AND ri.馬番=k.馬番
WHERE k.開催場所=N'函館' AND k.着順>0 AND k.四コーナー>0 AND ri.コース種別 IN(N'芝',N'ダ');

IF OBJECT_ID('tempdb..#k') IS NOT NULL DROP TABLE #k;
SELECT fin, y, surf, dist, fld, c4, CAST(c4 AS float)/fld posr,
  CASE WHEN c4=1 THEN N'1_逃げ' WHEN CAST(c4 AS float)/fld<=0.33 THEN N'2_先行'
       WHEN CAST(c4 AS float)/fld<=0.66 THEN N'3_差し' ELSE N'4_追込' END kyaku
INTO #k FROM #t;

SELECT N'全体' lvl, kyaku, COUNT(1) n,
 CAST(100.0*SUM(CASE WHEN fin=1 THEN 1.0 ELSE 0 END)/COUNT(1) AS decimal(4,1)) 勝率,
 CAST(100.0*SUM(CASE WHEN fin<=3 THEN 1.0 ELSE 0 END)/COUNT(1) AS decimal(4,1)) 複勝率,
 CAST((1.0*SUM(CASE WHEN fin=1 THEN 1.0 ELSE 0 END)/COUNT(1))/(SELECT 1.0*SUM(CASE WHEN fin=1 THEN 1.0 ELSE 0 END)/COUNT(1) FROM #k) AS decimal(4,2)) 勝IV
FROM #k GROUP BY kyaku ORDER BY kyaku;

SELECT surf+CAST(dist AS varchar) lvl, kyaku, COUNT(1) n,
 CAST(100.0*SUM(CASE WHEN fin=1 THEN 1.0 ELSE 0 END)/COUNT(1) AS decimal(4,1)) 勝率,
 CAST(100.0*SUM(CASE WHEN fin<=3 THEN 1.0 ELSE 0 END)/COUNT(1) AS decimal(4,1)) 複勝率
FROM #k WHERE (surf=N'芝' AND dist IN(1200,1800)) OR (surf=N'ダ' AND dist IN(1700,1000))
GROUP BY surf,dist,kyaku ORDER BY surf,dist,kyaku;

SELECT surf+CAST(dist AS varchar) lvl, COUNT(1) wins, CAST(AVG(posr) AS decimal(4,3)) 勝位置率, CAST(AVG(CAST(c4 AS float)) AS decimal(4,1)) 勝平均四角
FROM #k WHERE fin=1 AND ((surf=N'芝' AND dist IN(1200,1800)) OR (surf=N'ダ' AND dist IN(1700,1000)))
GROUP BY surf,dist ORDER BY surf,dist;

-- 全体 逃げ勝率 年別頑健性
SELECT y, COUNT(1) n_runs,
 CAST(100.0*SUM(CASE WHEN kyaku=N'1_逃げ' AND fin=1 THEN 1.0 ELSE 0 END)/NULLIF(SUM(CASE WHEN kyaku=N'1_逃げ' THEN 1.0 ELSE 0 END),0) AS decimal(4,1)) 逃げ勝率,
 CAST(100.0*SUM(CASE WHEN kyaku IN(N'1_逃げ',N'2_先行') AND fin<=3 THEN 1.0 ELSE 0 END)/NULLIF(SUM(CASE WHEN kyaku IN(N'1_逃げ',N'2_先行') THEN 1.0 ELSE 0 END),0) AS decimal(4,1)) 前々複勝率
FROM #k GROUP BY y ORDER BY y;
