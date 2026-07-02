-- 連系馬券BT(東京・コンピ軸ベース)。払戻金から実回収を年別に。
-- 戦略: ワイド軸流し(軸=コンピ1位×相手=コンピ2-5位,4点) / 馬連軸-2位(1点) / 三連複コンピ上位3頭BOX(1点)
WITH cr AS (
  SELECT ci.開催日 d, ci.レース番号 rno, ci.指数順位 rk, ci.馬番 mb, ri.着順 fin, YEAR(ci.開催日) yy
  FROM コンピ指数 ci
  JOIN レース情報 ri ON ri.開催場所=ci.開催場所 AND ri.開催日=ci.開催日 AND ri.レース番号=ci.レース番号 AND ri.馬番=ci.馬番
  WHERE ci.開催場所=N'東京' AND ri.着順>0
),
race AS (
  SELECT d, rno, MAX(yy) yy,
    MAX(CASE WHEN rk=1 THEN mb END) m1, MAX(CASE WHEN rk=1 THEN fin END) f1,
    MAX(CASE WHEN rk=2 THEN mb END) m2, MAX(CASE WHEN rk=2 THEN fin END) f2,
    MAX(CASE WHEN rk=3 THEN mb END) m3, MAX(CASE WHEN rk=3 THEN fin END) f3
  FROM cr WHERE rk<=3 GROUP BY d, rno
),
-- ワイド: 軸(rk1)×相手(rk2-5)
wpairs AS (
  SELECT r.d, r.rno, r.yy, r.m1, r.f1, x.mb mi, x.fin fi
  FROM race r JOIN cr x ON x.d=r.d AND x.rno=r.rno AND x.rk BETWEEN 2 AND 5
  WHERE r.m1 IS NOT NULL
),
wide AS (
  SELECT wp.yy,
    CASE WHEN wp.f1<=3 AND wp.fi<=3 THEN ISNULL(pw.pay,0) ELSE 0 END ret
  FROM wpairs wp
  LEFT JOIN (
    SELECT 開催日 d, レース番号 rno,
      CAST(LEFT(組番,CHARINDEX('-',組番)-1) AS int) a,
      CAST(SUBSTRING(組番,CHARINDEX('-',組番)+1,10) AS int) b, 金額 pay
    FROM 払戻金 WHERE 開催場所=N'東京' AND 馬券=N'ワイド'
  ) pw ON pw.d=wp.d AND pw.rno=wp.rno
       AND ((pw.a=wp.m1 AND pw.b=wp.mi) OR (pw.a=wp.mi AND pw.b=wp.m1))
),
-- 馬連: 軸-2位
uren AS (
  SELECT r.yy, CASE WHEN r.f1<=2 AND r.f2<=2 THEN ISNULL(pu.pay,0) ELSE 0 END ret
  FROM race r
  LEFT JOIN (
    SELECT 開催日 d, レース番号 rno,
      CAST(LEFT(組番,CHARINDEX('-',組番)-1) AS int) a,
      CAST(SUBSTRING(組番,CHARINDEX('-',組番)+1,10) AS int) b, 金額 pay
    FROM 払戻金 WHERE 開催場所=N'東京' AND 馬券=N'馬連'
  ) pu ON pu.d=r.d AND pu.rno=r.rno AND ((pu.a=r.m1 AND pu.b=r.m2) OR (pu.a=r.m2 AND pu.b=r.m1))
  WHERE r.m1 IS NOT NULL AND r.m2 IS NOT NULL
)
SELECT N'ワイド軸流し(4点)' 戦略, COUNT(1) 点数, MIN(0) dummy,
 CAST(AVG(CAST(ret AS float)) AS decimal(5,0)) 回収,
 CAST(AVG(CASE WHEN yy=2022 THEN CAST(ret AS float) END) AS decimal(5,0)) y22,
 CAST(AVG(CASE WHEN yy=2023 THEN CAST(ret AS float) END) AS decimal(5,0)) y23,
 CAST(AVG(CASE WHEN yy=2024 THEN CAST(ret AS float) END) AS decimal(5,0)) y24,
 CAST(AVG(CASE WHEN yy=2025 THEN CAST(ret AS float) END) AS decimal(5,0)) y25
FROM wide
UNION ALL
SELECT N'馬連 軸-2位(1点)', COUNT(1), 0,
 CAST(AVG(CAST(ret AS float)) AS decimal(5,0)),
 CAST(AVG(CASE WHEN yy=2022 THEN CAST(ret AS float) END) AS decimal(5,0)),
 CAST(AVG(CASE WHEN yy=2023 THEN CAST(ret AS float) END) AS decimal(5,0)),
 CAST(AVG(CASE WHEN yy=2024 THEN CAST(ret AS float) END) AS decimal(5,0)),
 CAST(AVG(CASE WHEN yy=2025 THEN CAST(ret AS float) END) AS decimal(5,0))
FROM uren;
