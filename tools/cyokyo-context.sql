-- 別角度分析(2023): ①調教の追い切り短評 語句別の効き ②コース替わり×コメント ③距離変化×コメント。
-- 着順=競走結果、追い切り短評/矢印=調教、距離/コース種別=レース情報、オッズ=リアルタイムオッズ。umacdで時系列化(前走コース/距離)。
SET NOCOUNT ON;
DECLARE @lo date='2022-01-01', @cf date='2023-01-01', @ct date='2023-12-31';
-- danwa強気語(コメントclass用・簡略)
DECLARE @pos TABLE(kw nvarchar(40)); INSERT INTO @pos(kw) VALUES
 (N'好勝負'),(N'力上位'),(N'勝ち負け'),(N'勝負'),(N'チャンス'),(N'何とか'),(N'勝てる'),(N'能力は高'),(N'地力'),(N'自信'),(N'楽しみ'),(N'いい状態'),(N'上向き'),(N'メドは立'),(N'通用'),(N'上位争'),(N'やれそう'),(N'相手次第'),(N'メンバーひとつ');
DECLARE @neg TABLE(kw nvarchar(40)); INSERT INTO @neg(kw) VALUES
 (N'使いな'),(N'使いつつ'),(N'変わり身'),(N'一変'),(N'でどこまで'),(N'もうひとつ'),(N'叩き'),(N'厳しい'),(N'物足'),(N'良化'),(N'様子'),(N'目標は'),(N'太め'),(N'不安'),(N'減量'),(N'難しい'),(N'こなせば'),(N'課題');

IF OBJECT_ID('tempdb..#c') IS NOT NULL DROP TABLE #c;
WITH d AS (
  SELECT umacd,開催日,開催場所,レース番号,馬番,印,コメント,
    ROW_NUMBER() OVER(PARTITION BY 開催日,開催場所,レース番号,馬番 ORDER BY 取得日時 DESC) rn
  FROM 厩舎の話 WHERE 開催日 BETWEEN @lo AND @ct AND umacd IS NOT NULL AND umacd<>'')
SELECT d.umacd,d.開催日,d.開催場所,d.レース番号,d.馬番,
  (SELECT COUNT(*) FROM @pos p WHERE d.コメント LIKE N'%'+p.kw+N'%')-(SELECT COUNT(*) FROM @neg n WHERE d.コメント LIKE N'%'+n.kw+N'%') AS score,
  k.着順,o.単勝オッズ,o.人気, r.距離, r.コース種別, cy.矢印, cy.追い切り短評 AS tanpyo
INTO #c FROM d
LEFT JOIN 競走結果 k ON k.開催日=d.開催日 AND k.開催場所=d.開催場所 AND k.レース番号=d.レース番号 AND k.馬番=d.馬番
LEFT JOIN リアルタイムオッズ o ON o.開催日=d.開催日 AND o.開催場所=d.開催場所 AND o.レース番号=d.レース番号 AND o.馬番=d.馬番
LEFT JOIN レース情報 r ON r.開催日=d.開催日 AND r.開催場所=d.開催場所 AND r.レース番号=d.レース番号 AND r.馬番=d.馬番
LEFT JOIN 調教 cy ON cy.開催日=d.開催日 AND cy.開催場所=d.開催場所 AND cy.レース番号=d.レース番号 AND cy.馬番=d.馬番
WHERE d.rn=1;

IF OBJECT_ID('tempdb..#r') IS NOT NULL DROP TABLE #r;
SELECT c.*,
  LAG(c.コース種別) OVER(PARTITION BY c.umacd ORDER BY c.開催日,c.レース番号) AS 前コース,
  LAG(c.距離) OVER(PARTITION BY c.umacd ORDER BY c.開催日,c.レース番号) AS 前距離
INTO #r FROM #c c WHERE c.開催日 BETWEEN @cf AND @ct AND c.着順>0;
ALTER TABLE #r ADD 今c nvarchar(2), コース替 nvarchar(8), 距離変化 nvarchar(8);
UPDATE #r SET 今c=CASE WHEN score>=1 THEN N'強' WHEN score<=-1 THEN N'弱' ELSE N'中' END,
 コース替=CASE WHEN 前コース IS NULL THEN N'不明' WHEN 前コース=N'芝' AND コース種別=N'ダ' THEN N'芝→ダ'
   WHEN 前コース=N'ダ' AND コース種別=N'芝' THEN N'ダ→芝' WHEN コース種別=N'芝' THEN N'芝→芝' WHEN コース種別=N'ダ' THEN N'ダ→ダ' ELSE N'他' END,
 距離変化=CASE WHEN 前距離 IS NULL OR 前距離=0 THEN N'不明' WHEN 距離-前距離<=-200 THEN N'短縮'
   WHEN 距離-前距離>=200 THEN N'延長' ELSE N'同等' END;

PRINT '=== A. 追い切り短評 語句別の効き(出現n>=200, 複勝率 上位/下位) ===';
DECLARE @tw TABLE(tag nvarchar(4), kw nvarchar(20));
INSERT INTO @tw VALUES
 (N'好',N'軽快'),(N'好',N'力強い'),(N'好',N'好調'),(N'好',N'キビキビ'),(N'好',N'好気配'),(N'好',N'スムーズ'),(N'好',N'素軽'),
 (N'好',N'活気'),(N'好',N'手応え十分'),(N'好',N'伸び脚'),(N'好',N'シャープ'),(N'好',N'余裕'),(N'好',N'デキ安定'),(N'好',N'上昇気配'),
 (N'好',N'ハツラツ'),(N'好',N'元気一杯'),(N'好',N'良好'),(N'好',N'確か'),(N'好',N'入念'),(N'好',N'終いの伸び'),(N'好',N'抜群'),(N'好',N'上々'),
 (N'凡',N'欠け'),(N'凡',N'ひと息'),(N'凡',N'平凡'),(N'凡',N'物足'),(N'凡',N'変わり身無'),(N'凡',N'軽め'),(N'凡',N'地味'),(N'凡',N'重い'),(N'凡',N'鈍'),
 (N'弱良',N'この一追いで良化'),(N'弱良',N'さほど良化'),(N'弱良',N'多少上向'),(N'中',N'まずまず'),(N'中',N'順調');
SELECT t.tag, t.kw, COUNT(*) 出現n,
 CAST(100.0*SUM(CASE WHEN s.着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) 複勝率,
 CAST(100.0*SUM(CASE WHEN s.着順=1 THEN ISNULL(s.単勝オッズ,0) ELSE 0 END)/COUNT(*) AS decimal(6,1)) 単回収,
 CAST(AVG(CAST(s.人気 AS float)) AS decimal(4,1)) 平均人気
FROM #r s JOIN @tw t ON s.tanpyo LIKE N'%'+t.kw+N'%'
GROUP BY t.tag,t.kw HAVING COUNT(*)>=200 ORDER BY 複勝率 DESC;

PRINT '=== B. 追い切り短評class × コメントclass(併用) ===';
SELECT CASE WHEN tanpyo LIKE N'%軽快%' OR tanpyo LIKE N'%力強い%' OR tanpyo LIKE N'%好調%' OR tanpyo LIKE N'%手応え十分%' OR tanpyo LIKE N'%シャープ%' OR tanpyo LIKE N'%活気%' OR tanpyo LIKE N'%上昇気配%' OR tanpyo LIKE N'%ハツラツ%' OR tanpyo LIKE N'%好気配%' OR tanpyo LIKE N'%抜群%' THEN N'好'
     WHEN tanpyo LIKE N'%欠け%' OR tanpyo LIKE N'%ひと息%' OR tanpyo LIKE N'%平凡%' OR tanpyo LIKE N'%物足%' OR tanpyo LIKE N'%変わり身無%' OR tanpyo LIKE N'%軽め%' OR tanpyo LIKE N'%地味%' THEN N'凡' ELSE N'中' END AS 追切,
 今c AS コメント, COUNT(*) n,
 CAST(100.0*SUM(CASE WHEN 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) 複勝率,
 CAST(100.0*SUM(CASE WHEN 着順=1 THEN ISNULL(単勝オッズ,0) ELSE 0 END)/COUNT(*) AS decimal(6,1)) 単回収
FROM #r WHERE tanpyo IS NOT NULL AND tanpyo<>''
GROUP BY CASE WHEN tanpyo LIKE N'%軽快%' OR tanpyo LIKE N'%力強い%' OR tanpyo LIKE N'%好調%' OR tanpyo LIKE N'%手応え十分%' OR tanpyo LIKE N'%シャープ%' OR tanpyo LIKE N'%活気%' OR tanpyo LIKE N'%上昇気配%' OR tanpyo LIKE N'%ハツラツ%' OR tanpyo LIKE N'%好気配%' OR tanpyo LIKE N'%抜群%' THEN N'好'
     WHEN tanpyo LIKE N'%欠け%' OR tanpyo LIKE N'%ひと息%' OR tanpyo LIKE N'%平凡%' OR tanpyo LIKE N'%物足%' OR tanpyo LIKE N'%変わり身無%' OR tanpyo LIKE N'%軽め%' OR tanpyo LIKE N'%地味%' THEN N'凡' ELSE N'中' END, 今c
ORDER BY 追切, 今c;

PRINT '=== C. コース替わり × コメントclass ===';
SELECT コース替, 今c AS コメント, COUNT(*) n,
 CAST(100.0*SUM(CASE WHEN 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) 複勝率,
 CAST(100.0*SUM(CASE WHEN 着順=1 THEN ISNULL(単勝オッズ,0) ELSE 0 END)/COUNT(*) AS decimal(6,1)) 単回収,
 CAST(AVG(CAST(人気 AS float)) AS decimal(4,1)) 平均人気
FROM #r WHERE コース替 IN(N'芝→ダ',N'ダ→芝',N'芝→芝',N'ダ→ダ') GROUP BY コース替,今c ORDER BY コース替,今c;

PRINT '=== D. 距離変化 × コメントclass ===';
SELECT 距離変化, 今c AS コメント, COUNT(*) n,
 CAST(100.0*SUM(CASE WHEN 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) 複勝率,
 CAST(100.0*SUM(CASE WHEN 着順=1 THEN ISNULL(単勝オッズ,0) ELSE 0 END)/COUNT(*) AS decimal(6,1)) 単回収
FROM #r WHERE 距離変化 IN(N'短縮',N'同等',N'延長') GROUP BY 距離変化,今c ORDER BY 距離変化,今c;
