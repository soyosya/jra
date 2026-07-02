-- 厩舎の話 深掘り: 語句別の効き・書きっぷり(長さ/印/文数)・強気でも出ない厩舎(中央競馬DB)。
-- 着順=競走結果、単勝オッズ=リアルタイムオッズ、調教師=レース情報。期間は @from..@to。
SET NOCOUNT ON;
DECLARE @from date = '2023-01-01', @to date = '2023-12-31';

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
SELECT d.開催日,d.開催場所,d.レース番号,d.馬番,d.コメント,d.印, r.調教師,r.調教師所属, k.着順, o.単勝オッズ,o.人気,
  (SELECT COUNT(*) FROM @pos p WHERE d.コメント LIKE N'%'+p.kw+N'%') AS pos,
  (SELECT COUNT(*) FROM @neg n WHERE d.コメント LIKE N'%'+n.kw+N'%') AS neg,
  LEN(d.コメント) AS clen,
  (LEN(d.コメント) - LEN(REPLACE(d.コメント,N'。',N''))) AS sentn
INTO #s
FROM d
JOIN 競走結果 k ON k.開催日=d.開催日 AND k.開催場所=d.開催場所 AND k.レース番号=d.レース番号 AND k.馬番=d.馬番
LEFT JOIN レース情報 r ON r.開催日=d.開催日 AND r.開催場所=d.開催場所 AND r.レース番号=d.レース番号 AND r.馬番=d.馬番
LEFT JOIN リアルタイムオッズ o ON o.開催日=d.開催日 AND o.開催場所=d.開催場所 AND o.レース番号=d.レース番号 AND o.馬番=d.馬番
WHERE d.rn=1 AND d.コメント IS NOT NULL AND k.着順>0;
ALTER TABLE #s ADD class nvarchar(6);
UPDATE #s SET class = CASE WHEN pos-neg>=1 THEN N'強気' WHEN pos-neg<=-1 THEN N'弱気' ELSE N'中立' END;

PRINT '=== 0. ベースライン(全体) ===';
SELECT COUNT(*) AS n,
 CAST(100.0*SUM(CASE WHEN 着順=1 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) AS 勝率,
 CAST(100.0*SUM(CASE WHEN 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) AS 複勝率,
 CAST(100.0*SUM(CASE WHEN 着順=1 THEN ISNULL(単勝オッズ,0) ELSE 0 END)/COUNT(*) AS decimal(6,1)) AS 単回収 FROM #s;

PRINT '=== 1. 強気でも出ない厩舎(強気n>=20, 強気時複勝率の低い順) ===';
SELECT TOP 15 調教師, COUNT(*) AS 出走n,
 CAST(100.0*SUM(CASE WHEN 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) AS 複勝率全体,
 SUM(CASE WHEN class=N'強気' THEN 1 ELSE 0 END) AS 強気n,
 CAST(100.0*SUM(CASE WHEN class=N'強気' AND 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN class=N'強気' THEN 1 ELSE 0 END),0) AS decimal(5,1)) AS 強気時複勝率,
 CAST(100.0*SUM(CASE WHEN class=N'強気' AND 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN class=N'強気' THEN 1 ELSE 0 END),0)
    - 100.0*SUM(CASE WHEN 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) AS 差_強気_全体
FROM #s WHERE 調教師 IS NOT NULL AND 調教師<>''
GROUP BY 調教師 HAVING SUM(CASE WHEN class=N'強気' THEN 1 ELSE 0 END)>=20
ORDER BY 強気時複勝率 ASC;

PRINT '=== 2. 語句別の効き(出現n>=50, 複勝率の高い順 上位20) ===';
DECLARE @all TABLE(kw nvarchar(40), tag nvarchar(6));
INSERT INTO @all SELECT kw,N'強' FROM @pos; INSERT INTO @all SELECT kw,N'弱' FROM @neg;
INSERT INTO @all(kw,tag) VALUES
 (N'仕上がり',N'状'),(N'上積み',N'状'),(N'良化',N'状'),(N'デキ',N'状'),(N'順調',N'状'),(N'動きは',N'状'),
 (N'一変',N'変'),(N'距離短縮',N'変'),(N'距離延長',N'変'),(N'血統',N'変'),(N'適性',N'変'),(N'コース替',N'変'),
 (N'休み明け',N'変'),(N'放牧',N'変'),(N'リフレッシュ',N'変'),(N'ブリンカー',N'変'),(N'成長',N'変'),(N'気性',N'変'),
 (N'前走',N'他'),(N'初',N'他'),(N'減量',N'他'),(N'乗り替',N'他'),(N'続戦',N'他'),(N'連闘',N'他'),(N'馬体',N'他'),(N'ソエ',N'弱'),(N'脚部不安',N'弱');
SELECT TOP 20 a.tag, a.kw, COUNT(*) AS 出現n,
 CAST(100.0*SUM(CASE WHEN s.着順=1 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) AS 勝率,
 CAST(100.0*SUM(CASE WHEN s.着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) AS 複勝率,
 CAST(100.0*SUM(CASE WHEN s.着順=1 THEN ISNULL(s.単勝オッズ,0) ELSE 0 END)/COUNT(*) AS decimal(6,1)) AS 単回収,
 CAST(AVG(CAST(s.人気 AS float)) AS decimal(4,1)) AS 平均人気
FROM #s s JOIN @all a ON s.コメント LIKE N'%'+a.kw+N'%'
GROUP BY a.tag,a.kw HAVING COUNT(*)>=50 ORDER BY 複勝率 DESC;

PRINT '=== 3. 語句別の効き(複勝率の低い順 ワースト15) ===';
SELECT TOP 15 a.tag, a.kw, COUNT(*) AS 出現n,
 CAST(100.0*SUM(CASE WHEN s.着順=1 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) AS 勝率,
 CAST(100.0*SUM(CASE WHEN s.着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) AS 複勝率,
 CAST(100.0*SUM(CASE WHEN s.着順=1 THEN ISNULL(s.単勝オッズ,0) ELSE 0 END)/COUNT(*) AS decimal(6,1)) AS 単回収,
 CAST(AVG(CAST(s.人気 AS float)) AS decimal(4,1)) AS 平均人気
FROM #s s JOIN @all a ON s.コメント LIKE N'%'+a.kw+N'%'
GROUP BY a.tag,a.kw HAVING COUNT(*)>=50 ORDER BY 複勝率 ASC;

PRINT '=== 4. 書きっぷり: コメント文字数別 ===';
SELECT
 CASE WHEN clen<30 THEN N'1:〜29' WHEN clen<45 THEN N'2:30-44' WHEN clen<60 THEN N'3:45-59'
      WHEN clen<75 THEN N'4:60-74' ELSE N'5:75〜' END AS 文字数帯,
 COUNT(*) AS n,
 CAST(100.0*SUM(CASE WHEN 着順=1 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) AS 勝率,
 CAST(100.0*SUM(CASE WHEN 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) AS 複勝率,
 CAST(100.0*SUM(CASE WHEN 着順=1 THEN ISNULL(単勝オッズ,0) ELSE 0 END)/COUNT(*) AS decimal(6,1)) AS 単回収,
 CAST(AVG(CAST(人気 AS float)) AS decimal(4,1)) AS 平均人気
FROM #s GROUP BY CASE WHEN clen<30 THEN N'1:〜29' WHEN clen<45 THEN N'2:30-44' WHEN clen<60 THEN N'3:45-59'
      WHEN clen<75 THEN N'4:60-74' ELSE N'5:75〜' END ORDER BY 文字数帯;

PRINT '=== 5. 書きっぷり: コメント先頭の印別 ===';
SELECT ISNULL(印,N'(無)') AS 印, COUNT(*) AS n,
 CAST(100.0*SUM(CASE WHEN 着順=1 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) AS 勝率,
 CAST(100.0*SUM(CASE WHEN 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) AS 複勝率,
 CAST(100.0*SUM(CASE WHEN 着順=1 THEN ISNULL(単勝オッズ,0) ELSE 0 END)/COUNT(*) AS decimal(6,1)) AS 単回収,
 CAST(AVG(CAST(人気 AS float)) AS decimal(4,1)) AS 平均人気
FROM #s GROUP BY 印 HAVING COUNT(*)>=30 ORDER BY 複勝率 DESC;

PRINT '=== 6. 書きっぷり: 文の数(句点数)別 ===';
SELECT CASE WHEN sentn<=1 THEN N'1文以下' WHEN sentn=2 THEN N'2文' WHEN sentn=3 THEN N'3文' ELSE N'4文以上' END AS 文数,
 COUNT(*) AS n,
 CAST(100.0*SUM(CASE WHEN 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) AS 複勝率,
 CAST(100.0*SUM(CASE WHEN 着順=1 THEN ISNULL(単勝オッズ,0) ELSE 0 END)/COUNT(*) AS decimal(6,1)) AS 単回収
FROM #s GROUP BY CASE WHEN sentn<=1 THEN N'1文以下' WHEN sentn=2 THEN N'2文' WHEN sentn=3 THEN N'3文' ELSE N'4文以上' END
ORDER BY 文数;
