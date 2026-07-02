SET NOCOUNT ON;
IF OBJECT_ID('tempdb..#b') IS NOT NULL DROP TABLE #b;
SELECT r.着順 fin, c.指数 idx, c.指数順位 crank, o.単勝オッズ tan
INTO #b
FROM レース情報 r
JOIN コンピ指数 c ON c.開催場所=r.開催場所 AND c.開催日=r.開催日 AND c.レース番号=r.レース番号 AND c.馬番=r.馬番
LEFT JOIN リアルタイムオッズ o ON o.開催場所=r.開催場所 AND o.開催日=r.開催日 AND o.レース番号=r.レース番号 AND o.馬番=r.馬番
WHERE r.開催場所='函館' AND r.着順>0;

SELECT '1位の指数値帯' grp,
  CASE WHEN idx>=85 THEN '1:85+' WHEN idx>=80 THEN '2:80-84' WHEN idx>=75 THEN '3:75-79'
       WHEN idx>=70 THEN '4:70-74' ELSE '5:-69' END band, COUNT(*) n,
  CAST(100.0*SUM(CASE WHEN fin=1 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) win,
  CAST(100.0*SUM(CASE WHEN fin<=3 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) plc,
  CAST(100.0*SUM(CASE WHEN fin=1 THEN tan ELSE 0 END)/(100.0*COUNT(*)) AS decimal(6,1)) roi
FROM #b WHERE crank=1 GROUP BY CASE WHEN idx>=85 THEN '1:85+' WHEN idx>=80 THEN '2:80-84' WHEN idx>=75 THEN '3:75-79'
       WHEN idx>=70 THEN '4:70-74' ELSE '5:-69' END ORDER BY band;

SELECT '指数順位別(全馬)' grp, crank, COUNT(*) n,
  CAST(100.0*SUM(CASE WHEN fin=1 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) win,
  CAST(100.0*SUM(CASE WHEN fin<=3 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) plc,
  CAST(100.0*SUM(CASE WHEN fin=1 THEN tan ELSE 0 END)/(100.0*COUNT(*)) AS decimal(6,1)) roi
FROM #b WHERE crank<=6 GROUP BY crank ORDER BY crank;
