-- ①印昇格/降格(前走比)を総合スコアに統合して再検証 + ②過去5走の最高成績レースのコメント vs 今走コメント比較。
-- umacdで時系列化。今走=2023(結果あり)。過去5走は結果のある回のみ対象。着順=競走結果、オッズ=リアルタイムオッズ。
SET NOCOUNT ON;
DECLARE @lo date='2022-01-01', @cur_from date='2023-01-01', @cur_to date='2023-12-31', @split date='2023-07-01';

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
  SELECT umacd, 開催日, 開催場所, レース番号, 馬番, 印, コメント,
    ROW_NUMBER() OVER(PARTITION BY 開催日,開催場所,レース番号,馬番 ORDER BY 取得日時 DESC) rn
  FROM 厩舎の話 WHERE 開催日 BETWEEN @lo AND @cur_to AND umacd IS NOT NULL AND umacd<>'')
SELECT d.umacd, d.開催日, d.開催場所, d.レース番号, d.馬番, d.印,
  (SELECT COUNT(*) FROM @pos p WHERE d.コメント LIKE N'%'+p.kw+N'%')
  -(SELECT COUNT(*) FROM @neg n WHERE d.コメント LIKE N'%'+n.kw+N'%') AS score,
  LEN(d.コメント) AS clen, k.着順, o.単勝オッズ, o.人気,
  CASE d.印 WHEN N'◎' THEN 3 WHEN N'▲' THEN 1 WHEN N'△' THEN -3 WHEN N'注' THEN -1 ELSE 0 END AS 印pt
INTO #c FROM d
LEFT JOIN 競走結果 k ON k.開催日=d.開催日 AND k.開催場所=d.開催場所 AND k.レース番号=d.レース番号 AND k.馬番=d.馬番
LEFT JOIN リアルタイムオッズ o ON o.開催日=d.開催日 AND o.開催場所=d.開催場所 AND o.レース番号=d.レース番号 AND o.馬番=d.馬番
WHERE d.rn=1;

IF OBJECT_ID('tempdb..#r') IS NOT NULL DROP TABLE #r;
SELECT c.*,
  LAG(c.score) OVER(PARTITION BY c.umacd ORDER BY c.開催日,c.レース番号) AS 前score,
  LAG(c.印)   OVER(PARTITION BY c.umacd ORDER BY c.開催日,c.レース番号) AS 前印,
  b.best_chaku, b.best_score, b.best_mark, b.best_n
INTO #r
FROM #c c
OUTER APPLY (
  SELECT TOP 1 p.着順 AS best_chaku, p.score AS best_score, p.印 AS best_mark, COUNT(*) OVER() AS best_n
  FROM (SELECT TOP 5 p2.開催日,p2.着順,p2.score,p2.印 FROM #c p2
        WHERE p2.umacd=c.umacd AND p2.開催日<c.開催日 AND p2.着順>0 ORDER BY p2.開催日 DESC) p
  ORDER BY p.着順 ASC, p.開催日 DESC
) b
WHERE c.開催日 BETWEEN @cur_from AND @cur_to AND c.着順>0;

-- 総合スコア V1(従来) と V2(前走比トレンド項を追加)
ALTER TABLE #r ADD scoreV1 int, scoreV2 int;
UPDATE #r SET scoreV1 = 印pt + score - (CASE WHEN clen<30 THEN 1 ELSE 0 END);
UPDATE #r SET scoreV2 = 印pt + score - (CASE WHEN clen<30 THEN 1 ELSE 0 END)
   + (CASE WHEN 印=N'◎' AND (前印<>N'◎' OR 前印 IS NULL) THEN 1 ELSE 0 END)   -- ○→◎ 昇格
   + (CASE WHEN score - 前score >= 2 THEN 1 ELSE 0 END)                          -- 大改善
   - (CASE WHEN 前印=N'◎' AND 印=N'△' THEN 2 ELSE 0 END);                       -- 急降格

PRINT '=== A. 統合: V1 vs V2 スコア帯別 複勝率(検証=後半) ===';
SELECT N'V2' AS 版, CASE WHEN scoreV2<=-2 THEN N'a:〜-2' WHEN scoreV2<=0 THEN N'b:-1〜0' WHEN scoreV2=1 THEN N'c:1'
       WHEN scoreV2=2 THEN N'd:2' WHEN scoreV2=3 THEN N'e:3' ELSE N'f:4〜' END AS 帯,
  COUNT(*) n, CAST(100.0*SUM(CASE WHEN 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) 複勝率,
  CAST(100.0*SUM(CASE WHEN 着順=1 THEN ISNULL(単勝オッズ,0) ELSE 0 END)/COUNT(*) AS decimal(6,1)) 単回収
FROM #r WHERE 開催日>=@split GROUP BY CASE WHEN scoreV2<=-2 THEN N'a:〜-2' WHEN scoreV2<=0 THEN N'b:-1〜0' WHEN scoreV2=1 THEN N'c:1'
       WHEN scoreV2=2 THEN N'd:2' WHEN scoreV2=3 THEN N'e:3' ELSE N'f:4〜' END
ORDER BY 帯;

PRINT '=== B0. 母数(過去5走に結果のある回がある 2023今走) ===';
SELECT COUNT(*) AS n, SUM(CASE WHEN best_chaku=1 THEN 1 ELSE 0 END) AS うち過去5走に勝鞍 FROM #r WHERE best_chaku IS NOT NULL;

PRINT '=== B1. 今走コメント vs 過去5走最高成績時コメント の強気差(今score - best_score) ===';
SELECT CASE WHEN score-best_score<=-2 THEN N'a:好走時より弱い(-2以下)' WHEN score-best_score=-1 THEN N'b:やや弱い(-1)'
            WHEN score-best_score=0 THEN N'c:同等' WHEN score-best_score=1 THEN N'd:やや強い(+1)' ELSE N'e:強い(+2以上)' END AS 今走の気配,
 COUNT(*) n, CAST(100.0*SUM(CASE WHEN 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) 複勝率,
 CAST(100.0*SUM(CASE WHEN 着順=1 THEN ISNULL(単勝オッズ,0) ELSE 0 END)/COUNT(*) AS decimal(6,1)) 単回収,
 CAST(AVG(CAST(人気 AS float)) AS decimal(4,1)) 平均人気
FROM #r WHERE best_score IS NOT NULL
GROUP BY CASE WHEN score-best_score<=-2 THEN N'a:好走時より弱い(-2以下)' WHEN score-best_score=-1 THEN N'b:やや弱い(-1)'
            WHEN score-best_score=0 THEN N'c:同等' WHEN score-best_score=1 THEN N'd:やや強い(+1)' ELSE N'e:強い(+2以上)' END
ORDER BY 今走の気配;

PRINT '=== B2. 過去5走に勝鞍ありの馬(再現性): 勝った時の印 vs 今走の印 ===';
SELECT ISNULL(best_mark,N'(無)')+N'→'+ISNULL(印,N'(無)') AS 勝時印_今印, COUNT(*) n,
 CAST(100.0*SUM(CASE WHEN 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) 複勝率,
 CAST(100.0*SUM(CASE WHEN 着順=1 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) 勝率,
 CAST(100.0*SUM(CASE WHEN 着順=1 THEN ISNULL(単勝オッズ,0) ELSE 0 END)/COUNT(*) AS decimal(6,1)) 単回収,
 CAST(AVG(CAST(人気 AS float)) AS decimal(4,1)) 平均人気
FROM #r WHERE best_chaku=1
GROUP BY ISNULL(best_mark,N'(無)')+N'→'+ISNULL(印,N'(無)') HAVING COUNT(*)>=40 ORDER BY 複勝率 DESC;

PRINT '=== B3. 過去5走最高着順別 × 今走コメントclass ===';
SELECT CASE WHEN best_chaku=1 THEN N'1:過去5走に1着' WHEN best_chaku<=3 THEN N'2:最高2-3着' WHEN best_chaku<=5 THEN N'3:最高4-5着' ELSE N'4:最高6着以下' END AS 過去最高,
 CASE WHEN score>=1 THEN N'今強気' WHEN score<=-1 THEN N'今弱気' ELSE N'今中立' END AS 今class,
 COUNT(*) n, CAST(100.0*SUM(CASE WHEN 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) 複勝率,
 CAST(100.0*SUM(CASE WHEN 着順=1 THEN ISNULL(単勝オッズ,0) ELSE 0 END)/COUNT(*) AS decimal(6,1)) 単回収
FROM #r WHERE best_chaku IS NOT NULL
GROUP BY CASE WHEN best_chaku=1 THEN N'1:過去5走に1着' WHEN best_chaku<=3 THEN N'2:最高2-3着' WHEN best_chaku<=5 THEN N'3:最高4-5着' ELSE N'4:最高6着以下' END,
 CASE WHEN score>=1 THEN N'今強気' WHEN score<=-1 THEN N'今弱気' ELSE N'今中立' END
ORDER BY 過去最高, 今class;
