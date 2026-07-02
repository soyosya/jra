-- 東京 単勝+EVポケット探索の基盤テーブル tk_bt を作成(存在すれば作り直さない)
IF OBJECT_ID('dbo.tk_bt') IS NULL
BEGIN
  WITH styleall AS (
    SELECT k.開催場所 v, k.開催日 d, k.レース番号 rno, k.馬名 h, k.四コーナー c4,
           COUNT(1) OVER(PARTITION BY k.開催場所,k.開催日,k.レース番号) fld
    FROM 競走結果 k WHERE k.着順>0 AND k.四コーナー>0
  ),
  styled AS (
    SELECT v,d,rno,h,
      CASE WHEN c4=1 THEN 1 WHEN CAST(c4 AS float)/fld<=0.33 THEN 2 WHEN CAST(c4 AS float)/fld<=0.66 THEN 3 ELSE 4 END st
    FROM styleall
  ),
  prevstyle AS (
    SELECT v,d,rno,h, LAG(st) OVER(PARTITION BY h ORDER BY d,rno) pst,
           LAG(d) OVER(PARTITION BY h ORDER BY d,rno) pstd
    FROM styled
  ),
  prevcompi AS (
    SELECT 開催場所 v, 開催日 d, レース番号 rno, 馬名 h, 指数,
           LAG(指数) OVER(PARTITION BY 馬名 ORDER BY 開催日,レース番号) pidx,
           LAG(開催日) OVER(PARTITION BY 馬名 ORDER BY 開催日,レース番号) pidxd
    FROM コンピ指数
  )
  SELECT
    ci.開催日 d, YEAR(ci.開催日) yy, ci.レース番号 rno, ci.馬名 h,
    ci.指数 idx, ci.指数順位 idxrank, ci.頭数 fld,
    ri.着順 fin, ri.コース種別 surf, ri.距離 dist, ri.馬場 baba,
    o.単勝オッズ tan, o.人気 pop,
    ps.pst,
    CASE WHEN ps.pstd IS NOT NULL AND DATEDIFF(day,ps.pstd,ci.開催日)<=365 THEN ps.pst ELSE NULL END pst365,
    CASE WHEN pc.pidx IS NOT NULL AND DATEDIFF(day,pc.pidxd,ci.開催日)<=120 THEN ci.指数-pc.pidx ELSE NULL END compidelta
  INTO dbo.tk_bt
  FROM コンピ指数 ci
  JOIN レース情報 ri ON ri.開催場所=ci.開催場所 AND ri.開催日=ci.開催日 AND ri.レース番号=ci.レース番号 AND ri.馬番=ci.馬番
  JOIN リアルタイムオッズ o ON o.開催場所=ci.開催場所 AND o.開催日=ci.開催日 AND o.レース番号=ci.レース番号 AND o.馬番=ci.馬番
  LEFT JOIN prevstyle ps ON ps.v=ci.開催場所 AND ps.d=ci.開催日 AND ps.rno=ci.レース番号 AND ps.h=ci.馬名
  LEFT JOIN prevcompi pc ON pc.v=ci.開催場所 AND pc.d=ci.開催日 AND pc.rno=ci.レース番号 AND pc.h=ci.馬名
  WHERE ci.開催場所=N'東京' AND ri.着順>0 AND o.単勝オッズ>0;
END
SELECT COUNT(1) 行, COUNT(DISTINCT CONCAT(d,'-',rno)) R, MIN(yy) 最古年, MAX(yy) 最新年,
 SUM(CASE WHEN idxrank=1 THEN 1 ELSE 0 END) コンピ1位行,
 SUM(CASE WHEN pst365 IS NOT NULL THEN 1 ELSE 0 END) 前走脚質有,
 SUM(CASE WHEN compidelta IS NOT NULL THEN 1 ELSE 0 END) コンピΔ有
FROM dbo.tk_bt;
