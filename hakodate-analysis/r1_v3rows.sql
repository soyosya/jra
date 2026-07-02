SET NOCOUNT ON;
PRINT '=== 厩舎の話(函館1R) ===';
SELECT 馬番,馬名,印,調教師,LEFT(コメント,60) コメント
FROM 厩舎の話 WHERE 開催日='2026-06-28' AND 開催場所='函館' AND レース番号=1 ORDER BY 馬番;
PRINT '=== 調教(函館1R) ===';
SELECT 馬番,馬名,矢印,LEFT(追い切り短評,50) 追切
FROM 調教 WHERE 開催日='2026-06-28' AND 開催場所='函館' AND レース番号=1 ORDER BY 馬番;
