-- ★(前走・前々走とも上り3Fベスト3 かつ 1着との着差≤1.2秒, 前走365日内)フラグを 特徴量.agari_st へ反映。
SET NOCOUNT ON;
IF COL_LENGTH('dbo.特徴量','agari_st') IS NULL ALTER TABLE dbo.特徴量 ADD agari_st int NULL;
GO
UPDATE dbo.特徴量 SET agari_st=0;
GO
WITH base AS (
  SELECT k.開催場所 v,k.開催日 d,k.レース番号 r,k.馬番 no,k.馬名 h,k.一着馬着差タイム mgn,
    RANK() OVER(PARTITION BY k.開催場所,k.開催日,k.レース番号 ORDER BY k.上り3F ASC) agrank
  FROM 競走結果 k JOIN レース情報 ri ON ri.開催場所=k.開催場所 AND ri.開催日=k.開催日 AND ri.レース番号=k.レース番号 AND ri.馬番=k.馬番
  WHERE k.上り3F>0 AND k.着順>0 AND ri.コース種別 IN (N'芝',N'ダ')
),
seq AS (
  SELECT v,d,r,no,h,mgn,agrank,
    LAG(agrank,1) OVER(PARTITION BY h ORDER BY d,r) p1, LAG(agrank,2) OVER(PARTITION BY h ORDER BY d,r) p2,
    LAG(mgn,1) OVER(PARTITION BY h ORDER BY d,r) pm1, LAG(mgn,2) OVER(PARTITION BY h ORDER BY d,r) pm2,
    LAG(d,1) OVER(PARTITION BY h ORDER BY d,r) pd1
  FROM base
)
UPDATE f SET f.agari_st=1
FROM dbo.特徴量 f JOIN seq s ON s.v=f.開催場所 AND s.d=f.開催日 AND s.r=f.レース番号 AND s.no=f.馬番
WHERE s.p1<=3 AND s.p2<=3 AND s.pm1<=1.2 AND s.pm2<=1.2 AND DATEDIFF(day,s.pd1,s.d)<=365;
GO
SELECT agari_st, COUNT(*) n FROM dbo.特徴量 WHERE YEAR(開催日)=2023 GROUP BY agari_st ORDER BY agari_st;
