WITH allr AS (
  SELECT k.開催場所 v, k.開催日 d, k.レース番号 rno, k.馬名 h, k.着順 fin, k.四コーナー c4, ri.コース種別 surf,
         COUNT(1) OVER(PARTITION BY k.開催場所,k.開催日,k.レース番号) fld
  FROM 競走結果 k
  JOIN レース情報 ri ON ri.開催場所=k.開催場所 AND ri.開催日=k.開催日 AND ri.レース番号=k.レース番号 AND ri.馬番=k.馬番
  WHERE k.着順>0 AND k.四コーナー>0
),
styled AS (
  SELECT v,d,rno,h,fin,surf,
    CASE WHEN c4=1 THEN 1 WHEN CAST(c4 AS float)/fld<=0.33 THEN 2 WHEN CAST(c4 AS float)/fld<=0.66 THEN 3 ELSE 4 END st
  FROM allr
),
seq AS (
  SELECT *, LAG(st) OVER(PARTITION BY h ORDER BY d,rno) pst, LAG(d) OVER(PARTITION BY h ORDER BY d,rno) pd FROM styled
),
tk AS (
  SELECT s.fin, s.surf, s.pst, o.単勝オッズ tan, o.人気 pop, YEAR(s.d) yy,
    CASE WHEN s.pst<=2 THEN N'前(逃先)' ELSE N'後(差追)' END zone,
    CASE WHEN o.人気=1 THEN N'1_1番' WHEN o.人気<=4 THEN N'2_2-4' WHEN o.人気<=8 THEN N'3_5-8' ELSE N'4_9+' END pb
  FROM seq s
  JOIN リアルタイムオッズ o ON o.開催場所=s.v AND o.開催日=s.d AND o.レース番号=s.rno AND o.馬名=s.h
  WHERE s.v=N'東京' AND s.pst IS NOT NULL AND o.単勝オッズ>0 AND DATEDIFF(day,s.pd,s.d)<=365
)
SELECT N'A_人気帯x前後' sec, pb+N' '+zone grp, COUNT(1) n,
 CAST(100.0*SUM(CASE WHEN fin=1 THEN 1.0 ELSE 0 END)/COUNT(1) AS decimal(4,1)) 勝率,
 CAST(100.0*SUM(CASE WHEN fin=1 THEN tan ELSE 0 END)/COUNT(1) AS decimal(5,1)) 単回収
FROM tk GROUP BY pb, zone
UNION ALL
SELECT N'B_年別_前走逃', CAST(yy AS nvarchar), COUNT(1),
 CAST(100.0*SUM(CASE WHEN fin=1 THEN 1.0 ELSE 0 END)/COUNT(1) AS decimal(4,1)),
 CAST(100.0*SUM(CASE WHEN fin=1 THEN tan ELSE 0 END)/COUNT(1) AS decimal(5,1))
FROM tk WHERE pst=1 GROUP BY yy
UNION ALL
SELECT N'C_年別_芝後方差', CAST(yy AS nvarchar), COUNT(1),
 CAST(100.0*SUM(CASE WHEN fin=1 THEN 1.0 ELSE 0 END)/COUNT(1) AS decimal(4,1)),
 CAST(100.0*SUM(CASE WHEN fin=1 THEN tan ELSE 0 END)/COUNT(1) AS decimal(5,1))
FROM tk WHERE surf=N'芝' AND pst=3 GROUP BY yy
ORDER BY sec, grp;
