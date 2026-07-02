-- 前走/前々走 上り3Fレース内ベスト3 の東京での成績・単回収(年別頑健性)
WITH base AS (
  SELECT k.開催場所 v, k.開催日 d, k.レース番号 rno, k.馬名 h, k.着順 fin, ri.コース種別 surf,
         RANK() OVER(PARTITION BY k.開催場所,k.開催日,k.レース番号 ORDER BY k.上り3F ASC) agr
  FROM 競走結果 k
  JOIN レース情報 ri ON ri.開催場所=k.開催場所 AND ri.開催日=k.開催日 AND ri.レース番号=k.レース番号 AND ri.馬番=k.馬番
  WHERE k.着順>0 AND k.上り3F>0 AND ri.コース種別 IN(N'芝',N'ダ')
),
seq AS (
  SELECT *, LAG(agr) OVER(PARTITION BY h ORDER BY d,rno) p1,
            LAG(agr,2) OVER(PARTITION BY h ORDER BY d,rno) p2,
            LAG(d) OVER(PARTITION BY h ORDER BY d,rno) pd FROM base
),
tk AS (
  SELECT s.fin, s.surf, s.p1, s.p2, YEAR(s.d) yy, o.単勝オッズ tan, o.人気 pop
  FROM seq s
  JOIN リアルタイムオッズ o ON o.開催場所=s.v AND o.開催日=s.d AND o.レース番号=s.rno AND o.馬名=s.h
  WHERE s.v=N'東京' AND s.p1 IS NOT NULL AND o.単勝オッズ>0 AND DATEDIFF(day,s.pd,s.d)<=365
)
SELECT N'A_区分_全' sec,
 CASE WHEN p1<=3 AND p2<=3 THEN N'連続Best3' WHEN p1<=3 THEN N'前走のみBest3' ELSE N'非該当' END grp,
 COUNT(1) n,
 CAST(100.0*SUM(CASE WHEN fin=1 THEN 1.0 ELSE 0 END)/COUNT(1) AS decimal(4,1)) 勝率,
 CAST(100.0*SUM(CASE WHEN fin<=3 THEN 1.0 ELSE 0 END)/COUNT(1) AS decimal(4,1)) 複勝率,
 CAST(100.0*SUM(CASE WHEN fin=1 THEN tan ELSE 0 END)/COUNT(1) AS decimal(5,1)) 単回収,
 CAST(AVG(CAST(pop AS float)) AS decimal(4,1)) 平均人気
FROM tk WHERE p2 IS NOT NULL GROUP BY CASE WHEN p1<=3 AND p2<=3 THEN N'連続Best3' WHEN p1<=3 THEN N'前走のみBest3' ELSE N'非該当' END
UNION ALL
SELECT N'B_年別_前走Best3', CAST(yy AS nvarchar), COUNT(1),
 CAST(100.0*SUM(CASE WHEN fin=1 THEN 1.0 ELSE 0 END)/COUNT(1) AS decimal(4,1)),
 CAST(100.0*SUM(CASE WHEN fin<=3 THEN 1.0 ELSE 0 END)/COUNT(1) AS decimal(4,1)),
 CAST(100.0*SUM(CASE WHEN fin=1 THEN tan ELSE 0 END)/COUNT(1) AS decimal(5,1)),
 CAST(AVG(CAST(pop AS float)) AS decimal(4,1))
FROM tk WHERE p1<=3 GROUP BY yy
UNION ALL
SELECT N'C_年別_芝前走Best3', CAST(yy AS nvarchar), COUNT(1),
 CAST(100.0*SUM(CASE WHEN fin=1 THEN 1.0 ELSE 0 END)/COUNT(1) AS decimal(4,1)),
 CAST(100.0*SUM(CASE WHEN fin<=3 THEN 1.0 ELSE 0 END)/COUNT(1) AS decimal(4,1)),
 CAST(100.0*SUM(CASE WHEN fin=1 THEN tan ELSE 0 END)/COUNT(1) AS decimal(5,1)),
 CAST(AVG(CAST(pop AS float)) AS decimal(4,1))
FROM tk WHERE surf=N'芝' AND p1<=3 GROUP BY yy
ORDER BY sec, grp;
