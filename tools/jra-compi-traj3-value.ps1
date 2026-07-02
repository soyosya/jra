<#
.SYNOPSIS
  jra-compi-traj3の指数"値"版。今走順位bandを固定し、過去3走の指数値(平均/高指数回数/水準)が複勝率に効くか。
.DESCRIPTION
  各馬の今走順位i0(band用) + 過去3走指数値(v1,v2,v3を馬名で参照)。順位版(traj3=上位回数)と"値"版を比較。
  (A)band固定×過去3走平均指数値バケット→複勝率。(B)band固定×過去3走で高指数(≥75)回数→複勝率。(C)順位版との対比+年別。
#>
[CmdletBinding()]param([string]$From='2022-01-01',[string]$To='2026-12-31',[int]$HiThr=75)
$ErrorActionPreference='Stop'
$cs=(Get-Content (Join-Path $PSScriptRoot '..\共通\appsettings.json') -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
$conn=New-Object System.Data.SqlClient.SqlConnection($cs);$conn.Open()
function Q($s){$c=$conn.CreateCommand();$c.CommandText=$s;$c.CommandTimeout=600;[void]$c.Parameters.AddWithValue('@f',$From);[void]$c.Parameters.AddWithValue('@t',$To);$r=$c.ExecuteReader();$o=@();while($r.Read()){$row=[ordered]@{};for($i=0;$i -lt $r.FieldCount;$i++){$row[$r.GetName($i)]=$r.GetValue($i)};$o+=[pscustomobject]$row};$r.Close();$o}

# 今走順位i0(band) + 過去3走指数値v1/v2/v3(馬名,レース最新スナップ) + 着順 + 単勝払戻。3走そろう馬のみ。
$CTE=@"
cp AS (SELECT 開催日,開催場所,レース番号,馬番,馬名,指数順位 i0 FROM (SELECT *,ROW_NUMBER() OVER(PARTITION BY 開催日,開催場所,レース番号,馬番 ORDER BY 取得日時 DESC) rn FROM コンピ指数 WHERE 開催日 BETWEEN @f AND @t AND 指数順位 IS NOT NULL) z WHERE rn=1),
d AS (
 SELECT r.着順,r.開催日,c.i0,p.v1,p.v2,p.v3,(p.v1+p.v2+p.v3)/3.0 vavg,pay.金額 tan,
   CASE WHEN c.i0=1 THEN '1:1位' WHEN c.i0 BETWEEN 2 AND 3 THEN '2:2-3位' WHEN c.i0 BETWEEN 4 AND 6 THEN '3:4-6位' ELSE '4:7位↓' END band
 FROM cp c
 JOIN レース情報 r ON r.開催日=c.開催日 AND r.開催場所=c.開催場所 AND r.レース番号=c.レース番号 AND r.馬番=c.馬番 AND r.着順>0
 CROSS APPLY (SELECT MAX(CASE WHEN rk=1 THEN val END) v1,MAX(CASE WHEN rk=2 THEN val END) v2,MAX(CASE WHEN rk=3 THEN val END) v3
   FROM (SELECT CAST(z.指数 AS int) val,ROW_NUMBER() OVER(ORDER BY z.開催日 DESC,z.レース番号 DESC) rk
         FROM (SELECT *,ROW_NUMBER() OVER(PARTITION BY 開催日,開催場所,レース番号 ORDER BY 取得日時 DESC) rr FROM コンピ指数 WHERE 馬名=c.馬名 AND 開催日<c.開催日 AND 指数 IS NOT NULL) z
         WHERE z.rr=1) y WHERE rk<=3) p
 OUTER APPLY (SELECT TOP 1 TRY_CONVERT(int,金額) 金額 FROM 払戻金 px WHERE px.開催日=r.開催日 AND px.開催場所=r.開催場所 AND px.レース番号=r.レース番号 AND px.馬券=N'単勝' AND TRY_CONVERT(int,px.組番)=c.馬番) pay
 WHERE r.着順>0
)
"@
function Seg($label,$cond){
  $m=(Q @"
WITH $CTE
SELECT COUNT(*) N,100.0*SUM(CASE WHEN 着順=1 THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) 勝,100.0*SUM(CASE WHEN 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) 複,100.0*SUM(CASE WHEN 着順=1 THEN ISNULL(tan,0) ELSE 0 END)/NULLIF(100.0*COUNT(*),0) 単回
FROM d WHERE v1 IS NOT NULL AND v2 IS NOT NULL AND v3 IS NOT NULL AND ($cond)
"@)[0]
  "    {0,-26} N={1,6} 勝率={2,5:N1}% 複勝率={3,5:N1}% 単回収={4,6:N1}%" -f $label,$m.N,$m.勝,$m.複,$m.単回
}
$bands=@(@('今走1位','i0=1'),@('今走2-3位','i0 BETWEEN 2 AND 3'),@('今走4-6位','i0 BETWEEN 4 AND 6'),@('今走7位↓','i0>=7'))

"===== (A) 今走順位band × 過去3走平均指数値 → 複勝率  ($From〜$To, 3走そろう馬) ====="
foreach($b in $bands){ "-- $($b[0]) --"
  Seg "過去3走平均 80+"    "$($b[1]) AND vavg>=80"
  Seg "過去3走平均 73-79"  "$($b[1]) AND vavg>=73 AND vavg<80"
  Seg "過去3走平均 66-72"  "$($b[1]) AND vavg>=66 AND vavg<73"
  Seg "過去3走平均 <66"    "$($b[1]) AND vavg<66"
}
""
"===== (B) 今走順位band × 過去3走で高指数(≥$HiThr)だった回数 → 複勝率 ====="
foreach($b in $bands){ "-- $($b[0]) --"
  for($k=0;$k -le 3;$k++){
    Seg "過去3走で高指数$k回" ("$($b[1]) AND (CASE WHEN v1>=$HiThr THEN 1 ELSE 0 END)+(CASE WHEN v2>=$HiThr THEN 1 ELSE 0 END)+(CASE WHEN v3>=$HiThr THEN 1 ELSE 0 END)=$k")
  }
}
""
"===== (C) 年別頑健性: 今走1位×過去3走平均80+ vs <66 (複勝率) ====="
foreach($y in 2022,2023,2024,2025,2026){
 $a=(Q "WITH $CTE SELECT COUNT(*) N,100.0*SUM(CASE WHEN 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) 複 FROM d WHERE v1 IS NOT NULL AND v2 IS NOT NULL AND v3 IS NOT NULL AND i0=1 AND vavg>=80 AND YEAR(開催日)=$y")[0]
 $b=(Q "WITH $CTE SELECT COUNT(*) N,100.0*SUM(CASE WHEN 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) 複 FROM d WHERE v1 IS NOT NULL AND v2 IS NOT NULL AND v3 IS NOT NULL AND i0=1 AND vavg<66 AND YEAR(開催日)=$y")[0]
 "  {0}: 平均80+ 複{1,5:N1}%(N={2,4}) / 平均<66 複{3,5:N1}%(N={4,4}) / 差{5,5:N1}pt" -f $y,$a.複,$a.N,$b.複,$b.N,($a.複-$b.複)
}
$conn.Close()
