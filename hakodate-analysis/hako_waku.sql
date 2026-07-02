SET NOCOUNT ON;
IF OBJECT_ID('tempdb..#b') IS NOT NULL DROP TABLE #b;
SELECT r.開催日 d, r.レース番号 rn, r.着順 fin, r.枠番 waku, r.馬番 no,
       r.コース種別 ct, r.距離 dist, c.指数順位 crank, c.頭数 ninzu, o.単勝オッズ tan
INTO #b
FROM レース情報 r
JOIN コンピ指数 c ON c.開催場所=r.開催場所 AND c.開催日=r.開催日 AND c.レース番号=r.レース番号 AND c.馬番=r.馬番
LEFT JOIN リアルタイムオッズ o ON o.開催場所=r.開催場所 AND o.開催日=r.開催日 AND o.レース番号=r.レース番号 AND o.馬番=r.馬番
WHERE r.開催場所='函館' AND r.着順>0;

-- 枠別: 芝1200
SELECT '芝1200 枠別' grp, waku, COUNT(*) n,
  CAST(100.0*SUM(CASE WHEN fin=1 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) win,
  CAST(100.0*SUM(CASE WHEN fin<=3 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) plc,
  CAST(AVG(CAST(crank AS float)) AS decimal(4,1)) avgrank,
  CAST(100.0*SUM(CASE WHEN fin=1 THEN tan ELSE 0 END)/(100.0*COUNT(*)) AS decimal(6,1)) roi
FROM #b WHERE ct='芝' AND dist=1200 GROUP BY waku ORDER BY waku;

-- 内外2分: 芝1200 (馬番で頭数の半分)
SELECT '芝1200 内/外' grp,
  CASE WHEN no*2<=ninzu THEN '内' ELSE '外' END half, COUNT(*) n,
  CAST(100.0*SUM(CASE WHEN fin<=3 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) plc,
  CAST(AVG(CAST(crank AS float)) AS decimal(4,1)) avgrank
FROM #b WHERE ct='芝' AND dist=1200 GROUP BY CASE WHEN no*2<=ninzu THEN '内' ELSE '外' END;

-- ダ1700 枠別
SELECT 'ダ1700 枠別' grp, waku, COUNT(*) n,
  CAST(100.0*SUM(CASE WHEN fin=1 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) win,
  CAST(100.0*SUM(CASE WHEN fin<=3 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) plc,
  CAST(AVG(CAST(crank AS float)) AS decimal(4,1)) avgrank
FROM #b WHERE ct='ダ' AND dist=1700 GROUP BY waku ORDER BY waku;

-- ダ1000 枠別
SELECT 'ダ1000 枠別' grp, waku, COUNT(*) n,
  CAST(100.0*SUM(CASE WHEN fin<=3 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) plc,
  CAST(AVG(CAST(crank AS float)) AS decimal(4,1)) avgrank
FROM #b WHERE ct='ダ' AND dist=1000 GROUP BY waku ORDER BY waku;
