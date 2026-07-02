SELECT TOP 8 開催日, レース番号, 馬番, 単勝オッズ, 複勝オッズ, 複勝オッズ_MIN, 複勝オッズ_MAX, 人気
FROM リアルタイムオッズ WHERE 開催場所=N'東京' AND 単勝オッズ>0 ORDER BY 開催日 DESC, レース番号, 人気;
SELECT N'複勝MIN>0' k, COUNT(1) n FROM リアルタイムオッズ WHERE 開催場所=N'東京' AND 複勝オッズ_MIN>0
UNION ALL SELECT N'複勝オッズ>0', COUNT(1) FROM リアルタイムオッズ WHERE 開催場所=N'東京' AND 複勝オッズ>0;
