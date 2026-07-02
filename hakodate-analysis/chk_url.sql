SET NOCOUNT ON;
-- 今日各場の1Rの頭数比較(函館8頭が妥当か俯瞰)
SELECT 開催場所, レース番号, COUNT(*) 頭数 FROM レース情報 WHERE 開催日='2026-06-28' AND レース番号 IN(1,2,3) GROUP BY 開催場所,レース番号 ORDER BY 開催場所,レース番号;
PRINT '=== 函館1R 馬情報URL(netkeiba race_id手掛り) ===';
SELECT TOP 3 馬番,馬名,馬情報URL FROM レース情報 WHERE 開催日='2026-06-28' AND 開催場所='函館' AND レース番号=1 ORDER BY 馬番;
