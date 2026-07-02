WITH r AS (
  SELECT k.開催場所 v, k.開催日 d, k.着順 fin, k.四コーナー c4, ri.コース種別 surf, ri.距離 dist,
         COUNT(1) OVER(PARTITION BY k.開催日, k.レース番号) fld
  FROM 競走結果 k
  JOIN レース情報 ri ON ri.開催場所=k.開催場所 AND ri.開催日=k.開催日 AND ri.レース番号=k.レース番号 AND ri.馬番=k.馬番
  WHERE k.開催場所=N'東京' AND k.着順>0 AND k.四コーナー>0 AND ri.コース種別 IN(N'芝',N'ダ')
),
t AS (
  SELECT d, fin, dist, CAST(c4 AS float)/fld posr,
    CASE WHEN c4=1 THEN N'逃' WHEN CAST(c4 AS float)/fld<=0.33 THEN N'先'
         WHEN CAST(c4 AS float)/fld<=0.66 THEN N'差' ELSE N'追' END kyaku,
    CASE WHEN surf=N'芝' THEN N'芝' ELSE N'ダ' END sf,
    YEAR(d) yy
  FROM r
)
SELECT N'A_距離帯' sec, sf+N' '+CASE WHEN dist<=1400 THEN N'~1400' WHEN dist<=1600 THEN N'1600' WHEN dist<=1800 THEN N'1800' WHEN dist<=2000 THEN N'2000' ELSE N'2100+' END grp,
 COUNT(1) n,
 CAST(100.0*SUM(CASE WHEN kyaku=N'逃' AND fin=1 THEN 1.0 ELSE 0 END)/NULLIF(SUM(CASE WHEN kyaku=N'逃' THEN 1.0 ELSE 0 END),0) AS decimal(4,1)) 逃勝,
 CAST(100.0*SUM(CASE WHEN kyaku IN(N'差',N'追') AND fin=1 THEN 1.0 ELSE 0 END)/NULLIF(SUM(CASE WHEN kyaku IN(N'差',N'追') THEN 1.0 ELSE 0 END),0) AS decimal(4,1)) 後勝,
 CAST(AVG(CASE WHEN fin=1 THEN posr END) AS decimal(4,3)) 勝位置
FROM t GROUP BY sf, CASE WHEN dist<=1400 THEN N'~1400' WHEN dist<=1600 THEN N'1600' WHEN dist<=1800 THEN N'1800' WHEN dist<=2000 THEN N'2000' ELSE N'2100+' END
UNION ALL
SELECT N'B_年別芝', CAST(yy AS nvarchar)+N' 芝', COUNT(1),
 CAST(100.0*SUM(CASE WHEN kyaku=N'逃' AND fin=1 THEN 1.0 ELSE 0 END)/NULLIF(SUM(CASE WHEN kyaku=N'逃' THEN 1.0 ELSE 0 END),0) AS decimal(4,1)),
 CAST(100.0*SUM(CASE WHEN kyaku IN(N'差',N'追') AND fin=1 THEN 1.0 ELSE 0 END)/NULLIF(SUM(CASE WHEN kyaku IN(N'差',N'追') THEN 1.0 ELSE 0 END),0) AS decimal(4,1)),
 CAST(AVG(CASE WHEN fin=1 THEN posr END) AS decimal(4,3))
FROM t WHERE sf=N'芝' GROUP BY yy
ORDER BY sec, grp;
