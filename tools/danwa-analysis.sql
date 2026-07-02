-- 厩舎の話「強気コメント」と着順の関係分析(中央競馬DB)。
-- 強気/弱気は厩舎コメントの語句ヒット数の差でスコア化(透明・ヒューリスティック)。
-- 調教師/馬主は レース情報(netkeiba) から結合(コメント解析より確実)。着順=競走結果、単勝オッズ=リアルタイムオッズ。
-- 期間は結果取込済みの 2026-05-23〜06-14(8開催日)。※小標本=探索的。
SET NOCOUNT ON;

DECLARE @from date = '2026-05-23', @to date = '2026-06-14';

DECLARE @pos TABLE(kw nvarchar(40));
INSERT INTO @pos(kw) VALUES
 (N'力上位'),(N'力通用'),(N'崩れぬ'),(N'崩れない'),(N'距離合'),(N'好勝負'),(N'勝ち負け'),(N'勝負'),
 (N'能力は高'),(N'能力上位'),(N'態勢は整'),(N'態勢が整'),(N'上位争'),(N'いい状態'),(N'状態はいい'),
 (N'状態は良'),(N'状態いい'),(N'上向き'),(N'地力'),(N'成長して'),(N'メドは立'),(N'メドが立'),
 (N'やれそう'),(N'自信'),(N'通用'),(N'楽しみ'),(N'チャンス'),(N'勝ち切'),(N'勝機'),(N'万全'),
 (N'絶好'),(N'文句な'),(N'勝ちたい'),(N'勝てる'),(N'何とか'),(N'見直'),(N'順番');

DECLARE @neg TABLE(kw nvarchar(40));
INSERT INTO @neg(kw) VALUES
 (N'どうか'),(N'難しい'),(N'こなせば'),(N'でどこまで'),(N'相手次第'),(N'相手なり'),(N'展開ひとつ'),
 (N'メンバーひとつ'),(N'展開次第'),(N'立て直'),(N'叩いて'),(N'叩き'),(N'使いな'),(N'使いつつ'),
 (N'目標は次'),(N'目標は先'),(N'物足'),(N'様子を見'),(N'余裕を残'),(N'この相手で'),(N'厳しい'),
 (N'もうひとつ'),(N'もう一息'),(N'太め'),(N'攻め不足'),(N'不安'),(N'ひと叩'),(N'変わり身'),
 (N'二走ボケ'),(N'甘くな'),(N'課題'),(N'微妙'),(N'物見'),(N'大人になり'),(N'叩き台');

IF OBJECT_ID('tempdb..#s') IS NOT NULL DROP TABLE #s;
WITH d AS (
  SELECT *, ROW_NUMBER() OVER(PARTITION BY 開催日,開催場所,レース番号,馬番 ORDER BY 取得日時 DESC) rn
  FROM 厩舎の話 WHERE 開催日 BETWEEN @from AND @to)
SELECT
  d.開催日, d.開催場所, d.レース番号, d.馬番, d.コメント,
  r.調教師, r.調教師所属, r.馬主,
  k.着順,
  o.単勝オッズ, o.人気,
  (SELECT COUNT(*) FROM @pos p WHERE d.コメント LIKE N'%'+p.kw+N'%') AS pos,
  (SELECT COUNT(*) FROM @neg n WHERE d.コメント LIKE N'%'+n.kw+N'%') AS neg
INTO #s
FROM d
JOIN 競走結果 k ON k.開催日=d.開催日 AND k.開催場所=d.開催場所 AND k.レース番号=d.レース番号 AND k.馬番=d.馬番
LEFT JOIN レース情報 r ON r.開催日=d.開催日 AND r.開催場所=d.開催場所 AND r.レース番号=d.レース番号 AND r.馬番=d.馬番
LEFT JOIN リアルタイムオッズ o ON o.開催日=d.開催日 AND o.開催場所=d.開催場所 AND o.レース番号=d.レース番号 AND o.馬番=d.馬番
WHERE d.rn=1 AND d.コメント IS NOT NULL AND k.着順 > 0;

ALTER TABLE #s ADD class nvarchar(6);
UPDATE #s SET class = CASE WHEN pos-neg>=1 THEN N'強気' WHEN pos-neg<=-1 THEN N'弱気' ELSE N'中立' END;

PRINT '=== A. 全体: 強気度クラス別 着順成績 ===';
SELECT class AS クラス, COUNT(*) AS n,
  CAST(100.0*SUM(CASE WHEN 着順=1 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) AS 勝率,
  CAST(100.0*SUM(CASE WHEN 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) AS 複勝率,
  CAST(100.0*SUM(CASE WHEN 着順=1 THEN ISNULL(単勝オッズ,0) ELSE 0 END)/COUNT(*) AS decimal(6,1)) AS 単回収,
  CAST(AVG(CAST(人気 AS float)) AS decimal(4,1)) AS 平均人気
FROM #s GROUP BY class
ORDER BY CASE class WHEN N'強気' THEN 1 WHEN N'中立' THEN 2 ELSE 3 END;

PRINT '=== B. 調教師別(出走n>=15): 強気率と複勝率(強気→結果 / 強気でも出ず の判別) ===';
SELECT TOP 30 調教師, 調教師所属 AS 所属, COUNT(*) AS 出走n,
  CAST(100.0*SUM(CASE WHEN class=N'強気' THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) AS 強気率,
  CAST(100.0*SUM(CASE WHEN 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) AS 複勝率全体,
  SUM(CASE WHEN class=N'強気' THEN 1 ELSE 0 END) AS 強気n,
  CAST(100.0*SUM(CASE WHEN class=N'強気' AND 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN class=N'強気' THEN 1 ELSE 0 END),0) AS decimal(5,1)) AS 強気時複勝率,
  CAST(100.0*SUM(CASE WHEN class=N'強気' AND 着順=1 THEN ISNULL(単勝オッズ,0) ELSE 0 END)/NULLIF(SUM(CASE WHEN class=N'強気' THEN 1 ELSE 0 END),0) AS decimal(6,1)) AS 強気時単回収
FROM #s WHERE 調教師 IS NOT NULL AND 調教師<>''
GROUP BY 調教師, 調教師所属 HAVING COUNT(*)>=15
ORDER BY 強気時複勝率 DESC;

PRINT '=== C. 馬主別(出走n>=10): 強気率と複勝率 ===';
SELECT TOP 30 馬主, COUNT(*) AS 出走n,
  CAST(100.0*SUM(CASE WHEN class=N'強気' THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) AS 強気率,
  CAST(100.0*SUM(CASE WHEN 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) AS 複勝率全体,
  SUM(CASE WHEN class=N'強気' THEN 1 ELSE 0 END) AS 強気n,
  CAST(100.0*SUM(CASE WHEN class=N'強気' AND 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN class=N'強気' THEN 1 ELSE 0 END),0) AS decimal(5,1)) AS 強気時複勝率
FROM #s WHERE 馬主 IS NOT NULL AND 馬主<>''
GROUP BY 馬主 HAVING COUNT(*)>=10
ORDER BY 出走n DESC;

PRINT '=== 参考: 総数・単勝オッズ結合率 ===';
SELECT COUNT(*) AS 総頭数, SUM(CASE WHEN 単勝オッズ IS NOT NULL THEN 1 ELSE 0 END) AS オッズ有, SUM(CASE WHEN 調教師 IS NOT NULL AND 調教師<>'' THEN 1 ELSE 0 END) AS 調教師有 FROM #s;
