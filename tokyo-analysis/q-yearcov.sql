SELECT YEAR(k.開催日) yy, COUNT(1) 競走結果行, COUNT(DISTINCT CONCAT(k.開催日,'-',k.レース番号)) R
FROM 競走結果 k WHERE k.開催場所=N'東京' AND k.着順>0
GROUP BY YEAR(k.開催日) ORDER BY yy;
