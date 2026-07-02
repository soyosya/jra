-- 当日カード: 指定日(@date)の各レースを danwa+調教 統合スコアV3 で評価し、買い軸/相手/消し+コンピ順位+人気を出力。
-- 事前に fetch-danwa / fetch-cyokyo / fetch-compi 済みの日を指定。@venue で場を絞ると読みやすい(NULLで全場)。
SET NOCOUNT ON;
DECLARE @date date='2026-06-14', @venue nvarchar(10)=N'東京';
DECLARE @lo date=DATEADD(day,-800,@date);
DECLARE @pos TABLE(kw nvarchar(40)); INSERT INTO @pos(kw) VALUES
 (N'好勝負'),(N'力上位'),(N'力通用'),(N'勝ち負け'),(N'勝負'),(N'勝ち切'),(N'勝機'),(N'チャンス'),(N'何とか'),(N'勝てる'),(N'勝ちたい'),
 (N'能力は高'),(N'能力上位'),(N'地力'),(N'上位争'),(N'通用'),(N'自信'),(N'文句な'),(N'態勢'),(N'万全'),(N'絶好'),(N'楽しみ'),
 (N'いい状態'),(N'状態は良'),(N'状態いい'),(N'上向き'),(N'メドは立'),(N'メドが立'),(N'見直'),(N'順番'),(N'やれそう'),(N'崩れ'),(N'相手なり'),(N'相手次第'),(N'メンバーひとつ'),(N'展開ひとつ'),(N'続戦');
DECLARE @neg TABLE(kw nvarchar(40)); INSERT INTO @neg(kw) VALUES
 (N'使いな'),(N'使いつつ'),(N'変わり身'),(N'一変'),(N'でどこまで'),(N'もうひとつ'),(N'もう一息'),(N'ひと叩'),(N'叩き'),(N'叩いて'),(N'厳しい'),
 (N'物足'),(N'物見'),(N'展開次第'),(N'良化'),(N'太め'),(N'攻め不足'),(N'不安'),(N'二走ボケ'),(N'甘くな'),(N'目標は次'),(N'目標は先'),(N'様子'),(N'大人になり'),(N'叩き台'),(N'どうか'),(N'難しい'),(N'こなせば'),(N'課題'),(N'微妙'),(N'ソエ'),(N'脚部不安'),(N'減量');

IF OBJECT_ID('tempdb..#c') IS NOT NULL DROP TABLE #c;
WITH d AS (
  SELECT umacd,開催日,開催場所,レース番号,馬番,馬名,印,コメント,
    ROW_NUMBER() OVER(PARTITION BY 開催日,開催場所,レース番号,馬番 ORDER BY 取得日時 DESC) rn
  FROM 厩舎の話 WHERE 開催日 BETWEEN @lo AND @date AND umacd IS NOT NULL AND umacd<>'')
SELECT d.umacd,d.開催日,d.開催場所,d.レース番号,d.馬番,d.馬名,d.印,
  (SELECT COUNT(*) FROM @pos p WHERE d.コメント LIKE N'%'+p.kw+N'%') AS pos,
  (SELECT COUNT(*) FROM @neg n WHERE d.コメント LIKE N'%'+n.kw+N'%') AS neg, LEN(d.コメント) clen,
  k.着順, r.距離, r.コース種別, cy.矢印, cy.追い切り短評 AS tanpyo,
  CASE d.印 WHEN N'◎' THEN 3 WHEN N'▲' THEN 1 WHEN N'△' THEN -3 WHEN N'注' THEN -1 ELSE 0 END AS 印pt
INTO #c FROM d
OUTER APPLY (SELECT TOP 1 着順 FROM 競走結果 k0 WHERE k0.開催日=d.開催日 AND k0.開催場所=d.開催場所 AND k0.レース番号=d.レース番号 AND k0.馬番=d.馬番) k
OUTER APPLY (SELECT TOP 1 距離,コース種別 FROM レース情報 r0 WHERE r0.開催日=d.開催日 AND r0.開催場所=d.開催場所 AND r0.レース番号=d.レース番号 AND r0.馬番=d.馬番) r
OUTER APPLY (SELECT TOP 1 矢印,追い切り短評 FROM 調教 cy0 WHERE cy0.開催日=d.開催日 AND cy0.開催場所=d.開催場所 AND cy0.レース番号=d.レース番号 AND cy0.馬番=d.馬番 ORDER BY 取得日時 DESC) cy
WHERE d.rn=1;

IF OBJECT_ID('tempdb..#r') IS NOT NULL DROP TABLE #r;
SELECT c.*,
  LAG(c.印) OVER(PARTITION BY c.umacd ORDER BY c.開催日,c.レース番号) AS 前印,
  LAG(c.コース種別) OVER(PARTITION BY c.umacd ORDER BY c.開催日,c.レース番号) AS 前コース,
  LAG(c.距離) OVER(PARTITION BY c.umacd ORDER BY c.開催日,c.レース番号) AS 前距離,
  b.best_chaku
INTO #r FROM #c c
OUTER APPLY (SELECT TOP 1 p.着順 best_chaku FROM (SELECT TOP 5 p2.開催日,p2.着順 FROM #c p2
   WHERE p2.umacd=c.umacd AND p2.開催日<c.開催日 AND p2.着順>0 ORDER BY p2.開催日 DESC) p ORDER BY p.着順 ASC) b
WHERE c.開催日=@date AND (@venue IS NULL OR c.開催場所=@venue);

ALTER TABLE #r ADD 追切class nvarchar(2), v3 int, 消し bit;
UPDATE #r SET 追切class = CASE
  WHEN tanpyo LIKE N'%軽快%' OR tanpyo LIKE N'%力強い%' OR tanpyo LIKE N'%好調%' OR tanpyo LIKE N'%手応え十分%' OR tanpyo LIKE N'%シャープ%' OR tanpyo LIKE N'%活気%' OR tanpyo LIKE N'%上昇気配%' OR tanpyo LIKE N'%ハツラツ%' OR tanpyo LIKE N'%好気配%' OR tanpyo LIKE N'%抜群%' OR tanpyo LIKE N'%伸び脚%' THEN N'好'
  WHEN tanpyo LIKE N'%欠け%' OR tanpyo LIKE N'%ひと息%' OR tanpyo LIKE N'%平凡%' OR tanpyo LIKE N'%物足%' OR tanpyo LIKE N'%変わり身無%' OR tanpyo LIKE N'%軽め%' OR tanpyo LIKE N'%地味%' THEN N'凡' ELSE N'中' END;
UPDATE #r SET v3 = 印pt + (pos-neg) - (CASE WHEN clen<30 THEN 1 ELSE 0 END)
   + (CASE WHEN 印=N'◎' AND (前印<>N'◎' OR 前印 IS NULL) THEN 1 ELSE 0 END)
   - (CASE WHEN 前印=N'◎' AND 印=N'△' THEN 2 ELSE 0 END)
   + (CASE 矢印 WHEN N'↗' THEN 2 WHEN N'↑' THEN 2 WHEN N'↘' THEN -3 WHEN N'↓' THEN -3 ELSE 0 END)
   + (CASE 追切class WHEN N'好' THEN 1 WHEN N'凡' THEN -2 ELSE 0 END)
   + (CASE WHEN best_chaku=1 AND 印=N'◎' THEN 1 ELSE 0 END)
   - (CASE WHEN 前コース=N'ダ' AND コース種別=N'芝' THEN 2 ELSE 0 END)
   - (CASE WHEN 距離-前距離>=200 THEN 1 ELSE 0 END);
UPDATE #r SET 消し = CASE WHEN 印=N'△' OR 矢印 IN(N'↘',N'↓') OR (追切class=N'凡' AND (pos-neg)<=-1)
   OR (前コース=N'ダ' AND コース種別=N'芝') OR (best_chaku>=6 AND (pos-neg)<=-1) THEN 1 ELSE 0 END;

PRINT '=== 当日カード(V3降順、コンピ順位/人気併記) ===';
SELECT r.開催場所 AS 場, r.レース番号 AS R, r.馬番, LEFT(r.馬名,8) AS 馬名, ISNULL(r.印,N'') AS 印, r.v3,
  CASE WHEN r.消し=1 THEN N'消' WHEN r.v3>=5 THEN N'◎軸' WHEN r.v3>=3 THEN N'○相手' WHEN r.v3>=1 THEN N'△' ELSE N'' END AS 評価,
  ISNULL(r.矢印,N'') AS 矢, ISNULL(r.追切class,N'') AS 追,
  cp.指数順位 AS コンピ, o.人気
FROM #r r
OUTER APPLY (SELECT TOP 1 指数順位 FROM コンピ指数 z WHERE z.開催日=r.開催日 AND z.開催場所=r.開催場所 AND z.レース番号=r.レース番号 AND z.馬番=r.馬番 ORDER BY 取得日時 DESC) cp
OUTER APPLY (SELECT TOP 1 人気 FROM リアルタイムオッズ z2 WHERE z2.開催日=r.開催日 AND z2.開催場所=r.開催場所 AND z2.レース番号=r.レース番号 AND z2.馬番=r.馬番 ORDER BY 日時 DESC) o
ORDER BY r.レース番号, r.v3 DESC, r.馬番;
