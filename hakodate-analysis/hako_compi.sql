SET NOCOUNT ON;
IF OBJECT_ID('tempdb..#b') IS NOT NULL DROP TABLE #b;
SELECT r.開催日 d, r.レース番号 rn, r.馬番 no, r.着順 fin, r.枠番 waku,
       r.コース種別 ct, r.距離 dist, c.指数順位 crank, c.指数 cidx, c.頭数 ninzu,
       o.単勝オッズ tan, o.人気 pop
INTO #b
FROM レース情報 r
JOIN コンピ指数 c ON c.開催場所=r.開催場所 AND c.開催日=r.開催日 AND c.レース番号=r.レース番号 AND c.馬番=r.馬番
LEFT JOIN リアルタイムオッズ o ON o.開催場所=r.開催場所 AND o.開催日=r.開催日 AND o.レース番号=r.レース番号 AND o.馬番=r.馬番
WHERE r.開催場所='函館' AND r.着順>0;

SELECT 'A.コンピ1位 年別' grp, CAST(YEAR(d) AS varchar) k, COUNT(*) n,
  CAST(100.0*SUM(CASE WHEN fin=1 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) win,
  CAST(100.0*SUM(CASE WHEN fin<=3 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) plc,
  CAST(100.0*SUM(CASE WHEN fin=1 THEN tan ELSE 0 END)/(100.0*COUNT(*)) AS decimal(6,1)) roi
FROM #b WHERE crank=1 GROUP BY YEAR(d)
UNION ALL
SELECT 'A.コンピ1位 全体','ALL',COUNT(*),
  CAST(100.0*SUM(CASE WHEN fin=1 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)),
  CAST(100.0*SUM(CASE WHEN fin<=3 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)),
  CAST(100.0*SUM(CASE WHEN fin=1 THEN tan ELSE 0 END)/(100.0*COUNT(*)) AS decimal(6,1))
FROM #b WHERE crank=1
UNION ALL
SELECT 'B.人気1番 全体','ALL',COUNT(*),
  CAST(100.0*SUM(CASE WHEN fin=1 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)),
  CAST(100.0*SUM(CASE WHEN fin<=3 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)),
  CAST(100.0*SUM(CASE WHEN fin=1 THEN tan ELSE 0 END)/(100.0*COUNT(*)) AS decimal(6,1))
FROM #b WHERE pop=1
ORDER BY grp,k;

SELECT 'C.コンピ1位 コース距離別' grp, ct, dist, COUNT(*) n,
  CAST(100.0*SUM(CASE WHEN fin=1 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) win,
  CAST(100.0*SUM(CASE WHEN fin<=3 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) plc,
  CAST(100.0*SUM(CASE WHEN fin=1 THEN tan ELSE 0 END)/(100.0*COUNT(*)) AS decimal(6,1)) roi
FROM #b WHERE crank=1 GROUP BY ct,dist HAVING COUNT(*)>=30 ORDER BY n DESC;
