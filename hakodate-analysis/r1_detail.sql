SET NOCOUNT ON;
-- 今日 函館 1R 条件
SELECT TOP 1 開催日,レース番号,距離,コース種別,条件,競走名,天候,馬場 FROM レース情報 WHERE 開催日='2026-06-28' AND 開催場所='函館' AND レース番号=1;
PRINT '=== 1R 全頭 ===';
SELECT r.馬番,r.馬名,r.性別,r.馬齢,r.騎手,r.斤量,r.馬主,r.調教師,c.指数 コンピ,c.指数順位 順
FROM レース情報 r
LEFT JOIN コンピ指数 c ON c.開催場所=r.開催場所 AND c.開催日=r.開催日 AND c.レース番号=r.レース番号 AND c.馬番=r.馬番
WHERE r.開催日='2026-06-28' AND r.開催場所='函館' AND r.レース番号=1 ORDER BY r.馬番;
