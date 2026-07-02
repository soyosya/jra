SELECT レース番号, MAX(コース種別) surf, MAX(距離) dist, MAX(条件) joken, COUNT(*) 頭数,
 SUM(CASE WHEN 馬名 IS NULL OR 馬名=N'' THEN 1 ELSE 0 END) 空名
FROM レース情報 WHERE 開催場所=N'東京' AND 開催日='2026-06-14' AND 着順>0 GROUP BY レース番号 ORDER BY レース番号;
