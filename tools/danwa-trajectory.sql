-- 厩舎の話の「変化」で勝負気配を読む: 馬(umacd)ごとに時系列で前走/前々走のコメント強気スコア・印を辿り、今走着順との関係を見る。
-- danwaは2022-2023完全。今走=2023(結果あり)。前走/前々走コメントは2022-2023から取得。着順=競走結果、オッズ=リアルタイムオッズ。
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

-- 各馬×開催日の最新コメントの強気スコアと印
IF OBJECT_ID('tempdb..#c') IS NOT NULL DROP TABLE #c;
WITH d AS (
  SELECT umacd, 開催日, 開催場所, レース番号, 馬番, 印, コメント,
    ROW_NUMBER() OVER(PARTITION BY 開催日,開催場所,レース番号,馬番 ORDER BY 取得日時 DESC) rn
  FROM 厩舎の話 WHERE 開催日 BETWEEN @lo AND @cur_to AND umacd IS NOT NULL AND umacd<>'')
SELECT umacd, 開催日, 開催場所, レース番号, 馬番, 印,
  (SELECT COUNT(*) FROM @pos p WHERE コメント LIKE N'%'+p.kw+N'%')
  -(SELECT COUNT(*) FROM @neg n WHERE コメント LIKE N'%'+n.kw+N'%') AS score
INTO #c FROM d WHERE rn=1;

-- 時系列LAG(前走/前々走)
IF OBJECT_ID('tempdb..#q') IS NOT NULL DROP TABLE #q;
SELECT *,
  LAG(score) OVER(PARTITION BY umacd ORDER BY 開催日, レース番号) AS 前走score,
  LAG(score,2) OVER(PARTITION BY umacd ORDER BY 開催日, レース番号) AS 前々走score,
  LAG(印) OVER(PARTITION BY umacd ORDER BY 開催日, レース番号) AS 前走印,
  LAG(開催日) OVER(PARTITION BY umacd ORDER BY 開催日, レース番号) AS 前走日
INTO #q FROM #c;

-- 今走(2023)×着順
IF OBJECT_ID('tempdb..#r') IS NOT NULL DROP TABLE #r;
SELECT q.*, k.着順, o.単勝オッズ, o.人気,
  CASE WHEN q.score>=1 THEN N'強' WHEN q.score<=-1 THEN N'弱' ELSE N'中' END AS 今class,
  CASE WHEN q.前走score>=1 THEN N'強' WHEN q.前走score<=-1 THEN N'弱' ELSE N'中' END AS 前class
INTO #r
FROM #q q
JOIN 競走結果 k ON k.開催日=q.開催日 AND k.開催場所=q.開催場所 AND k.レース番号=q.レース番号 AND k.馬番=q.馬番
LEFT JOIN リアルタイムオッズ o ON o.開催日=q.開催日 AND o.開催場所=q.開催場所 AND o.レース番号=q.レース番号 AND o.馬番=q.馬番
WHERE q.開催日 BETWEEN @cur_from AND @cur_to AND q.前走score IS NOT NULL AND k.着順>0;

PRINT '=== 0. 母数(前走コメントあり 2023今走) ===';
SELECT COUNT(*) AS n FROM #r;

PRINT '=== 1. 変化Δ(今走score - 前走score)別 ===';
SELECT CASE WHEN score-前走score<=-2 THEN N'a:大悪化' WHEN score-前走score=-1 THEN N'b:悪化'
            WHEN score-前走score=0 THEN N'c:横ばい' WHEN score-前走score=1 THEN N'd:改善' ELSE N'e:大改善' END AS 変化,
 COUNT(*) AS n,
 CAST(100.0*SUM(CASE WHEN 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) AS 複勝率,
 CAST(100.0*SUM(CASE WHEN 着順=1 THEN ISNULL(単勝オッズ,0) ELSE 0 END)/COUNT(*) AS decimal(6,1)) AS 単回収,
 CAST(AVG(CAST(人気 AS float)) AS decimal(4,1)) AS 平均人気
FROM #r GROUP BY CASE WHEN score-前走score<=-2 THEN N'a:大悪化' WHEN score-前走score=-1 THEN N'b:悪化'
            WHEN score-前走score=0 THEN N'c:横ばい' WHEN score-前走score=1 THEN N'd:改善' ELSE N'e:大改善' END
ORDER BY 変化;

PRINT '=== 2. 今走class × 前走class マトリクス(新規強気 vs 継続強気 等) ===';
SELECT 前class AS 前走, 今class AS 今走, COUNT(*) AS n,
 CAST(100.0*SUM(CASE WHEN 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) AS 複勝率,
 CAST(100.0*SUM(CASE WHEN 着順=1 THEN ISNULL(単勝オッズ,0) ELSE 0 END)/COUNT(*) AS decimal(6,1)) AS 単回収,
 CAST(AVG(CAST(人気 AS float)) AS decimal(4,1)) AS 平均人気
FROM #r GROUP BY 前class, 今class ORDER BY 今class, 前class;

PRINT '=== 3. 今走=強気のみ: 前走が強気だったか否かで比較(勝負気配=新規強気?) ===';
SELECT CASE WHEN 前class=N'強' THEN N'継続強気(前走も強)' ELSE N'新規強気(前走 中/弱)' END AS 型,
 COUNT(*) AS n,
 CAST(100.0*SUM(CASE WHEN 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) AS 複勝率,
 CAST(100.0*SUM(CASE WHEN 着順=1 THEN ISNULL(単勝オッズ,0) ELSE 0 END)/COUNT(*) AS decimal(6,1)) AS 単回収,
 CAST(AVG(CAST(人気 AS float)) AS decimal(4,1)) AS 平均人気
FROM #r WHERE 今class=N'強'
GROUP BY CASE WHEN 前class=N'強' THEN N'継続強気(前走も強)' ELSE N'新規強気(前走 中/弱)' END;

PRINT '=== 4. 3走トレンド(前々走→前走→今走)別 ===';
SELECT CASE
   WHEN 前々走score IS NULL THEN N'z:前々走なし'
   WHEN score>前走score AND 前走score>=前々走score THEN N'1:一貫上昇'
   WHEN score>=前走score AND 前走score>前々走score THEN N'1:一貫上昇'
   WHEN score<前走score AND 前走score<=前々走score THEN N'4:一貫下降'
   WHEN score<=前走score AND 前走score<前々走score THEN N'4:一貫下降'
   WHEN score>前走score THEN N'2:直近上昇'
   WHEN score<前走score THEN N'3:直近下降'
   ELSE N'0:横ばい' END AS トレンド,
 COUNT(*) AS n,
 CAST(100.0*SUM(CASE WHEN 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) AS 複勝率,
 CAST(100.0*SUM(CASE WHEN 着順=1 THEN ISNULL(単勝オッズ,0) ELSE 0 END)/COUNT(*) AS decimal(6,1)) AS 単回収
FROM #r GROUP BY CASE
   WHEN 前々走score IS NULL THEN N'z:前々走なし'
   WHEN score>前走score AND 前走score>=前々走score THEN N'1:一貫上昇'
   WHEN score>=前走score AND 前走score>前々走score THEN N'1:一貫上昇'
   WHEN score<前走score AND 前走score<=前々走score THEN N'4:一貫下降'
   WHEN score<=前走score AND 前走score<前々走score THEN N'4:一貫下降'
   WHEN score>前走score THEN N'2:直近上昇'
   WHEN score<前走score THEN N'3:直近下降'
   ELSE N'0:横ばい' END
ORDER BY トレンド;

PRINT '=== 5. 印の昇格(前走印→今走印): 新規◎ 等 ===';
SELECT ISNULL(前走印,N'(無)')+N'→'+ISNULL(印,N'(無)') AS 印遷移, COUNT(*) AS n,
 CAST(100.0*SUM(CASE WHEN 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) AS 複勝率,
 CAST(100.0*SUM(CASE WHEN 着順=1 THEN ISNULL(単勝オッズ,0) ELSE 0 END)/COUNT(*) AS decimal(6,1)) AS 単回収,
 CAST(AVG(CAST(人気 AS float)) AS decimal(4,1)) AS 平均人気
FROM #r GROUP BY ISNULL(前走印,N'(無)')+N'→'+ISNULL(印,N'(無)')
HAVING COUNT(*)>=80 ORDER BY 複勝率 DESC;
