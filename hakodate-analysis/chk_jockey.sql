SET NOCOUNT ON;
-- 今日各場 1R の騎手列の充足
SELECT 開催場所, レース番号, 馬番, 馬名, ISNULL(NULLIF(騎手,N''),N'(空)') 騎手
FROM レース情報 WHERE 開催日='2026-06-28' AND レース番号=1 ORDER BY 開催場所,馬番;
PRINT '=== 騎手列の全体充足(今日) ===';
SELECT 開催場所, COUNT(*) 出走, SUM(CASE WHEN 騎手 IS NULL OR 騎手=N'' THEN 1 ELSE 0 END) 騎手空
FROM レース情報 WHERE 開催日='2026-06-28' GROUP BY 開催場所;
