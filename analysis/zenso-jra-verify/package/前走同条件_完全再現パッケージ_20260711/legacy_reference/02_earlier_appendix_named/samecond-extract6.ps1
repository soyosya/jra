# 同条件60%×中団勢: 抽出v3 — 前走/今走の全コーナー率(1-4角)+直近3走平均(1/3/4角)
# 目的: 中団勢の定義検証(コーナー軸×相対化方式)。3角=全場カバー100%近くで本命。
param([string]$From='2022-01-01',[string]$To='2026-07-09',[string]$Out='C:/keiba/analysis/samecond_mid_base6.csv')
[Console]::OutputEncoding=[System.Text.Encoding]::UTF8
$ErrorActionPreference='Stop'
. 'C:\keiba\tools\keiba-common.ps1'
$cn=New-Object System.Data.SqlClient.SqlConnection (Get-KeibaConnString); $cn.Open()
function Q([string]$sql,[hashtable]$p=@{}){ $c=$cn.CreateCommand(); $c.CommandTimeout=3600; $c.CommandText=$sql; foreach($k in $p.Keys){[void]$c.Parameters.AddWithValue($k,$p[$k])}; $dt=New-Object System.Data.DataTable; (New-Object System.Data.SqlClient.SqlDataAdapter $c).Fill($dt)|Out-Null; ,$dt }

Write-Host "[1/2] SQL抽出(20セル×全コーナー)..."
$sql=@"
SET NOCOUNT ON;
IF OBJECT_ID('tempdb..#cell') IS NOT NULL DROP TABLE #cell;
CREATE TABLE #cell(v nvarchar(10), d int);
INSERT INTO #cell VALUES
 (N'園田',1400),(N'佐賀',1400),(N'笠松',1400),(N'名古屋',1500),(N'名古屋',1400),(N'金沢',1400),(N'金沢',1500),
 (N'高知',1300),(N'高知',1400),(N'高知',1600),(N'水沢',1400),(N'大井',1200),(N'大井',1600),(N'門別',1000),(N'門別',1200),
 (N'船橋',1200),(N'浦和',1400),(N'川崎',1400),(N'盛岡',1400),(N'佐賀',1300);

IF OBJECT_ID('tempdb..#cur') IS NOT NULL DROP TABLE #cur;
SELECT r.開催日, r.開催場所, r.レース番号, r.馬番, r.馬名, r.着順, r.血統登録番号 rid,
       r.一コーナー tc1, r.二コーナー tc2, r.三コーナー tc3, r.四コーナー tc4,
       ri.距離, ri.騎手 tj, k.指数, k.指数順位,
       COUNT(*) OVER(PARTITION BY r.開催日,r.開催場所,r.レース番号) tou
INTO #cur
FROM dbo.競走結果 r
JOIN (SELECT DISTINCT 開催日,開催場所,レース番号,馬番,距離,騎手 FROM dbo.レース情報) ri
  ON ri.開催日=r.開催日 AND ri.開催場所=r.開催場所 AND ri.レース番号=r.レース番号 AND ri.馬番=r.馬番
JOIN #cell ce ON ce.v=r.開催場所 AND ce.d=ri.距離
LEFT JOIN (SELECT 開催日,開催場所,レース番号,馬番,指数,指数順位,
                  ROW_NUMBER() OVER(PARTITION BY 開催日,開催場所,レース番号,馬番 ORDER BY 取得日時 DESC) sn
           FROM dbo.コンピ指数) k
  ON k.開催日=r.開催日 AND k.開催場所=r.開催場所 AND k.レース番号=r.レース番号 AND k.馬番=r.馬番 AND k.sn=1
WHERE r.開催日 BETWEEN @f AND @t AND r.着順>0;

-- 直近3走(平地・ID残差・コーナー率つき)
IF OBJECT_ID('tempdb..#p3') IS NOT NULL DROP TABLE #p3;
SELECT * INTO #p3 FROM (
  SELECT DISTINCT c.開催日 td, c.開催場所 tv, c.レース番号 tr, c.馬番 tu,
         v.開催日 pd, v.開催場所 pv, v.レース番号 pr, v.距離 pdist,
         v.着順 pf, v.走破時計 pt, v.上り3F pa, v.一着馬着差タイム pm, v.頭数 ptou, v.騎手 pj,
         CASE WHEN v.頭数>1 AND v.一コーナー>0 THEN (v.一コーナー-1.0)/(v.頭数-1.0) END pr1,
         CASE WHEN v.頭数>1 AND v.二コーナー>0 THEN (v.二コーナー-1.0)/(v.頭数-1.0) END pr2,
         CASE WHEN v.頭数>1 AND v.三コーナー>0 THEN (v.三コーナー-1.0)/(v.頭数-1.0) END pr3,
         CASE WHEN v.頭数>1 AND v.四コーナー>0 THEN (v.四コーナー-1.0)/(v.頭数-1.0) END pr4,
         ROW_NUMBER() OVER(PARTITION BY c.開催日,c.開催場所,c.レース番号,c.馬番 ORDER BY v.開催日 DESC, v.レース番号 DESC) rn
  FROM #cur c
  JOIN dbo.vw_競走結果統合 v
    ON v.馬名=c.馬名 AND v.開催日<c.開催日 AND v.着順>0 AND v.開催場所<>N'帯広ば'
   AND (c.rid IS NULL OR v.血統登録番号 IS NULL OR v.血統登録番号=c.rid)
) x WHERE rn<=3;

IF OBJECT_ID('tempdb..#p') IS NOT NULL DROP TABLE #p;
SELECT * INTO #p FROM #p3 WHERE rn=1;
IF OBJECT_ID('tempdb..#a3') IS NOT NULL DROP TABLE #a3;
SELECT td,tv,tr,tu, AVG(pr1) a1_3, AVG(pr3) a3_3, AVG(pr4) a4_3, COUNT(*) n3,
  MAX(CASE WHEN rn=2 THEN pr3 END) r3_2, MAX(CASE WHEN rn=3 THEN pr3 END) r3_3,
  MAX(CASE WHEN rn=2 THEN pr4 END) r4_2, MAX(CASE WHEN rn=3 THEN pr4 END) r4_3,
  MAX(CASE WHEN rn=2 THEN CASE WHEN ptou>1 THEN (pf-1.0)/(ptou-1.0) END END) fr_2,
  MAX(CASE WHEN rn=3 THEN CASE WHEN ptou>1 THEN (pf-1.0)/(ptou-1.0) END END) fr_3
INTO #a3 FROM #p3 GROUP BY td,tv,tr,tu;

SELECT c.開催日,c.開催場所,c.レース番号,c.馬番,c.着順,c.距離,c.tou,c.指数,c.指数順位,
  CASE WHEN c.tou>1 AND c.tc1>0 THEN (c.tc1-1.0)/(c.tou-1.0) END t1,
  CASE WHEN c.tou>1 AND c.tc3>0 THEN (c.tc3-1.0)/(c.tou-1.0) END t3,
  CASE WHEN c.tou>1 AND c.tc4>0 THEN (c.tc4-1.0)/(c.tou-1.0) END t4,
  c.tj 今走騎手, p.pj 前走騎手,
  p.pd 前走日, p.pv 前走場, p.pr 前走R, p.pdist 前走距離, p.pf 前走着順,
  p.pt 前走時計, p.pa 前走上り, p.pm 前走着差, p.ptou 前走頭数,
  p.pr1 p1r, p.pr2 p2r, p.pr3 p3r, p.pr4 p4r,
  a.a1_3, a.a3_3, a.a4_3, a.n3, a.r3_2, a.r3_3, a.r4_2, a.r4_3, a.fr_2, a.fr_3,
  CASE WHEN p.pv=c.開催場所 AND p.pdist=c.距離 THEN 1 ELSE 0 END same,
  py1.金額 tanPay, py2.金額 fukuPay
FROM #cur c
LEFT JOIN #p p ON p.td=c.開催日 AND p.tv=c.開催場所 AND p.tr=c.レース番号 AND p.tu=c.馬番
LEFT JOIN #a3 a ON a.td=c.開催日 AND a.tv=c.開催場所 AND a.tr=c.レース番号 AND a.tu=c.馬番
LEFT JOIN dbo.払戻金 py1 ON py1.開催場所=c.開催場所 AND py1.開催日=c.開催日 AND py1.レース番号=c.レース番号 AND py1.馬券=N'単勝' AND py1.組番=CAST(c.馬番 AS nvarchar(3))
LEFT JOIN dbo.払戻金 py2 ON py2.開催場所=c.開催場所 AND py2.開催日=c.開催日 AND py2.レース番号=c.レース番号 AND py2.馬券=N'複勝' AND py2.組番=CAST(c.馬番 AS nvarchar(3))
ORDER BY c.開催日,c.開催場所,c.レース番号,c.馬番
"@
$dt=Q $sql @{'@f'=$From;'@t'=$To}
$cn.Close()
Write-Host ("  {0}行" -f $dt.Rows.Count)

Write-Host "[2/2] CSV書き出し -> $Out"
$sw=New-Object System.IO.StreamWriter($Out,$false,[System.Text.Encoding]::UTF8)
$sw.WriteLine('開催日,開催場所,レース番号,馬番,着順,距離,頭数,指数,指数順位,t1,t3,t4,今走騎手,前走騎手,前走日,前走場,前走R,前走距離,前走着順,前走時計,前走上り,前走着差,前走頭数,p1r,p2r,p3r,p4r,a1_3,a3_3,a4_3,n3,r3_2,r3_3,r4_2,r4_3,fr_2,fr_3,same,tanPay,fukuPay')
function V($x,$fmt=''){ if($x -is [DBNull] -or $null -eq $x){ '' } elseif($fmt -eq 'd'){ ([datetime]$x).ToString('yyyy-MM-dd') } elseif($fmt -eq 'r4'){ [math]::Round([double]$x,4) } else { $x } }
foreach($r in $dt.Rows){
  $vals=@(
    ([datetime]$r.開催日).ToString('yyyy-MM-dd'), $r.開催場所, [int]$r.レース番号, [int]$r.馬番, [int]$r.着順,
    [int]$r.距離, [int]$r.tou, (V $r.指数), (V $r.指数順位),
    (V $r.t1 'r4'), (V $r.t3 'r4'), (V $r.t4 'r4'),
    (V $r.今走騎手), (V $r.前走騎手),
    (V $r.前走日 'd'), (V $r.前走場), (V $r.前走R), (V $r.前走距離), (V $r.前走着順),
    (V $r.前走時計 'r4'), (V $r.前走上り 'r4'), (V $r.前走着差 'r4'), (V $r.前走頭数),
    (V $r.p1r 'r4'), (V $r.p2r 'r4'), (V $r.p3r 'r4'), (V $r.p4r 'r4'),
    (V $r.a1_3 'r4'), (V $r.a3_3 'r4'), (V $r.a4_3 'r4'), (V $r.n3),
    (V $r.r3_2 'r4'), (V $r.r3_3 'r4'), (V $r.r4_2 'r4'), (V $r.r4_3 'r4'), (V $r.fr_2 'r4'), (V $r.fr_3 'r4'),
    [int]$r.same,
    $(if($r.tanPay -is [DBNull]){0}else{[int]$r.tanPay}), $(if($r.fukuPay -is [DBNull]){0}else{[int]$r.fukuPay})
  )
  $sw.WriteLine(($vals -join ','))
}
$sw.Close()
Write-Host "DONE"
