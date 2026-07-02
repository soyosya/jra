-- コンピ指数1位/指数帯の東京 勝率・複勝率・単複回収(年別)
WITH c AS (
  SELECT ci.開催日 d, ci.開催場所 v, ci.レース番号 rno, ci.馬番 mb, ci.指数, ci.指数順位, ci.頭数,
         ri.着順 fin, o.単勝オッズ tan, o.複勝オッズ_MIN fukmin, o.人気 pop
  FROM コンピ指数 ci
  JOIN レース情報 ri ON ri.開催場所=ci.開催場所 AND ri.開催日=ci.開催日 AND ri.レース番号=ci.レース番号 AND ri.馬番=ci.馬番
  LEFT JOIN リアルタイムオッズ o ON o.開催場所=ci.開催場所 AND o.開催日=ci.開催日 AND o.レース番号=ci.レース番号 AND o.馬番=ci.馬番
  WHERE ci.開催場所=N'東京' AND ri.着順>0
)
SELECT N'A_コンピ1位_年別' sec, CAST(YEAR(d) AS nvarchar) grp, COUNT(1) n,
 CAST(100.0*SUM(CASE WHEN fin=1 THEN 1.0 ELSE 0 END)/COUNT(1) AS decimal(4,1)) 勝率,
 CAST(100.0*SUM(CASE WHEN fin<=3 THEN 1.0 ELSE 0 END)/COUNT(1) AS decimal(4,1)) 複勝率,
 CAST(100.0*SUM(CASE WHEN fin=1 THEN tan ELSE 0 END)/COUNT(1) AS decimal(5,1)) 単回収,
 CAST(100.0*SUM(CASE WHEN fin<=3 THEN ISNULL(fukmin,0) ELSE 0 END)/COUNT(1) AS decimal(5,1)) 複回収
FROM c WHERE 指数順位=1 GROUP BY YEAR(d)
UNION ALL
SELECT N'B_コンピ指数帯', CASE WHEN 指数>=85 THEN N'85+' WHEN 指数>=80 THEN N'80-84' WHEN 指数>=70 THEN N'70-79' WHEN 指数>=60 THEN N'60-69' ELSE N'~59' END,
 COUNT(1),
 CAST(100.0*SUM(CASE WHEN fin=1 THEN 1.0 ELSE 0 END)/COUNT(1) AS decimal(4,1)),
 CAST(100.0*SUM(CASE WHEN fin<=3 THEN 1.0 ELSE 0 END)/COUNT(1) AS decimal(4,1)),
 CAST(100.0*SUM(CASE WHEN fin=1 THEN tan ELSE 0 END)/COUNT(1) AS decimal(5,1)),
 CAST(100.0*SUM(CASE WHEN fin<=3 THEN ISNULL(fukmin,0) ELSE 0 END)/COUNT(1) AS decimal(5,1))
FROM c GROUP BY CASE WHEN 指数>=85 THEN N'85+' WHEN 指数>=80 THEN N'80-84' WHEN 指数>=70 THEN N'70-79' WHEN 指数>=60 THEN N'60-69' ELSE N'~59' END
UNION ALL
SELECT N'C_コンピ1位_全体', N'all', COUNT(1),
 CAST(100.0*SUM(CASE WHEN fin=1 THEN 1.0 ELSE 0 END)/COUNT(1) AS decimal(4,1)),
 CAST(100.0*SUM(CASE WHEN fin<=3 THEN 1.0 ELSE 0 END)/COUNT(1) AS decimal(4,1)),
 CAST(100.0*SUM(CASE WHEN fin=1 THEN tan ELSE 0 END)/COUNT(1) AS decimal(5,1)),
 CAST(100.0*SUM(CASE WHEN fin<=3 THEN ISNULL(fukmin,0) ELSE 0 END)/COUNT(1) AS decimal(5,1))
FROM c WHERE 指数順位=1
ORDER BY sec, grp;
