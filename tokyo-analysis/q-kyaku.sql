WITH r AS (
  SELECT k.着順 fin, k.四コーナー c4, ri.コース種別 surf, ri.距離 dist,
         COUNT(1) OVER(PARTITION BY k.開催日, k.レース番号) fld
  FROM 競走結果 k
  JOIN レース情報 ri ON ri.開催場所=k.開催場所 AND ri.開催日=k.開催日 AND ri.レース番号=k.レース番号 AND ri.馬番=k.馬番
  WHERE k.開催場所=N'東京' AND k.着順>0 AND k.四コーナー>0 AND ri.コース種別 IN(N'芝',N'ダ')
),
t AS (
  SELECT fin, c4, CAST(c4 AS float)/fld posr, fld,
    CASE WHEN c4=1 THEN N'1_逃げ'
         WHEN CAST(c4 AS float)/fld<=0.33 THEN N'2_先行'
         WHEN CAST(c4 AS float)/fld<=0.66 THEN N'3_差し'
         ELSE N'4_追込' END kyaku,
    CASE WHEN surf=N'芝' THEN N'芝' ELSE N'ダ' END sf
  FROM r
)
SELECT N'全体' lvl, kyaku, COUNT(1) n,
 CAST(100.0*SUM(CASE WHEN fin=1 THEN 1.0 ELSE 0 END)/COUNT(1) AS decimal(4,1)) 勝率,
 CAST(100.0*SUM(CASE WHEN fin<=3 THEN 1.0 ELSE 0 END)/COUNT(1) AS decimal(4,1)) 複勝率,
 CAST((1.0*SUM(CASE WHEN fin=1 THEN 1.0 ELSE 0 END)/COUNT(1))/(SELECT 1.0*SUM(CASE WHEN fin=1 THEN 1.0 ELSE 0 END)/COUNT(1) FROM t) AS decimal(4,2)) 勝IV
FROM t GROUP BY kyaku
UNION ALL
SELECT sf, kyaku, COUNT(1),
 CAST(100.0*SUM(CASE WHEN fin=1 THEN 1.0 ELSE 0 END)/COUNT(1) AS decimal(4,1)),
 CAST(100.0*SUM(CASE WHEN fin<=3 THEN 1.0 ELSE 0 END)/COUNT(1) AS decimal(4,1)),
 NULL
FROM t GROUP BY sf, kyaku
ORDER BY lvl, kyaku;
