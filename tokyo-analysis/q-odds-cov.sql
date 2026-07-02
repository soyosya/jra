SELECT YEAR(ri.開催日) yy,
 COUNT(1) 出走,
 SUM(CASE WHEN o.単勝オッズ>0 THEN 1 ELSE 0 END) RTオッズ有,
 SUM(CASE WHEN o.人気>0 THEN 1 ELSE 0 END) RT人気有
FROM レース情報 ri
LEFT JOIN リアルタイムオッズ o ON o.開催場所=ri.開催場所 AND o.開催日=ri.開催日 AND o.レース番号=ri.レース番号 AND o.馬番=ri.馬番
WHERE ri.開催場所=N'東京' AND ri.着順>0
GROUP BY YEAR(ri.開催日) ORDER BY yy;
