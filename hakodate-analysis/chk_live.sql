SET NOCOUNT ON;
PRINT '=== リアルタイムオッズ 函館1R 今日 ===';
SELECT COUNT(*) 頭数, MAX(馬番) 最大馬番, MAX(日時) 最終取得 FROM リアルタイムオッズ WHERE 開催日='2026-06-28' AND 開催場所='函館' AND レース番号=1;
SELECT 馬番,馬名,単勝オッズ,人気 FROM リアルタイムオッズ WHERE 開催日='2026-06-28' AND 開催場所='函館' AND レース番号=1 ORDER BY 馬番;
PRINT '=== レース情報 騎手取得元の手掛り: 1R 14/15番は存在する? ===';
SELECT 馬番,馬名,騎手,着順 FROM レース情報 WHERE 開催日='2026-06-28' AND 開催場所='函館' AND レース番号=1 AND 馬番 IN(14,15);
