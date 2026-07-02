SET NOCOUNT ON;
SELECT TOP 1 距離,コース種別,条件,馬場,CONVERT(varchar(5),発走時刻,108) 発走 FROM レース情報 WHERE 開催日='2026-06-28' AND 開催場所='函館' AND レース番号=12;
PRINT '=== 12R コンピ+オッズ ===';
SELECT r.馬番,r.馬名,r.騎手,c.指数 指,c.指数順位 順,o.単勝オッズ 単,o.人気
FROM レース情報 r
LEFT JOIN コンピ指数 c ON c.開催場所=r.開催場所 AND c.開催日=r.開催日 AND c.レース番号=r.レース番号 AND c.馬番=r.馬番
LEFT JOIN リアルタイムオッズ o ON o.開催場所=r.開催場所 AND o.開催日=r.開催日 AND o.レース番号=r.レース番号 AND o.馬番=r.馬番
WHERE r.開催日='2026-06-28' AND r.開催場所='函館' AND r.レース番号=12 ORDER BY c.指数順位;
PRINT '=== 厩舎の話 ===';
SELECT 馬番,印,LEFT(コメント,40) コメント FROM 厩舎の話 WHERE 開催日='2026-06-28' AND 開催場所='函館' AND レース番号=12 ORDER BY 馬番;
PRINT '=== 調教 ===';
SELECT 馬番,矢印,LEFT(追い切り短評,26) 追切 FROM 調教 WHERE 開催日='2026-06-28' AND 開催場所='函館' AND レース番号=12 ORDER BY 馬番;
