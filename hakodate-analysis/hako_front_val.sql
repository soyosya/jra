SET NOCOUNT ON;
-- レースごと頭数(四角>0の実走)
IF OBJECT_ID('tempdb..#fld') IS NOT NULL DROP TABLE #fld;
SELECT 開催場所 v,開催日 d,レース番号 rn, COUNT(*) fld
INTO #fld FROM 競走結果 WHERE 着順>0 AND 四コーナー>0 GROUP BY 開催場所,開催日,レース番号;

-- 函館出走馬(2022-2024) + コンピ + オッズ + 過去先行力
IF OBJECT_ID('tempdb..#f') IS NOT NULL DROP TABLE #f;
SELECT r.開催日 d, r.レース番号 rn, r.馬名 h, r.着順 fin, r.距離 dist, r.コース種別 surf,
       c.指数順位 crank, o.単勝オッズ tan,
       ps.avg_posr, ps.lead_rate, ps.np
INTO #f
FROM レース情報 r
JOIN コンピ指数 c ON c.開催場所=r.開催場所 AND c.開催日=r.開催日 AND c.レース番号=r.レース番号 AND c.馬番=r.馬番
LEFT JOIN リアルタイムオッズ o ON o.開催場所=r.開催場所 AND o.開催日=r.開催日 AND o.レース番号=r.レース番号 AND o.馬番=r.馬番
CROSS APPLY (
  SELECT AVG(CAST(k.四コーナー AS float)/f.fld) avg_posr,
         AVG(CASE WHEN k.四コーナー=1 OR CAST(k.四コーナー AS float)/f.fld<=0.33 THEN 1.0 ELSE 0 END) lead_rate,
         COUNT(*) np
  FROM (
    SELECT TOP 5 k2.開催場所 v,k2.開催日 dd,k2.レース番号 rr,k2.四コーナー
    FROM 競走結果 k2
    WHERE k2.馬名=r.馬名 AND k2.開催日<r.開催日 AND k2.開催日>=DATEADD(day,-400,r.開催日) AND k2.四コーナー>0 AND k2.着順>0
    ORDER BY k2.開催日 DESC,k2.レース番号 DESC
  ) k JOIN #fld f ON f.v=k.v AND f.d=k.dd AND f.rn=k.rr
) ps
WHERE r.開催場所='函館' AND r.着順>0 AND YEAR(r.開催日) IN (2022,2023,2024) AND ps.np>=2;

SELECT 'カバレッジ' x, COUNT(*) n_有効先行データ FROM #f;

-- (A) 先行力(lead_rate)帯 × 全体
SELECT 'A.lead_rate全体' grp,
  CASE WHEN lead_rate>=0.6 THEN '1:前々(.6+)' WHEN lead_rate>=0.3 THEN '2:中(.3-.6)' ELSE '3:後方(<.3)' END band,
  COUNT(*) n,
  CAST(100.0*SUM(CASE WHEN fin=1 THEN 1.0 ELSE 0 END)/COUNT(*) AS decimal(4,1)) win,
  CAST(100.0*SUM(CASE WHEN fin<=3 THEN 1.0 ELSE 0 END)/COUNT(*) AS decimal(4,1)) plc,
  CAST(AVG(CAST(crank AS float)) AS decimal(4,1)) avgrank,
  CAST(100.0*SUM(CASE WHEN fin=1 THEN tan ELSE 0 END)/(100.0*COUNT(*)) AS decimal(5,2)) roi
FROM #f GROUP BY CASE WHEN lead_rate>=0.6 THEN '1:前々(.6+)' WHEN lead_rate>=0.3 THEN '2:中(.3-.6)' ELSE '3:後方(<.3)' END ORDER BY band;

-- (B) ★incremental: コンピ上位(crank<=4)内で 先行力帯
SELECT 'B.crank<=4内' grp,
  CASE WHEN lead_rate>=0.6 THEN '1:前々' WHEN lead_rate>=0.3 THEN '2:中' ELSE '3:後方' END band,
  COUNT(*) n,
  CAST(100.0*SUM(CASE WHEN fin=1 THEN 1.0 ELSE 0 END)/COUNT(*) AS decimal(4,1)) win,
  CAST(100.0*SUM(CASE WHEN fin<=3 THEN 1.0 ELSE 0 END)/COUNT(*) AS decimal(4,1)) plc,
  CAST(AVG(CAST(crank AS float)) AS decimal(4,1)) avgrank,
  CAST(100.0*SUM(CASE WHEN fin=1 THEN tan ELSE 0 END)/(100.0*COUNT(*)) AS decimal(5,2)) roi
FROM #f WHERE crank<=4 GROUP BY CASE WHEN lead_rate>=0.6 THEN '1:前々' WHEN lead_rate>=0.3 THEN '2:中' ELSE '3:後方' END ORDER BY band;

-- (C) コンピ1位 × 先行力(1位が前々か後方か)
SELECT 'C.コンピ1位' grp,
  CASE WHEN lead_rate>=0.5 THEN '1:前々1位' ELSE '2:差1位' END band, COUNT(*) n,
  CAST(100.0*SUM(CASE WHEN fin=1 THEN 1.0 ELSE 0 END)/COUNT(*) AS decimal(4,1)) win,
  CAST(100.0*SUM(CASE WHEN fin<=3 THEN 1.0 ELSE 0 END)/COUNT(*) AS decimal(4,1)) plc,
  CAST(100.0*SUM(CASE WHEN fin=1 THEN tan ELSE 0 END)/(100.0*COUNT(*)) AS decimal(5,2)) roi
FROM #f WHERE crank=1 GROUP BY CASE WHEN lead_rate>=0.5 THEN '1:前々1位' ELSE '2:差1位' END ORDER BY band;

-- (D) 年別頑健性: crank<=4内 前々 vs 後方 複勝率
SELECT 'D.年別 crank<=4' grp, YEAR(d) y,
  CAST(100.0*SUM(CASE WHEN lead_rate>=0.6 AND fin<=3 THEN 1.0 ELSE 0 END)/NULLIF(SUM(CASE WHEN lead_rate>=0.6 THEN 1.0 ELSE 0 END),0) AS decimal(4,1)) 前々複,
  SUM(CASE WHEN lead_rate>=0.6 THEN 1 ELSE 0 END) n前々,
  CAST(100.0*SUM(CASE WHEN lead_rate<0.3 AND fin<=3 THEN 1.0 ELSE 0 END)/NULLIF(SUM(CASE WHEN lead_rate<0.3 THEN 1.0 ELSE 0 END),0) AS decimal(4,1)) 後方複,
  SUM(CASE WHEN lead_rate<0.3 THEN 1 ELSE 0 END) n後方
FROM #f WHERE crank<=4 GROUP BY YEAR(d) ORDER BY y;

-- (E) 年別: コンピ1位 前々 vs 差 複勝率
SELECT 'E.年別 コンピ1位' grp, YEAR(d) y,
  CAST(100.0*SUM(CASE WHEN lead_rate>=0.5 AND fin<=3 THEN 1.0 ELSE 0 END)/NULLIF(SUM(CASE WHEN lead_rate>=0.5 THEN 1.0 ELSE 0 END),0) AS decimal(4,1)) 前々複,
  SUM(CASE WHEN lead_rate>=0.5 THEN 1 ELSE 0 END) n前々,
  CAST(100.0*SUM(CASE WHEN lead_rate<0.5 AND fin<=3 THEN 1.0 ELSE 0 END)/NULLIF(SUM(CASE WHEN lead_rate<0.5 THEN 1.0 ELSE 0 END),0) AS decimal(4,1)) 差複,
  SUM(CASE WHEN lead_rate<0.5 THEN 1 ELSE 0 END) n差
FROM #f WHERE crank=1 GROUP BY YEAR(d) ORDER BY y;
