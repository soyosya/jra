IF OBJECT_ID('tempdb..#fld') IS NOT NULL DROP TABLE #fld;
SELECT 開催場所 v,開催日 dd,レース番号 rr,COUNT(*) fld INTO #fld FROM 競走結果 WHERE 着順>0 AND 四コーナー>0 GROUP BY 開催場所,開催日,レース番号;
-- R8の各馬で Compute-PrevStyle と同じTOP1クエリを一括実行(JOIN #fld)
SELECT e.馬名, x.pst
FROM (SELECT 馬名 FROM レース情報 WHERE 開催場所=N'東京' AND 開催日='2026-06-14' AND レース番号=8) e
OUTER APPLY (
  SELECT TOP 1 CASE WHEN k.四コーナー=1 THEN 1 WHEN CAST(k.四コーナー AS float)/f.fld<=0.33 THEN 2 WHEN CAST(k.四コーナー AS float)/f.fld<=0.66 THEN 3 ELSE 4 END pst
  FROM 競走結果 k JOIN #fld f ON f.v=k.開催場所 AND f.dd=k.開催日 AND f.rr=k.レース番号
  WHERE k.馬名=e.馬名 AND k.開催日<'2026-06-14' AND k.四コーナー>0 AND k.着順>0
  ORDER BY k.開催日 DESC,k.レース番号 DESC
) x;
