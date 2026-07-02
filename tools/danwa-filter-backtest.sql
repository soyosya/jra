-- 厩舎の話 精緻化辞書+実用フィルタのバックテスト(中央競馬DB)。
-- 2023を 前半(学習)=@from..@split未満 / 後半(検証)=@split以降 に分け、検証側の成績で評価(in-sample誇張を排除)。
-- 着順=競走結果、単勝オッズ/人気=リアルタイムオッズ、複勝払戻=払戻金、調教師=レース情報。
SET NOCOUNT ON;
DECLARE @from date='2023-01-01', @to date='2023-12-31', @split date='2023-07-01';

-- 精緻化(実測ベース): 自信・能力・仕上がり済=正、仕上げ途上・願望・疑問=負。
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

IF OBJECT_ID('tempdb..#s') IS NOT NULL DROP TABLE #s;
WITH d AS (
  SELECT *, ROW_NUMBER() OVER(PARTITION BY 開催日,開催場所,レース番号,馬番 ORDER BY 取得日時 DESC) rn
  FROM 厩舎の話 WHERE 開催日 BETWEEN @from AND @to)
SELECT d.開催日,d.馬番,d.印, k.着順, o.単勝オッズ, o.人気,
  (SELECT COUNT(*) FROM @pos p WHERE d.コメント LIKE N'%'+p.kw+N'%') AS pos,
  (SELECT COUNT(*) FROM @neg n WHERE d.コメント LIKE N'%'+n.kw+N'%') AS neg,
  LEN(d.コメント) AS clen,
  CASE WHEN d.開催日 < @split THEN N'学習' ELSE N'検証' END AS 期,
  (SELECT TOP 1 pay.金額 FROM 払戻金 pay WHERE pay.開催日=d.開催日 AND pay.開催場所=d.開催場所
        AND pay.レース番号=d.レース番号 AND pay.馬券=N'複勝' AND pay.組番=CAST(d.馬番 AS nvarchar(8))) AS 複勝払戻
INTO #s
FROM d
JOIN 競走結果 k ON k.開催日=d.開催日 AND k.開催場所=d.開催場所 AND k.レース番号=d.レース番号 AND k.馬番=d.馬番
LEFT JOIN リアルタイムオッズ o ON o.開催日=d.開催日 AND o.開催場所=d.開催場所 AND o.レース番号=d.レース番号 AND o.馬番=d.馬番
WHERE d.rn=1 AND d.コメント IS NOT NULL AND k.着順>0;

-- 印ポイント + 語句スコア + 短文減点
ALTER TABLE #s ADD 印pt int, score int, class nvarchar(6);
UPDATE #s SET 印pt = CASE 印 WHEN N'◎' THEN 3 WHEN N'▲' THEN 1 WHEN N'△' THEN -3 WHEN N'注' THEN -1 ELSE 0 END;
UPDATE #s SET score = 印pt + pos - neg - (CASE WHEN clen<30 THEN 1 ELSE 0 END);
UPDATE #s SET class = CASE WHEN pos-neg>=1 THEN N'強気' WHEN pos-neg<=-1 THEN N'弱気' ELSE N'中立' END;

PRINT '=== 1. 精緻化辞書: 語句クラス別 複勝率(学習 vs 検証=OOS) ===';
SELECT 期, class, COUNT(*) AS n,
 CAST(100.0*SUM(CASE WHEN 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) AS 複勝率,
 CAST(100.0*SUM(CASE WHEN 着順=1 THEN ISNULL(単勝オッズ,0) ELSE 0 END)/COUNT(*) AS decimal(6,1)) AS 単回収
FROM #s GROUP BY 期, class ORDER BY 期 DESC, CASE class WHEN N'強気' THEN 1 WHEN N'中立' THEN 2 ELSE 3 END;

PRINT '=== 2. 実用フィルタ: 総合スコア帯別 成績(検証=後半のみ) ===';
SELECT
 CASE WHEN score<=-2 THEN N'a:〜-2' WHEN score<=0 THEN N'b:-1〜0' WHEN score=1 THEN N'c:1'
      WHEN score=2 THEN N'd:2' WHEN score=3 THEN N'e:3' ELSE N'f:4〜' END AS スコア帯,
 COUNT(*) AS n,
 CAST(100.0*SUM(CASE WHEN 着順=1 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) AS 勝率,
 CAST(100.0*SUM(CASE WHEN 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) AS 複勝率,
 CAST(1.0*SUM(ISNULL(複勝払戻,0))/COUNT(*) AS decimal(6,1)) AS 複勝回収,
 CAST(100.0*SUM(CASE WHEN 着順=1 THEN ISNULL(単勝オッズ,0) ELSE 0 END)/COUNT(*) AS decimal(6,1)) AS 単回収,
 CAST(AVG(CAST(人気 AS float)) AS decimal(4,1)) AS 平均人気
FROM #s WHERE 期=N'検証'
GROUP BY CASE WHEN score<=-2 THEN N'a:〜-2' WHEN score<=0 THEN N'b:-1〜0' WHEN score=1 THEN N'c:1'
      WHEN score=2 THEN N'd:2' WHEN score=3 THEN N'e:3' ELSE N'f:4〜' END
ORDER BY スコア帯;

PRINT '=== 3. 妙味検出: 高スコア(score>=2) × 人気帯 複勝回収(検証) ===';
SELECT
 CASE WHEN 人気<=3 THEN N'1-3番人気' WHEN 人気<=6 THEN N'4-6番' WHEN 人気<=9 THEN N'7-9番' ELSE N'10番〜' END AS 人気帯,
 COUNT(*) AS n,
 CAST(100.0*SUM(CASE WHEN 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) AS 複勝率,
 CAST(1.0*SUM(ISNULL(複勝払戻,0))/COUNT(*) AS decimal(6,1)) AS 複勝回収,
 CAST(100.0*SUM(CASE WHEN 着順=1 THEN ISNULL(単勝オッズ,0) ELSE 0 END)/COUNT(*) AS decimal(6,1)) AS 単回収
FROM #s WHERE 期=N'検証' AND score>=2 AND 人気>0
GROUP BY CASE WHEN 人気<=3 THEN N'1-3番人気' WHEN 人気<=6 THEN N'4-6番' WHEN 人気<=9 THEN N'7-9番' ELSE N'10番〜' END
ORDER BY 人気帯;

PRINT '=== 4. 印×強気スコア の複勝率マトリクス(検証) ===';
SELECT 印pt AS 印ポイント,
 SUM(CASE WHEN pos-neg>=1 THEN 1 ELSE 0 END) AS 強気n,
 CAST(100.0*SUM(CASE WHEN pos-neg>=1 AND 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN pos-neg>=1 THEN 1 ELSE 0 END),0) AS decimal(5,1)) AS 強気時複勝,
 SUM(CASE WHEN pos-neg<=-1 THEN 1 ELSE 0 END) AS 弱気n,
 CAST(100.0*SUM(CASE WHEN pos-neg<=-1 AND 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN pos-neg<=-1 THEN 1 ELSE 0 END),0) AS decimal(5,1)) AS 弱気時複勝
FROM #s WHERE 期=N'検証' GROUP BY 印pt ORDER BY 印ポイント DESC;
