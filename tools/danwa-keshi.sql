-- 近走コメントの変遷から「消し」パターンを抽出(中央競馬DB)。umacdで時系列化、前走/前々走をLAG、過去5走最高着順をAPPLY。
-- 重視: 人気馬(1-5番)なのに消しになる罠。着順=競走結果、オッズ/人気=リアルタイムオッズ。今走=2023。
SET NOCOUNT ON;
DECLARE @lo date='2022-01-01', @cur_from date='2023-01-01', @cur_to date='2023-12-31';
DECLARE @pos TABLE(kw nvarchar(40));
INSERT INTO @pos(kw) VALUES
 (N'好勝負'),(N'力上位'),(N'力通用'),(N'勝ち負け'),(N'勝負'),(N'勝ち切'),(N'勝機'),(N'チャンス'),
 (N'何とか'),(N'勝てる'),(N'勝ちたい'),(N'能力は高'),(N'能力上位'),(N'地力'),(N'上位争'),(N'通用'),
 (N'自信'),(N'文句な'),(N'態勢'),(N'万全'),(N'絶好'),(N'楽しみ'),(N'いい状態'),(N'状態は良'),
 (N'状態いい'),(N'上向き'),(N'メドは立'),(N'メドが立'),(N'見直'),(N'順番'),(N'やれそう'),(N'崩れ'),
 (N'相手なり'),(N'相手次第'),(N'メンバーひとつ'),(N'展開ひとつ'),(N'続戦');
DECLARE @neg TABLE(kw nvarchar(40));
INSERT INTO @neg(kw) VALUES
 (N'使いな'),(N'使いつつ'),(N'変わり身'),(N'一変'),(N'でどこまで'),(N'もうひとつ'),(N'もう一息'),
 (N'ひと叩'),(N'叩き'),(N'叩いて'),(N'厳しい'),(N'物足'),(N'物見'),(N'展開次第'),(N'良化'),(N'太め'),
 (N'攻め不足'),(N'不安'),(N'二走ボケ'),(N'甘くな'),(N'目標は次'),(N'目標は先'),(N'様子'),(N'大人になり'),
 (N'叩き台'),(N'どうか'),(N'難しい'),(N'こなせば'),(N'課題'),(N'微妙'),(N'ソエ'),(N'脚部不安'),(N'減量');

IF OBJECT_ID('tempdb..#c') IS NOT NULL DROP TABLE #c;
WITH d AS (
  SELECT umacd,開催日,開催場所,レース番号,馬番,印,コメント,
    ROW_NUMBER() OVER(PARTITION BY 開催日,開催場所,レース番号,馬番 ORDER BY 取得日時 DESC) rn
  FROM 厩舎の話 WHERE 開催日 BETWEEN @lo AND @cur_to AND umacd IS NOT NULL AND umacd<>'')
SELECT d.umacd,d.開催日,d.開催場所,d.レース番号,d.馬番,d.印,
  (SELECT COUNT(*) FROM @pos p WHERE d.コメント LIKE N'%'+p.kw+N'%')
  -(SELECT COUNT(*) FROM @neg n WHERE d.コメント LIKE N'%'+n.kw+N'%') AS score,
  k.着順,o.単勝オッズ,o.人気
INTO #c FROM d
LEFT JOIN 競走結果 k ON k.開催日=d.開催日 AND k.開催場所=d.開催場所 AND k.レース番号=d.レース番号 AND k.馬番=d.馬番
LEFT JOIN リアルタイムオッズ o ON o.開催日=d.開催日 AND o.開催場所=d.開催場所 AND o.レース番号=d.レース番号 AND o.馬番=d.馬番
WHERE d.rn=1;

IF OBJECT_ID('tempdb..#r') IS NOT NULL DROP TABLE #r;
SELECT c.*,
  LAG(c.score) OVER(PARTITION BY c.umacd ORDER BY c.開催日,c.レース番号) AS 前s,
  LAG(c.score,2) OVER(PARTITION BY c.umacd ORDER BY c.開催日,c.レース番号) AS 前々s,
  LAG(c.印) OVER(PARTITION BY c.umacd ORDER BY c.開催日,c.レース番号) AS 前印,
  b.best_chaku
INTO #r FROM #c c
OUTER APPLY (SELECT TOP 1 p.着順 best_chaku FROM (SELECT TOP 5 p2.開催日,p2.着順 FROM #c p2
   WHERE p2.umacd=c.umacd AND p2.開催日<c.開催日 AND p2.着順>0 ORDER BY p2.開催日 DESC) p ORDER BY p.着順 ASC) b
WHERE c.開催日 BETWEEN @cur_from AND @cur_to AND c.着順>0;
ALTER TABLE #r ADD 今c nvarchar(2),前c nvarchar(2),前々c nvarchar(2),弱回数 int;
UPDATE #r SET 今c=CASE WHEN score>=1 THEN N'強' WHEN score<=-1 THEN N'弱' ELSE N'中' END,
  前c=CASE WHEN 前s>=1 THEN N'強' WHEN 前s<=-1 THEN N'弱' ELSE N'中' END,
  前々c=CASE WHEN 前々s>=1 THEN N'強' WHEN 前々s<=-1 THEN N'弱' ELSE N'中' END;
UPDATE #r SET 弱回数=(CASE WHEN score<=-1 THEN 1 ELSE 0 END)+(CASE WHEN 前s<=-1 THEN 1 ELSE 0 END)+(CASE WHEN 前々s<=-1 THEN 1 ELSE 0 END);

PRINT '=== 0. ベースライン(2023今走・前走あり) ===';
SELECT COUNT(*) n, CAST(100.0*SUM(CASE WHEN 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) 複勝率,
 CAST(100.0*SUM(CASE WHEN 着順=1 THEN ISNULL(単勝オッズ,0) ELSE 0 END)/COUNT(*) AS decimal(6,1)) 単回収 FROM #r WHERE 前s IS NOT NULL;

PRINT '=== 1. 印遷移ワースト(n>=80, 複勝率の低い順) ===';
SELECT TOP 10 ISNULL(前印,N'(無)')+N'→'+ISNULL(印,N'(無)') 印遷移, COUNT(*) n,
 CAST(100.0*SUM(CASE WHEN 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) 複勝率,
 CAST(100.0*SUM(CASE WHEN 着順=1 THEN ISNULL(単勝オッズ,0) ELSE 0 END)/COUNT(*) AS decimal(6,1)) 単回収,
 CAST(AVG(CAST(人気 AS float)) AS decimal(4,1)) 平均人気
FROM #r GROUP BY ISNULL(前印,N'(無)')+N'→'+ISNULL(印,N'(無)') HAVING COUNT(*)>=80 ORDER BY 複勝率 ASC;

PRINT '=== 2. 直近3走の弱気回数別 ===';
SELECT 弱回数, COUNT(*) n,
 CAST(100.0*SUM(CASE WHEN 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) 複勝率,
 CAST(100.0*SUM(CASE WHEN 着順=1 THEN ISNULL(単勝オッズ,0) ELSE 0 END)/COUNT(*) AS decimal(6,1)) 単回収,
 CAST(AVG(CAST(人気 AS float)) AS decimal(4,1)) 平均人気
FROM #r WHERE 前々s IS NOT NULL GROUP BY 弱回数 ORDER BY 弱回数;

PRINT '=== 3. 前走class×今走class 複勝率(消しセル探し) ===';
SELECT 前c 前走,今c 今走,COUNT(*) n,
 CAST(100.0*SUM(CASE WHEN 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) 複勝率,
 CAST(100.0*SUM(CASE WHEN 着順=1 THEN ISNULL(単勝オッズ,0) ELSE 0 END)/COUNT(*) AS decimal(6,1)) 単回収
FROM #r WHERE 前s IS NOT NULL GROUP BY 前c,今c ORDER BY 複勝率 ASC;

PRINT '=== 4. 人気馬の罠: 1-5番人気のみ 消しパターン別 複勝率(市場が買う中での過小評価検出) ===';
SELECT パターン, COUNT(*) n,
 CAST(100.0*SUM(CASE WHEN 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) 複勝率,
 CAST(100.0*SUM(CASE WHEN 着順=1 THEN ISNULL(単勝オッズ,0) ELSE 0 END)/COUNT(*) AS decimal(6,1)) 単回収
FROM (
  SELECT 着順,単勝オッズ, パターン FROM #r CROSS APPLY (VALUES
    (N'今△'),
    (CASE WHEN 今c=N'弱' AND 前c=N'弱' THEN N'2走連続弱気' END),
    (CASE WHEN 今c=N'弱' THEN N'今弱気' END),
    (CASE WHEN 前印=N'◎' AND 印<>N'◎' THEN N'◎から降格' END),
    (CASE WHEN best_chaku>=6 AND 今c=N'弱' THEN N'地力薄(最高6着↓)×今弱気' END),
    (N'(参考)1-5番全体')
  ) v(パターン)
  WHERE 人気 BETWEEN 1 AND 5 AND (パターン=N'今△'
     OR (パターン=N'2走連続弱気' AND 今c=N'弱' AND 前c=N'弱')
     OR (パターン=N'今弱気' AND 今c=N'弱')
     OR (パターン=N'◎から降格' AND 前印=N'◎' AND 印<>N'◎')
     OR (パターン=N'地力薄(最高6着↓)×今弱気' AND best_chaku>=6 AND 今c=N'弱')
     OR パターン=N'(参考)1-5番全体')
    AND (印=N'△' OR パターン<>N'今△')
) t GROUP BY パターン ORDER BY 複勝率 ASC;

PRINT '=== 5. 消しルール候補: 全体での効き(n/複勝率/単回収 と 1-5番人気での該当) ===';
SELECT ルール, COUNT(*) 全n,
 CAST(100.0*SUM(CASE WHEN 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) 複勝率,
 CAST(100.0*SUM(CASE WHEN 着順=1 THEN ISNULL(単勝オッズ,0) ELSE 0 END)/COUNT(*) AS decimal(6,1)) 単回収,
 SUM(CASE WHEN 人気 BETWEEN 1 AND 5 THEN 1 ELSE 0 END) 人気1_5n,
 CAST(100.0*SUM(CASE WHEN 人気 BETWEEN 1 AND 5 AND 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN 人気 BETWEEN 1 AND 5 THEN 1 ELSE 0 END),0) AS decimal(5,1)) 人気1_5複勝率
FROM (
 SELECT 着順,単勝オッズ,人気,N'A:今△' ルール FROM #r WHERE 印=N'△'
 UNION ALL SELECT 着順,単勝オッズ,人気,N'B:2走連続弱気' FROM #r WHERE 今c=N'弱' AND 前c=N'弱'
 UNION ALL SELECT 着順,単勝オッズ,人気,N'C:◎から降格(◎→非◎)' FROM #r WHERE 前印=N'◎' AND 印<>N'◎'
 UNION ALL SELECT 着順,単勝オッズ,人気,N'D:地力薄×今弱気' FROM #r WHERE best_chaku>=6 AND 今c=N'弱'
 UNION ALL SELECT 着順,単勝オッズ,人気,N'E:3走連続弱気' FROM #r WHERE 弱回数=3 AND 前々s IS NOT NULL
) t GROUP BY ルール ORDER BY 複勝率 ASC;
