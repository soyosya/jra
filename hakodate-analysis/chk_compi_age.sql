SET NOCOUNT ON;
SELECT 開催場所,レース番号,COUNT(*) 頭数,MIN(取得日時) 取得,MAX(馬番) 最大馬番,MAX(取得元) 取得元
FROM コンピ指数 WHERE 開催日='2026-06-28' AND 開催場所='函館' AND レース番号 IN(1,2)
GROUP BY 開催場所,レース番号 ORDER BY レース番号;
