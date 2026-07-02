-- 拡張基盤 tk_bt2: クラス/騎手/厩舎/馬齢/性別/斤量/馬体重/枠/ローテ/距離変化 を付与
IF OBJECT_ID('dbo.tk_bt2') IS NULL
BEGIN
  WITH styleall AS (
    SELECT k.開催場所 v,k.開催日 d,k.レース番号 rno,k.馬名 h,k.四コーナー c4,
           COUNT(1) OVER(PARTITION BY k.開催場所,k.開催日,k.レース番号) fld
    FROM 競走結果 k WHERE k.着順>0 AND k.四コーナー>0
  ),
  styled AS (
    SELECT v,d,rno,h, CASE WHEN c4=1 THEN 1 WHEN CAST(c4 AS float)/fld<=0.33 THEN 2 WHEN CAST(c4 AS float)/fld<=0.66 THEN 3 ELSE 4 END st FROM styleall
  ),
  prevstyle AS (
    SELECT v,d,rno,h, LAG(st) OVER(PARTITION BY h ORDER BY d,rno) pst, LAG(d) OVER(PARTITION BY h ORDER BY d,rno) pstd FROM styled
  ),
  prevrace AS (
    SELECT 開催場所 v,開催日 d,レース番号 rno,馬名 h,
           LAG(開催日) OVER(PARTITION BY 馬名 ORDER BY 開催日,レース番号) pdate,
           LAG(距離)  OVER(PARTITION BY 馬名 ORDER BY 開催日,レース番号) pdist
    FROM レース情報 WHERE 着順>0
  ),
  prevcompi AS (
    SELECT 開催場所 v,開催日 d,レース番号 rno,馬名 h, 指数,
           LAG(指数) OVER(PARTITION BY 馬名 ORDER BY 開催日,レース番号) pidx,
           LAG(開催日) OVER(PARTITION BY 馬名 ORDER BY 開催日,レース番号) pidxd
    FROM コンピ指数
  )
  SELECT
    ci.開催日 d, YEAR(ci.開催日) yy, ci.レース番号 rno, ci.馬名 h,
    ci.指数 idx, ci.指数順位 idxrank, ci.頭数 fld,
    ri.着順 fin, ri.コース種別 surf, ri.距離 dist, ri.馬場 baba, ri.条件 joken,
    ri.馬齢 age, ri.性別 sex, ri.騎手 jky, ri.調教師 trn, ri.斤量 kin, ri.馬体重 wt, ri.枠番 waku,
    o.単勝オッズ tan, o.人気 pop,
    CASE WHEN ps.pstd IS NOT NULL AND DATEDIFF(day,ps.pstd,ci.開催日)<=365 THEN ps.pst ELSE NULL END pst365,
    CASE WHEN pr.pdate IS NOT NULL THEN DATEDIFF(day,pr.pdate,ci.開催日) ELSE NULL END rotdays,
    CASE WHEN pr.pdist IS NOT NULL THEN ri.距離-pr.pdist ELSE NULL END distdiff,
    CASE WHEN pc.pidx IS NOT NULL AND DATEDIFF(day,pc.pidxd,ci.開催日)<=120 THEN ci.指数-pc.pidx ELSE NULL END compidelta,
    CASE
      WHEN ri.条件 LIKE N'%新馬%' OR ri.条件 LIKE N'%メイク%' THEN N'1_新馬'
      WHEN ri.条件 LIKE N'%未勝利%' THEN N'2_未勝利'
      WHEN ri.条件 LIKE N'%1勝%' OR ri.条件 LIKE N'%500万%' THEN N'3_1勝'
      WHEN ri.条件 LIKE N'%2勝%' OR ri.条件 LIKE N'%1000万%' THEN N'4_2勝'
      WHEN ri.条件 LIKE N'%3勝%' OR ri.条件 LIKE N'%1600万%' THEN N'5_3勝'
      ELSE N'6_OP重賞' END cls
  INTO dbo.tk_bt2
  FROM コンピ指数 ci
  JOIN レース情報 ri ON ri.開催場所=ci.開催場所 AND ri.開催日=ci.開催日 AND ri.レース番号=ci.レース番号 AND ri.馬番=ci.馬番
  JOIN リアルタイムオッズ o ON o.開催場所=ci.開催場所 AND o.開催日=ci.開催日 AND o.レース番号=ci.レース番号 AND o.馬番=ci.馬番
  LEFT JOIN prevstyle ps ON ps.v=ci.開催場所 AND ps.d=ci.開催日 AND ps.rno=ci.レース番号 AND ps.h=ci.馬名
  LEFT JOIN prevrace pr ON pr.v=ci.開催場所 AND pr.d=ci.開催日 AND pr.rno=ci.レース番号 AND pr.h=ci.馬名
  LEFT JOIN prevcompi pc ON pc.v=ci.開催場所 AND pc.d=ci.開催日 AND pc.rno=ci.レース番号 AND pc.h=ci.馬名
  WHERE ci.開催場所=N'東京' AND ri.着順>0 AND o.単勝オッズ>0;
END
SELECT COUNT(1) 行, COUNT(DISTINCT jky) 騎手数, COUNT(DISTINCT trn) 厩舎数,
 SUM(CASE WHEN rotdays IS NOT NULL THEN 1 ELSE 0 END) ローテ有,
 SUM(CASE WHEN distdiff IS NOT NULL THEN 1 ELSE 0 END) 距離変化有 FROM dbo.tk_bt2;
SELECT cls, COUNT(1) n FROM dbo.tk_bt2 GROUP BY cls ORDER BY cls;
