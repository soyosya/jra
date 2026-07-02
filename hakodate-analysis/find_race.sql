SET NOCOUNT ON;
-- 直近の出馬表(着順=0)がある日付×場
SELECT 開催日, 開催場所, COUNT(*) 出走, SUM(CASE WHEN 着順=0 THEN 1 ELSE 0 END) 未確定
FROM レース情報 WHERE 開催日>='2026-06-25' GROUP BY 開催日,開催場所 ORDER BY 開催日,開催場所;
PRINT '=== 横山武/岩田望 が乗る 1R を探索(6/27-6/28) ===';
SELECT 開催日,開催場所,レース番号,馬番,馬名,騎手,着順
FROM レース情報
WHERE 開催日>='2026-06-27' AND レース番号=1 AND (騎手 LIKE N'横山武%' OR 騎手 LIKE N'岩田望%')
ORDER BY 開催日,開催場所,馬番;
