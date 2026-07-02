-- 厩舎の話の効きを文脈別に分析(中央競馬DB, 2023): クラス別/距離・芝ダ別/騎手乗替×コメント/調教矢印×コメント併用。
-- 着順=競走結果、距離・条件・騎手=レース情報、矢印=調教、オッズ=リアルタイムオッズ。umacdで時系列化(前走騎手=乗替判定)。
SET NOCOUNT ON;
DECLARE @lo date='2022-01-01', @cf date='2023-01-01', @ct date='2023-12-31';
DECLARE @pos TABLE(kw nvarchar(40)); INSERT INTO @pos(kw) VALUES
 (N'好勝負'),(N'力上位'),(N'力通用'),(N'勝ち負け'),(N'勝負'),(N'勝ち切'),(N'勝機'),(N'チャンス'),(N'何とか'),(N'勝てる'),(N'勝ちたい'),
 (N'能力は高'),(N'能力上位'),(N'地力'),(N'上位争'),(N'通用'),(N'自信'),(N'文句な'),(N'態勢'),(N'万全'),(N'絶好'),(N'楽しみ'),
 (N'いい状態'),(N'状態は良'),(N'状態いい'),(N'上向き'),(N'メドは立'),(N'メドが立'),(N'見直'),(N'順番'),(N'やれそう'),(N'崩れ'),(N'相手なり'),(N'相手次第'),(N'メンバーひとつ'),(N'展開ひとつ'),(N'続戦');
DECLARE @neg TABLE(kw nvarchar(40)); INSERT INTO @neg(kw) VALUES
 (N'使いな'),(N'使いつつ'),(N'変わり身'),(N'一変'),(N'でどこまで'),(N'もうひとつ'),(N'もう一息'),(N'ひと叩'),(N'叩き'),(N'叩いて'),(N'厳しい'),
 (N'物足'),(N'物見'),(N'展開次第'),(N'良化'),(N'太め'),(N'攻め不足'),(N'不安'),(N'二走ボケ'),(N'甘くな'),(N'目標は次'),(N'目標は先'),(N'様子'),(N'大人になり'),(N'叩き台'),(N'どうか'),(N'難しい'),(N'こなせば'),(N'課題'),(N'微妙'),(N'ソエ'),(N'脚部不安'),(N'減量');

IF OBJECT_ID('tempdb..#c') IS NOT NULL DROP TABLE #c;
WITH d AS (
  SELECT umacd,開催日,開催場所,レース番号,馬番,印,コメント,
    ROW_NUMBER() OVER(PARTITION BY 開催日,開催場所,レース番号,馬番 ORDER BY 取得日時 DESC) rn
  FROM 厩舎の話 WHERE 開催日 BETWEEN @lo AND @ct AND umacd IS NOT NULL AND umacd<>'')
SELECT d.umacd,d.開催日,d.開催場所,d.レース番号,d.馬番,d.印,
  (SELECT COUNT(*) FROM @pos p WHERE d.コメント LIKE N'%'+p.kw+N'%')-(SELECT COUNT(*) FROM @neg n WHERE d.コメント LIKE N'%'+n.kw+N'%') AS score,
  k.着順,o.単勝オッズ,o.人気, r.騎手, r.距離, r.コース種別, r.条件, cy.矢印
INTO #c FROM d
LEFT JOIN 競走結果 k ON k.開催日=d.開催日 AND k.開催場所=d.開催場所 AND k.レース番号=d.レース番号 AND k.馬番=d.馬番
LEFT JOIN リアルタイムオッズ o ON o.開催日=d.開催日 AND o.開催場所=d.開催場所 AND o.レース番号=d.レース番号 AND o.馬番=d.馬番
LEFT JOIN レース情報 r ON r.開催日=d.開催日 AND r.開催場所=d.開催場所 AND r.レース番号=d.レース番号 AND r.馬番=d.馬番
LEFT JOIN 調教 cy ON cy.開催日=d.開催日 AND cy.開催場所=d.開催場所 AND cy.レース番号=d.レース番号 AND cy.馬番=d.馬番
WHERE d.rn=1;

IF OBJECT_ID('tempdb..#r') IS NOT NULL DROP TABLE #r;
SELECT c.*, LAG(c.騎手) OVER(PARTITION BY c.umacd ORDER BY c.開催日,c.レース番号) AS 前騎手
INTO #r FROM #c c WHERE c.開催日 BETWEEN @cf AND @ct AND c.着順>0;
ALTER TABLE #r ADD 今c nvarchar(2), classcat nvarchar(10), 距離帯 nvarchar(8), 乗替 nvarchar(6);
UPDATE #r SET 今c=CASE WHEN score>=1 THEN N'強' WHEN score<=-1 THEN N'弱' ELSE N'中' END,
 classcat=CASE WHEN 条件 LIKE N'%新馬%' THEN N'1新馬' WHEN 条件 LIKE N'%未勝利%' THEN N'2未勝利' WHEN 条件 LIKE N'%1勝%' THEN N'3_1勝'
   WHEN 条件 LIKE N'%2勝%' THEN N'4_2勝' WHEN 条件 LIKE N'%3勝%' THEN N'5_3勝' WHEN 条件 LIKE N'%オープン%' THEN N'6OP' ELSE N'9他' END,
 距離帯=CASE WHEN 距離<=1300 THEN N'1短' WHEN 距離<=1600 THEN N'2マイル' WHEN 距離<=2000 THEN N'3中' ELSE N'4長' END,
 乗替=CASE WHEN 前騎手 IS NULL OR 前騎手=N'' THEN N'不明' WHEN 前騎手=騎手 THEN N'継続' ELSE N'乗替' END;

PRINT '=== A. クラス別: 強気/弱気の複勝率 ===';
SELECT classcat AS クラス, COUNT(*) n,
 CAST(100.0*SUM(CASE WHEN 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) 全体,
 SUM(CASE WHEN 今c=N'強' THEN 1 ELSE 0 END) 強n,
 CAST(100.0*SUM(CASE WHEN 今c=N'強' AND 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN 今c=N'強' THEN 1 ELSE 0 END),0) AS decimal(5,1)) 強気複勝,
 CAST(100.0*SUM(CASE WHEN 今c=N'弱' AND 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN 今c=N'弱' THEN 1 ELSE 0 END),0) AS decimal(5,1)) 弱気複勝
FROM #r GROUP BY classcat ORDER BY classcat;

PRINT '=== B. 距離帯×芝ダ: 強気/弱気の複勝率 ===';
SELECT コース種別 AS 種別, 距離帯, COUNT(*) n,
 CAST(100.0*SUM(CASE WHEN 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) 全体,
 CAST(100.0*SUM(CASE WHEN 今c=N'強' AND 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN 今c=N'強' THEN 1 ELSE 0 END),0) AS decimal(5,1)) 強気複勝,
 CAST(100.0*SUM(CASE WHEN 今c=N'弱' AND 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN 今c=N'弱' THEN 1 ELSE 0 END),0) AS decimal(5,1)) 弱気複勝
FROM #r WHERE コース種別 IN(N'芝',N'ダ') GROUP BY コース種別,距離帯 ORDER BY コース種別,距離帯;

PRINT '=== C. 騎手乗替 × コメントclass ===';
SELECT 乗替, 今c AS コメント, COUNT(*) n,
 CAST(100.0*SUM(CASE WHEN 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) 複勝率,
 CAST(100.0*SUM(CASE WHEN 着順=1 THEN ISNULL(単勝オッズ,0) ELSE 0 END)/COUNT(*) AS decimal(6,1)) 単回収,
 CAST(AVG(CAST(人気 AS float)) AS decimal(4,1)) 平均人気
FROM #r WHERE 乗替 IN(N'継続',N'乗替') GROUP BY 乗替,今c ORDER BY 乗替,今c;

PRINT '=== D. 調教矢印 × コメントclass(併用) ===';
SELECT ISNULL(矢印,N'(無)') AS 矢印, 今c AS コメント, COUNT(*) n,
 CAST(100.0*SUM(CASE WHEN 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) 複勝率,
 CAST(100.0*SUM(CASE WHEN 着順=1 THEN ISNULL(単勝オッズ,0) ELSE 0 END)/COUNT(*) AS decimal(6,1)) 単回収,
 CAST(AVG(CAST(人気 AS float)) AS decimal(4,1)) 平均人気
FROM #r WHERE 矢印 IN(N'→',N'↗',N'↘') GROUP BY 矢印,今c HAVING COUNT(*)>=50 ORDER BY 複勝率 DESC;

PRINT '=== E. 合わせ技: 強気×矢印↗×乗替 などの上位/下位 ===';
SELECT 今c+N'/'+ISNULL(矢印,N'-')+N'/'+乗替 AS 組合せ, COUNT(*) n,
 CAST(100.0*SUM(CASE WHEN 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) 複勝率,
 CAST(100.0*SUM(CASE WHEN 着順=1 THEN ISNULL(単勝オッズ,0) ELSE 0 END)/COUNT(*) AS decimal(6,1)) 単回収,
 CAST(AVG(CAST(人気 AS float)) AS decimal(4,1)) 平均人気
FROM #r WHERE 矢印 IN(N'→',N'↗') AND 乗替 IN(N'継続',N'乗替')
GROUP BY 今c+N'/'+ISNULL(矢印,N'-')+N'/'+乗替 HAVING COUNT(*)>=100 ORDER BY 複勝率 DESC;
