SET NOCOUNT ON;
SELECT 馬番,馬名,着順,騎手 FROM レース情報 WHERE 開催日='2026-06-28' AND 開催場所='函館' AND レース番号=1 AND 着順>0 ORDER BY 着順;
PRINT '=== 着順未確定なら出馬表のまま ===';
SELECT COUNT(*) 全, SUM(CASE WHEN 着順>0 THEN 1 ELSE 0 END) 確定 FROM レース情報 WHERE 開催日='2026-06-28' AND 開催場所='函館' AND レース番号=1;
