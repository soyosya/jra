SET NOCOUNT ON;
SELECT TOP 1 競走名,条件,距離,コース種別 FROM レース情報 WHERE 開催日='2026-06-28' AND 開催場所='福島' AND レース番号=4;
SELECT 馬番,馬名,騎手 FROM レース情報 WHERE 開催日='2026-06-28' AND 開催場所='福島' AND レース番号=4 AND 馬番 IN(13,14,15) ORDER BY 馬番;
