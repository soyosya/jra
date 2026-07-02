-- 前走脚質(事前に使える)ベースの東京 単回収。市場に織込済か。人気帯も。
WITH allr AS (
  SELECT k.開催場所 v, k.開催日 d, k.レース番号 rno, k.馬名 h, k.着順 fin, k.四コーナー c4,
         ri.コース種別 surf,
         COUNT(1) OVER(PARTITION BY k.開催場所,k.開催日,k.レース番号) fld
  FROM 競走結果 k
  JOIN レース情報 ri ON ri.開催場所=k.開催場所 AND ri.開催日=k.開催日 AND ri.レース番号=k.レース番号 AND ri.馬番=k.馬番
  WHERE k.着順>0 AND k.四コーナー>0
),
styled AS (
  SELECT v,d,rno,h,fin,surf,
    CASE WHEN c4=1 THEN 1 WHEN CAST(c4 AS float)/fld<=0.33 THEN 2
         WHEN CAST(c4 AS float)/fld<=0.66 THEN 3 ELSE 4 END st
  FROM allr
),
seq AS (
  SELECT *,
    LAG(st) OVER(PARTITION BY h ORDER BY d,rno) pst,
    LAG(d)  OVER(PARTITION BY h ORDER BY d,rno) pd
  FROM styled
),
tk AS (
  SELECT s.fin, s.surf, s.pst, o.単勝オッズ tan, o.人気 pop,
    CASE s.pst WHEN 1 THEN N'1_前走逃' WHEN 2 THEN N'2_前走先' WHEN 3 THEN N'3_前走差' WHEN 4 THEN N'4_前走追' END pk
  FROM seq s
  JOIN リアルタイムオッズ o ON o.開催場所=s.v AND o.開催日=s.d AND o.レース番号=s.rno AND o.馬名=s.h
  WHERE s.v=N'東京' AND s.pst IS NOT NULL AND o.単勝オッズ>0 AND DATEDIFF(day,s.pd,s.d)<=365
)
SELECT N'A_前走脚質_全' sec, pk grp, COUNT(1) n,
 CAST(100.0*SUM(CASE WHEN fin=1 THEN 1.0 ELSE 0 END)/COUNT(1) AS decimal(4,1)) 勝率,
 CAST(100.0*SUM(CASE WHEN fin<=3 THEN 1.0 ELSE 0 END)/COUNT(1) AS decimal(4,1)) 複勝率,
 CAST(100.0*SUM(CASE WHEN fin=1 THEN tan ELSE 0 END)/COUNT(1) AS decimal(5,1)) 単回収,
 CAST(AVG(CAST(pop AS float)) AS decimal(4,1)) 平均人気
FROM tk GROUP BY pk
UNION ALL
SELECT N'B_前走脚質_芝', pk, COUNT(1),
 CAST(100.0*SUM(CASE WHEN fin=1 THEN 1.0 ELSE 0 END)/COUNT(1) AS decimal(4,1)),
 CAST(100.0*SUM(CASE WHEN fin<=3 THEN 1.0 ELSE 0 END)/COUNT(1) AS decimal(4,1)),
 CAST(100.0*SUM(CASE WHEN fin=1 THEN tan ELSE 0 END)/COUNT(1) AS decimal(5,1)),
 CAST(AVG(CAST(pop AS float)) AS decimal(4,1))
FROM tk WHERE surf=N'芝' GROUP BY pk
ORDER BY sec, grp;
