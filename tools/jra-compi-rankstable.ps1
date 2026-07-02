<#
.SYNOPSIS
  コンピ指数「安定上位」(前走順位≤T かつ 今走順位≤T)が、今走順位band内で複勝率を上乗せするか検証(地方からの依頼)。
.DESCRIPTION
  各馬: 今走コンピ順位 i0 / 前走コンピ順位 r1(馬名で過去参照) / 着順 / 単勝払戻。
  今走band(1位/2-3/4-6/7↓)を固定し、前走(上位1-T / 中下位T+1↓ / 前走なし)で複勝率/勝率/単回収を比較。
  規律: band固定で前走上位が複勝率を上げるか・年別頑健か。複勝率(軸確度)と回収(妙味)は別。([[jra-compi-trajectory]][[compi-index-trend]])
.PARAMETER T  上位の閾値(既定3)。
#>
[CmdletBinding()]param([string]$From='2022-01-01',[string]$To='2026-12-31',[int]$T=3)
$ErrorActionPreference='Stop'
$cs=(Get-Content (Join-Path $PSScriptRoot '..\共通\appsettings.json') -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
$conn=New-Object System.Data.SqlClient.SqlConnection($cs);$conn.Open()
function Q($s){$c=$conn.CreateCommand();$c.CommandText=$s;$c.CommandTimeout=600;[void]$c.Parameters.AddWithValue('@f',$From);[void]$c.Parameters.AddWithValue('@t',$To);$r=$c.ExecuteReader();$o=@();while($r.Read()){$row=[ordered]@{};for($i=0;$i -lt $r.FieldCount;$i++){$row[$r.GetName($i)]=$r.GetValue($i)};$o+=[pscustomobject]$row};$r.Close();$o}

$CTE=@"
cp AS (SELECT 開催日,開催場所,レース番号,馬番,馬名,指数順位 i0 FROM (SELECT *,ROW_NUMBER() OVER(PARTITION BY 開催日,開催場所,レース番号,馬番 ORDER BY 取得日時 DESC) rn FROM コンピ指数 WHERE 開催日 BETWEEN @f AND @t AND 指数順位 IS NOT NULL) z WHERE rn=1),
d AS (
 SELECT r.開催日,r.着順,c.i0,pp.r1,pay.金額 tan
 FROM cp c
 JOIN レース情報 r ON r.開催日=c.開催日 AND r.開催場所=c.開催場所 AND r.レース番号=c.レース番号 AND r.馬番=c.馬番 AND r.着順>0
 OUTER APPLY (SELECT TOP 1 z.指数順位 r1 FROM (SELECT 指数順位,開催日,レース番号,ROW_NUMBER() OVER(PARTITION BY 開催日,開催場所,レース番号 ORDER BY 取得日時 DESC) rr FROM コンピ指数 WHERE 馬名=c.馬名 AND 開催日<c.開催日 AND 指数順位 IS NOT NULL) z WHERE z.rr=1 ORDER BY z.開催日 DESC,z.レース番号 DESC) pp
 OUTER APPLY (SELECT TOP 1 TRY_CONVERT(int,金額) 金額 FROM 払戻金 p WHERE p.開催日=c.開催日 AND p.開催場所=c.開催場所 AND p.レース番号=c.レース番号 AND p.馬券=N'単勝' AND TRY_CONVERT(int,p.組番)=c.馬番) pay
)
"@
function Seg($label,$cond){
  $m=(Q @"
WITH $CTE
SELECT COUNT(*) N,100.0*SUM(CASE WHEN 着順=1 THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) 勝,100.0*SUM(CASE WHEN 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) 複,100.0*SUM(CASE WHEN 着順=1 THEN ISNULL(tan,0) ELSE 0 END)/NULLIF(100.0*COUNT(*),0) 単回
FROM d WHERE $cond
"@)[0]
  "  {0,-26} N={1,6} 勝率={2,5:N1}% 複勝率={3,5:N1}% 単回収={4,6:N1}%" -f $label,$m.N,$m.勝,$m.複,$m.単回
}
"===== コンピ安定上位 検証 (上位閾値T=$T) $From〜$To ====="
$bands=@(@('今走1位','i0=1'),@('今走2-3位','i0 BETWEEN 2 AND 3'),@('今走4-6位','i0 BETWEEN 4 AND 6'),@('今走7位↓','i0>=7'))
foreach($b in $bands){
  "-- $($b[0]) --"
  Seg "  前走上位(1-$T)"   "$($b[1]) AND r1 IS NOT NULL AND r1<=$T"
  Seg "  前走中下位($($T+1)↓)" "$($b[1]) AND r1 IS NOT NULL AND r1>$T"
  Seg "  前走なし(新馬等)"   "$($b[1]) AND r1 IS NULL"
}
""
"===== 安定上位ボーナスの年別頑健性: 今走1位×前走上位 vs 前走中下位(複勝率) ====="
foreach($y in 2022,2023,2024,2025,2026){
 $a=(Q "WITH $CTE SELECT 100.0*SUM(CASE WHEN 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) 複,COUNT(*) N FROM d WHERE i0=1 AND r1 IS NOT NULL AND r1<=$T AND YEAR(開催日)=$y")[0]
 $b=(Q "WITH $CTE SELECT 100.0*SUM(CASE WHEN 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) 複,COUNT(*) N FROM d WHERE i0=1 AND r1 IS NOT NULL AND r1>$T AND YEAR(開催日)=$y")[0]
 "  {0}: 前走上位 複{1,5:N1}%(N={2,4}) / 前走中下位 複{3,5:N1}%(N={4,4}) / 差{5,5:N1}pt" -f $y,$a.複,$a.N,$b.複,$b.N,($a.複-$b.複)
}
$conn.Close()
