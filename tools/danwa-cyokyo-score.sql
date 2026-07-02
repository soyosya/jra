-- danwa(コメント)+調教(矢印/追い切り短評)+文脈(コース替/距離変化)を統合した総合スコアV3 と検証(2023, 前半学習/後半検証)。
-- V2=danwa単独 と比較し、調教・文脈を足した効果を held-out で確認。着順=競走結果、矢印/追切=調教、距離/コース=レース情報、オッズ=リアルタイムオッズ。
SET NOCOUNT ON;
DECLARE @lo date='2022-01-01', @cf date='2023-01-01', @ct date='2023-12-31', @split date='2023-07-01';
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
  (SELECT COUNT(*) FROM @pos p WHERE d.コメント LIKE N'%'+p.kw+N'%') AS pos,
  (SELECT COUNT(*) FROM @neg n WHERE d.コメント LIKE N'%'+n.kw+N'%') AS neg, LEN(d.コメント) clen,
  k.着順,o.単勝オッズ,o.人気, r.距離, r.コース種別, cy.矢印, cy.追い切り短評 AS tanpyo,
  CASE d.印 WHEN N'◎' THEN 3 WHEN N'▲' THEN 1 WHEN N'△' THEN -3 WHEN N'注' THEN -1 ELSE 0 END AS 印pt
INTO #c FROM d
LEFT JOIN 競走結果 k ON k.開催日=d.開催日 AND k.開催場所=d.開催場所 AND k.レース番号=d.レース番号 AND k.馬番=d.馬番
LEFT JOIN リアルタイムオッズ o ON o.開催日=d.開催日 AND o.開催場所=d.開催場所 AND o.レース番号=d.レース番号 AND o.馬番=d.馬番
LEFT JOIN レース情報 r ON r.開催日=d.開催日 AND r.開催場所=d.開催場所 AND r.レース番号=d.レース番号 AND r.馬番=d.馬番
LEFT JOIN 調教 cy ON cy.開催日=d.開催日 AND cy.開催場所=d.開催場所 AND cy.レース番号=d.レース番号 AND cy.馬番=d.馬番
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
WHERE c.開催日 BETWEEN @cf AND @ct AND c.着順>0;

ALTER TABLE #r ADD 追切class nvarchar(2), v2 int, v3 int, 消し bit;
UPDATE #r SET 追切class = CASE
  WHEN tanpyo LIKE N'%軽快%' OR tanpyo LIKE N'%力強い%' OR tanpyo LIKE N'%好調%' OR tanpyo LIKE N'%手応え十分%' OR tanpyo LIKE N'%シャープ%' OR tanpyo LIKE N'%活気%' OR tanpyo LIKE N'%上昇気配%' OR tanpyo LIKE N'%ハツラツ%' OR tanpyo LIKE N'%好気配%' OR tanpyo LIKE N'%抜群%' OR tanpyo LIKE N'%伸び脚%' THEN N'好'
  WHEN tanpyo LIKE N'%欠け%' OR tanpyo LIKE N'%ひと息%' OR tanpyo LIKE N'%平凡%' OR tanpyo LIKE N'%物足%' OR tanpyo LIKE N'%変わり身無%' OR tanpyo LIKE N'%軽め%' OR tanpyo LIKE N'%地味%' THEN N'凡' ELSE N'中' END;

UPDATE #r SET v2 = 印pt + (pos-neg) - (CASE WHEN clen<30 THEN 1 ELSE 0 END)
   + (CASE WHEN 印=N'◎' AND (前印<>N'◎' OR 前印 IS NULL) THEN 1 ELSE 0 END)
   - (CASE WHEN 前印=N'◎' AND 印=N'△' THEN 2 ELSE 0 END);
UPDATE #r SET v3 = v2
   + (CASE 矢印 WHEN N'↗' THEN 2 WHEN N'↑' THEN 2 WHEN N'↘' THEN -3 WHEN N'↓' THEN -3 ELSE 0 END)
   + (CASE 追切class WHEN N'好' THEN 1 WHEN N'凡' THEN -2 ELSE 0 END)
   + (CASE WHEN best_chaku=1 AND 印=N'◎' THEN 1 ELSE 0 END)
   - (CASE WHEN 前コース=N'ダ' AND コース種別=N'芝' THEN 2 ELSE 0 END)
   - (CASE WHEN 距離-前距離>=200 THEN 1 ELSE 0 END);
UPDATE #r SET 消し = CASE WHEN 印=N'△' OR 矢印 IN(N'↘',N'↓')
   OR (追切class=N'凡' AND (pos-neg)<=-1)
   OR (前コース=N'ダ' AND コース種別=N'芝')
   OR (best_chaku>=6 AND (pos-neg)<=-1) THEN 1 ELSE 0 END;

PRINT '=== A. V2(danwa単独) スコア帯別 複勝率(検証=後半) ===';
SELECT CASE WHEN v2<=-2 THEN N'a:〜-2' WHEN v2<=0 THEN N'b:-1〜0' WHEN v2<=2 THEN N'c:1-2' WHEN v2<=4 THEN N'd:3-4' ELSE N'e:5〜' END 帯,
 COUNT(*) n, CAST(100.0*SUM(CASE WHEN 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) 複勝率,
 CAST(100.0*SUM(CASE WHEN 着順=1 THEN ISNULL(単勝オッズ,0) ELSE 0 END)/COUNT(*) AS decimal(6,1)) 単回収
FROM #r WHERE 開催日>=@split GROUP BY CASE WHEN v2<=-2 THEN N'a:〜-2' WHEN v2<=0 THEN N'b:-1〜0' WHEN v2<=2 THEN N'c:1-2' WHEN v2<=4 THEN N'd:3-4' ELSE N'e:5〜' END ORDER BY 帯;

PRINT '=== B. V3(danwa+調教+文脈) スコア帯別 複勝率(検証=後半) ===';
SELECT CASE WHEN v3<=-2 THEN N'a:〜-2' WHEN v3<=0 THEN N'b:-1〜0' WHEN v3<=2 THEN N'c:1-2' WHEN v3<=4 THEN N'd:3-4' WHEN v3<=6 THEN N'e:5-6' ELSE N'f:7〜' END 帯,
 COUNT(*) n, CAST(100.0*SUM(CASE WHEN 着順=1 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) 勝率,
 CAST(100.0*SUM(CASE WHEN 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) 複勝率,
 CAST(100.0*SUM(CASE WHEN 着順=1 THEN ISNULL(単勝オッズ,0) ELSE 0 END)/COUNT(*) AS decimal(6,1)) 単回収,
 CAST(AVG(CAST(人気 AS float)) AS decimal(4,1)) 平均人気
FROM #r WHERE 開催日>=@split GROUP BY CASE WHEN v3<=-2 THEN N'a:〜-2' WHEN v3<=0 THEN N'b:-1〜0' WHEN v3<=2 THEN N'c:1-2' WHEN v3<=4 THEN N'd:3-4' WHEN v3<=6 THEN N'e:5-6' ELSE N'f:7〜' END ORDER BY 帯;

PRINT '=== C. 消しフラグ 効果(検証) ===';
SELECT CASE 消し WHEN 1 THEN N'消し該当' ELSE N'非該当' END フラグ, COUNT(*) n,
 CAST(100.0*SUM(CASE WHEN 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/COUNT(*) AS decimal(5,1)) 複勝率,
 CAST(100.0*SUM(CASE WHEN 着順=1 THEN ISNULL(単勝オッズ,0) ELSE 0 END)/COUNT(*) AS decimal(6,1)) 単回収,
 SUM(CASE WHEN 人気 BETWEEN 1 AND 5 THEN 1 ELSE 0 END) 人気1_5n,
 CAST(100.0*SUM(CASE WHEN 人気 BETWEEN 1 AND 5 AND 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN 人気 BETWEEN 1 AND 5 THEN 1 ELSE 0 END),0) AS decimal(5,1)) 人気1_5複勝率
FROM #r WHERE 開催日>=@split GROUP BY 消し;
