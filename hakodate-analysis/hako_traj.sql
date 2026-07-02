SET NOCOUNT ON;
IF OBJECT_ID('tempdb..#t') IS NOT NULL DROP TABLE #t;
-- 函館今走 × 直近前走コンピ(任意場, <=120日)
SELECT r.開催日 d, r.レース番号 rn, r.馬名 h, r.着順 fin,
       c.指数 idx, c.指数順位 crank, o.単勝オッズ tan,
       p.idx pidx, (c.指数 - p.idx) ddx
INTO #t
FROM レース情報 r
JOIN コンピ指数 c ON c.開催場所=r.開催場所 AND c.開催日=r.開催日 AND c.レース番号=r.レース番号 AND c.馬番=r.馬番
LEFT JOIN リアルタイムオッズ o ON o.開催場所=r.開催場所 AND o.開催日=r.開催日 AND o.レース番号=r.レース番号 AND o.馬番=r.馬番
OUTER APPLY (
  SELECT TOP 1 CAST(pc.指数 AS int) idx
  FROM コンピ指数 pc
  WHERE pc.馬名=r.馬名 AND pc.開催日 < r.開催日 AND pc.開催日 >= DATEADD(day,-120,r.開催日)
  ORDER BY pc.開催日 DESC
) p
WHERE r.開催場所='函館' AND r.着順>0 AND p.idx IS NOT NULL;

SELECT 'Δ帯別(全馬)' grp,
  CASE WHEN ddx>=8 THEN '1:+8以上' WHEN ddx>=3 THEN '2:+3〜7' WHEN ddx>=-2 THEN '3:-2〜+2'
       WHEN ddx>=-7 THEN '4:-7〜-3' ELSE '5:-8以下' END band, COUNT(*) n,
  CAST(100.0*SUM(CASE WHEN fin=1 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) win,
  CAST(100.0*SUM(CASE WHEN fin<=3 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) plc,
  CAST(AVG(CAST(crank AS float)) AS decimal(4,1)) avgrank,
  CAST(100.0*SUM(CASE WHEN fin=1 THEN tan ELSE 0 END)/(100.0*COUNT(*)) AS decimal(6,1)) roi
FROM #t GROUP BY CASE WHEN ddx>=8 THEN '1:+8以上' WHEN ddx>=3 THEN '2:+3〜7' WHEN ddx>=-2 THEN '3:-2〜+2'
       WHEN ddx>=-7 THEN '4:-7〜-3' ELSE '5:-8以下' END ORDER BY band;

-- 今走順位で交絡除去: 上位人気帯(crank<=5)内でΔ
SELECT 'Δ帯別(crank<=5)' grp,
  CASE WHEN ddx>=3 THEN 'A:上昇+3↑' WHEN ddx>=-2 THEN 'B:横ばい' ELSE 'C:下降-3↓' END band, COUNT(*) n,
  CAST(100.0*SUM(CASE WHEN fin=1 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) win,
  CAST(100.0*SUM(CASE WHEN fin<=3 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) plc,
  CAST(AVG(CAST(crank AS float)) AS decimal(4,1)) avgrank,
  CAST(100.0*SUM(CASE WHEN fin=1 THEN tan ELSE 0 END)/(100.0*COUNT(*)) AS decimal(6,1)) roi
FROM #t WHERE crank<=5 GROUP BY CASE WHEN ddx>=3 THEN 'A:上昇+3↑' WHEN ddx>=-2 THEN 'B:横ばい' ELSE 'C:下降-3↓' END ORDER BY band;
