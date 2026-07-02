SET NOCOUNT ON;
PRINT '=== 横山武史 今日の騎乗(全場) ===';
SELECT 開催場所,レース番号,馬番,馬名,騎手 FROM レース情報 WHERE 開催日='2026-06-28' AND 騎手 LIKE N'横山%武%' ORDER BY 開催場所,レース番号;
PRINT '=== 岩田望来 今日の騎乗(全場) ===';
SELECT 開催場所,レース番号,馬番,馬名,騎手 FROM レース情報 WHERE 開催日='2026-06-28' AND 騎手 LIKE N'岩田%望%' ORDER BY 開催場所,レース番号;
PRINT '=== 横山(全員)今日 函館 ===';
SELECT DISTINCT 騎手 FROM レース情報 WHERE 開催日='2026-06-28' AND 開催場所='函館' AND 騎手 LIKE N'横山%';
