SET NOCOUNT ON;
SELECT TOP 8 騎手, LEN(騎手) 長 FROM レース情報 WHERE 開催場所='函館' AND 着順>0 AND 騎手 LIKE N'%岩田%' GROUP BY 騎手 ORDER BY 騎手;
SELECT TOP 5 騎手 FROM レース情報 WHERE 開催場所='函館' AND 着順>0 AND 騎手 LIKE N'%北村%' GROUP BY 騎手;
