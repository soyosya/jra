-- ワイド軸流し(軸=コンピ1位×相手コンピ2-5位)の回収を コース/芝距離帯 で。差し有利が連系価値を生むか。
WITH cr AS (
  SELECT ci.開催日 d, ci.レース番号 rno, ci.指数順位 rk, ci.馬番 mb, ri.着順 fin, YEAR(ci.開催日) yy,
         ri.コース種別 surf, ri.距離 dist
  FROM コンピ指数 ci
  JOIN レース情報 ri ON ri.開催場所=ci.開催場所 AND ri.開催日=ci.開催日 AND ri.レース番号=ci.レース番号 AND ri.馬番=ci.馬番
  WHERE ci.開催場所=N'東京' AND ri.着順>0
),
race AS (
  SELECT d, rno, MAX(yy) yy, MAX(surf) surf, MAX(dist) dist,
    MAX(CASE WHEN rk=1 THEN mb END) m1, MAX(CASE WHEN rk=1 THEN fin END) f1
  FROM cr GROUP BY d, rno
),
wpairs AS (
  SELECT r.d, r.rno, r.yy, r.surf, r.dist, r.m1, r.f1, x.mb mi, x.fin fi
  FROM race r JOIN cr x ON x.d=r.d AND x.rno=r.rno AND x.rk BETWEEN 2 AND 5
  WHERE r.m1 IS NOT NULL
),
wide AS (
  SELECT wp.yy, wp.surf, wp.dist,
    CASE WHEN wp.f1<=3 AND wp.fi<=3 THEN ISNULL(pw.pay,0) ELSE 0 END ret
  FROM wpairs wp
  LEFT JOIN (
    SELECT 開催日 d, レース番号 rno,
      CAST(LEFT(組番,CHARINDEX('-',組番)-1) AS int) a,
      CAST(SUBSTRING(組番,CHARINDEX('-',組番)+1,10) AS int) b, 金額 pay
    FROM 払戻金 WHERE 開催場所=N'東京' AND 馬券=N'ワイド'
  ) pw ON pw.d=wp.d AND pw.rno=wp.rno AND ((pw.a=wp.m1 AND pw.b=wp.mi) OR (pw.a=wp.mi AND pw.b=wp.m1))
)
SELECT grp,
 COUNT(1) 点数,
 CAST(AVG(CAST(ret AS float)) AS decimal(5,0)) 回収,
 CAST(AVG(CASE WHEN yy=2022 THEN CAST(ret AS float) END) AS decimal(5,0)) y22,
 CAST(AVG(CASE WHEN yy=2023 THEN CAST(ret AS float) END) AS decimal(5,0)) y23,
 CAST(AVG(CASE WHEN yy=2024 THEN CAST(ret AS float) END) AS decimal(5,0)) y24,
 CAST(AVG(CASE WHEN yy=2025 THEN CAST(ret AS float) END) AS decimal(5,0)) y25
FROM (
  SELECT *, CASE WHEN surf=N'ダ' THEN N'ダ' WHEN dist>=2000 THEN N'芝2000+' WHEN dist>=1800 THEN N'芝1800' ELSE N'芝~1600' END grp FROM wide
) x
GROUP BY grp ORDER BY grp;
