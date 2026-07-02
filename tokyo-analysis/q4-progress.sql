SELECT N'レース情報2025_出走' k, COUNT(1) n, MIN(開催日) 最古, MAX(開催日) 最新
FROM レース情報 WHERE YEAR(開催日)=2025 AND 着順>0
UNION ALL
SELECT N'競走結果2025_行', COUNT(1), MIN(開催日), MAX(開催日) FROM 競走結果 WHERE YEAR(開催日)=2025 AND 着順>0
UNION ALL
SELECT N'リアルタイムオッズ2025_行', COUNT(1), MIN(開催日), MAX(開催日) FROM リアルタイムオッズ WHERE YEAR(開催日)=2025;
