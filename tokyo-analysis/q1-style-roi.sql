-- 東京 実現脚質(四角相対位置)別の単勝回収・勝率(人気で織込済か)
WITH r AS (
  SELECT k.着順 fin, k.四コーナー c4, ri.コース種別 surf,
         o.単勝オッズ tan, o.人気 pop,
         COUNT(1) OVER(PARTITION BY k.開催日, k.レース番号) fld
  FROM 競走結果 k
  JOIN レース情報 ri ON ri.開催場所=k.開催場所 AND ri.開催日=k.開催日 AND ri.レース番号=k.レース番号 AND ri.馬番=k.馬番
  JOIN リアルタイムオッズ o ON o.開催場所=k.開催場所 AND o.開催日=k.開催日 AND o.レース番号=k.レース番号 AND o.馬番=k.馬番
  WHERE k.開催場所=N'東京' AND k.着順>0 AND k.四コーナー>0 AND ri.コース種別 IN(N'芝',N'ダ') AND o.単勝オッズ>0
),
t AS (
  SELECT fin, tan, pop,
    CASE WHEN c4=1 THEN N'1_逃' WHEN CAST(c4 AS float)/fld<=0.33 THEN N'2_先'
         WHEN CAST(c4 AS float)/fld<=0.66 THEN N'3_差' ELSE N'4_追' END kyaku,
    CASE WHEN surf=N'芝' THEN N'芝' ELSE N'ダ' END sf
  FROM r
)
SELECT N'A_脚質別_全' sec, kyaku grp, COUNT(1) n,
 CAST(100.0*SUM(CASE WHEN fin=1 THEN 1.0 ELSE 0 END)/COUNT(1) AS decimal(4,1)) 勝率,
 CAST(100.0*SUM(CASE WHEN fin=1 THEN tan ELSE 0 END)/COUNT(1) AS decimal(5,1)) 単回収,
 CAST(AVG(CAST(pop AS float)) AS decimal(4,1)) 平均人気
FROM t GROUP BY kyaku
UNION ALL
SELECT N'B_脚質別_芝', kyaku, COUNT(1),
 CAST(100.0*SUM(CASE WHEN fin=1 THEN 1.0 ELSE 0 END)/COUNT(1) AS decimal(4,1)),
 CAST(100.0*SUM(CASE WHEN fin=1 THEN tan ELSE 0 END)/COUNT(1) AS decimal(5,1)),
 CAST(AVG(CAST(pop AS float)) AS decimal(4,1))
FROM t WHERE sf=N'芝' GROUP BY kyaku
UNION ALL
SELECT N'C_脚質別_ダ', kyaku, COUNT(1),
 CAST(100.0*SUM(CASE WHEN fin=1 THEN 1.0 ELSE 0 END)/COUNT(1) AS decimal(4,1)),
 CAST(100.0*SUM(CASE WHEN fin=1 THEN tan ELSE 0 END)/COUNT(1) AS decimal(5,1)),
 CAST(AVG(CAST(pop AS float)) AS decimal(4,1))
FROM t WHERE sf=N'ダ' GROUP BY kyaku
ORDER BY sec, grp;
