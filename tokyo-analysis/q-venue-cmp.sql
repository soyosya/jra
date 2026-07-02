WITH r AS (
  SELECT k.開催場所 v, k.着順 fin, k.四コーナー c4, ri.コース種別 surf,
         COUNT(1) OVER(PARTITION BY k.開催場所, k.開催日, k.レース番号) fld
  FROM 競走結果 k
  JOIN レース情報 ri ON ri.開催場所=k.開催場所 AND ri.開催日=k.開催日 AND ri.レース番号=k.レース番号 AND ri.馬番=k.馬番
  WHERE k.着順>0 AND k.四コーナー>0 AND ri.コース種別 IN(N'芝',N'ダ')
),
t AS (
  SELECT v, fin, CAST(c4 AS float)/fld posr,
    CASE WHEN c4=1 THEN N'逃' WHEN CAST(c4 AS float)/fld<=0.33 THEN N'先'
         WHEN CAST(c4 AS float)/fld<=0.66 THEN N'差' ELSE N'追' END kyaku,
    CASE WHEN surf=N'芝' THEN N'芝' ELSE N'ダ' END sf
  FROM r
)
SELECT v 場, sf コース,
 COUNT(1) 出走,
 CAST(100.0*SUM(CASE WHEN kyaku=N'逃' AND fin=1 THEN 1.0 ELSE 0 END)/NULLIF(SUM(CASE WHEN kyaku=N'逃' THEN 1.0 ELSE 0 END),0) AS decimal(4,1)) 逃勝率,
 CAST(100.0*SUM(CASE WHEN kyaku=N'先' AND fin=1 THEN 1.0 ELSE 0 END)/NULLIF(SUM(CASE WHEN kyaku=N'先' THEN 1.0 ELSE 0 END),0) AS decimal(4,1)) 先勝率,
 CAST(100.0*SUM(CASE WHEN kyaku IN(N'差',N'追') AND fin=1 THEN 1.0 ELSE 0 END)/NULLIF(SUM(CASE WHEN kyaku IN(N'差',N'追') THEN 1.0 ELSE 0 END),0) AS decimal(4,1)) 後方勝率,
 CAST(100.0*SUM(CASE WHEN kyaku IN(N'差',N'追') AND fin<=3 THEN 1.0 ELSE 0 END)/NULLIF(SUM(CASE WHEN kyaku IN(N'差',N'追') THEN 1.0 ELSE 0 END),0) AS decimal(4,1)) 後方複勝率,
 CAST(AVG(CASE WHEN fin=1 THEN posr END) AS decimal(4,3)) 勝馬位置比
FROM t GROUP BY v, sf
ORDER BY sf, 後方勝率 DESC;
