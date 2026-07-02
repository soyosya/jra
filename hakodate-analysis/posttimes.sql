SET NOCOUNT ON;
SELECT レース番号, CONVERT(varchar(5),発走時刻,108) 発走, COUNT(*) 頭数,
  MAX(CASE WHEN 着順>0 THEN 1 ELSE 0 END) 確定済
FROM レース情報 WHERE 開催日='2026-06-28' AND 開催場所='函館'
GROUP BY レース番号,発走時刻 ORDER BY レース番号;
