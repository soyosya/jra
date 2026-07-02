SELECT YEAR(開催日) yy, COUNT(1) レース情報行, COUNT(DISTINCT CONCAT(開催日,'-',レース番号)) R
FROM レース情報 WHERE 開催場所=N'東京' AND 着順>0
GROUP BY YEAR(開催日) ORDER BY yy;
