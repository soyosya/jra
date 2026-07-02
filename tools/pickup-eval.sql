-- ピックアップ各カテゴリの有用性検証。結果(競走結果)が蓄積された開催で実行する。
-- 着順は 競走結果 を (開催日,馬名) で結合(将来 umacd 結合に切替可)。
SET NOCOUNT ON;
DECLARE @from date = '2000-01-01';   -- 評価開始日(必要に応じ変更)

-- ① カテゴリ別の今走成績(複勝率/単勝回収はオッズが要るため複勝率中心)
SELECT p.カテゴリ,
  頭数      = COUNT(*),
  結果あり  = SUM(CASE WHEN k.着順 IS NOT NULL THEN 1 ELSE 0 END),
  勝率      = CAST(100.0*SUM(CASE WHEN k.着順=1 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN k.着順 IS NOT NULL THEN 1 ELSE 0 END),0) AS decimal(5,1)),
  複勝率    = CAST(100.0*SUM(CASE WHEN k.着順<=3 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN k.着順 IS NOT NULL THEN 1 ELSE 0 END),0) AS decimal(5,1))
FROM ピックアップ p
OUTER APPLY (SELECT TOP 1 着順 FROM 競走結果 k WHERE k.開催日=p.開催日 AND k.馬名=p.馬名) k
WHERE p.開催日>=@from
GROUP BY p.カテゴリ
ORDER BY p.カテゴリ;

-- ② ★ユーザ仮説: 自己ベストの馬を「前走着順」で層別 → 今走複勝率
--    前走馬券圏内(≤3)で今走自己ベスト = 好調維持か?
SELECT 前走 = CASE WHEN pr.着順 IS NULL THEN N'前走不明'
                   WHEN pr.着順<=3 THEN N'前走馬券圏(≤3)'
                   WHEN pr.着順<=5 THEN N'前走4-5着'
                   ELSE N'前走6着以下' END,
  頭数   = COUNT(*),
  今走勝率   = CAST(100.0*SUM(CASE WHEN k.着順=1 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN k.着順 IS NOT NULL THEN 1 ELSE 0 END),0) AS decimal(5,1)),
  今走複勝率 = CAST(100.0*SUM(CASE WHEN k.着順<=3 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN k.着順 IS NOT NULL THEN 1 ELSE 0 END),0) AS decimal(5,1))
FROM ピックアップ p
OUTER APPLY (SELECT TOP 1 着順 FROM 競走結果 pr WHERE pr.馬名=p.馬名 AND pr.開催日<p.開催日 ORDER BY pr.開催日 DESC) pr
OUTER APPLY (SELECT TOP 1 着順 FROM 競走結果 k  WHERE k.開催日=p.開催日 AND k.馬名=p.馬名) k
WHERE p.カテゴリ=N'自己ベスト' AND p.開催日>=@from
GROUP BY CASE WHEN pr.着順 IS NULL THEN N'前走不明'
              WHEN pr.着順<=3 THEN N'前走馬券圏(≤3)'
              WHEN pr.着順<=5 THEN N'前走4-5着'
              ELSE N'前走6着以下' END
ORDER BY 1;

-- ③ さらに前走の厩舎コメント(danwa)を絡める拡張余地:
--    p.umacd = 厩舎の話.umacd で前走コメントを引ける(別途)。
