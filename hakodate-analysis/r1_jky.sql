SET NOCOUNT ON;
-- 1R騎乗騎手の函館通算(2022-2026, 着順>0)
;WITH j AS (SELECT N'岩田 望来' n UNION ALL SELECT N'北村 友一' UNION ALL SELECT N'丹内 祐次'
  UNION ALL SELECT N'横山 琉人' UNION ALL SELECT N'佐々木 大輔' UNION ALL SELECT N'古川 奈穂'
  UNION ALL SELECT N'小林 美駒' UNION ALL SELECT N'河原田 菜々')
SELECT j.n 騎手,
  COUNT(r.着順) 騎乗, SUM(CASE WHEN r.着順=1 THEN 1 ELSE 0 END) 勝,
  CAST(100.0*SUM(CASE WHEN r.着順=1 THEN 1.0 ELSE 0 END)/NULLIF(COUNT(r.着順),0) AS decimal(4,1)) 勝率,
  CAST(100.0*SUM(CASE WHEN r.着順<=3 THEN 1.0 ELSE 0 END)/NULLIF(COUNT(r.着順),0) AS decimal(4,1)) 複勝率
FROM j LEFT JOIN レース情報 r ON r.騎手=j.n AND r.開催場所='函館' AND r.着順>0
GROUP BY j.n ORDER BY 複勝率 DESC;
