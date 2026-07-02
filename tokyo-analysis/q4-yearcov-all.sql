SELECT YEAR(開催日) yy, COUNT(DISTINCT 開催場所) 場数, COUNT(DISTINCT CONCAT(開催場所,開催日,レース番号)) R, COUNT(1) 出走
FROM レース情報 WHERE 着順>0 GROUP BY YEAR(開催日) ORDER BY yy;
SELECT N'コンピ_年別' k, YEAR(開催日) yy, COUNT(1) n FROM コンピ指数 GROUP BY YEAR(開催日) ORDER BY yy;
