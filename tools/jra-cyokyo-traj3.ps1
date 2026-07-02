<#
.SYNOPSIS
  調教(矢印/追い切り短評)の3走パターンで、今走馬券圏内になる買いパターン/消しパターンを探す(コンピband固定)。
.DESCRIPTION
  今走矢印a0/短評s0 + 過去2走矢印a1,a2(馬名参照) + コンピ順位band + 着順。完全な2022-2024で。
  規律: 今走順位band固定で基準複勝率に対し上回る=買い/下回る=消し。年別頑健性で確認。⚠️矢印LIKEはN接頭辞必須。
#>
[CmdletBinding()]param([string]$From='2022-01-01',[string]$To='2024-12-31')
$ErrorActionPreference='Stop'
$cs=(Get-Content (Join-Path $PSScriptRoot '..\共通\appsettings.json') -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
$conn=New-Object System.Data.SqlClient.SqlConnection($cs);$conn.Open()
function Q($s){$c=$conn.CreateCommand();$c.CommandText=$s;$c.CommandTimeout=600;[void]$c.Parameters.AddWithValue('@f',$From);[void]$c.Parameters.AddWithValue('@t',$To);$r=$c.ExecuteReader();$o=@();while($r.Read()){$row=[ordered]@{};for($i=0;$i -lt $r.FieldCount;$i++){$row[$r.GetName($i)]=$r.GetValue($i)};$o+=[pscustomobject]$row};$r.Close();$o}

# 今走調教(矢印a0/短評s0)+コンピ順位band+着順、過去2走矢印a1/a2(馬名)。ポジ/ネガ短評フラグ。
$CTE=@"
cy AS (SELECT 開催日,開催場所,レース番号,馬番,馬名,矢印,追い切り短評,ROW_NUMBER() OVER(PARTITION BY 開催日,開催場所,レース番号,馬番 ORDER BY 取得日時 DESC) rn FROM 調教 WHERE 開催日 BETWEEN @f AND @t),
cp AS (SELECT 開催日,開催場所,レース番号,馬番,指数順位,ROW_NUMBER() OVER(PARTITION BY 開催日,開催場所,レース番号,馬番 ORDER BY 取得日時 DESC) rn FROM コンピ指数 WHERE 開催日 BETWEEN @f AND @t),
d AS (
 SELECT r.着順,r.開催日,cp.指数順位,
   CASE WHEN c.矢印 LIKE N'%↗%' OR c.矢印 LIKE N'%↑%' THEN 'up' WHEN c.矢印 LIKE N'%↘%' OR c.矢印 LIKE N'%↓%' THEN 'down' ELSE 'flat' END a0,
   CASE WHEN cp.指数順位=1 THEN '1:1位' WHEN cp.指数順位 BETWEEN 2 AND 3 THEN '2:2-3位' WHEN cp.指数順位 BETWEEN 4 AND 6 THEN '3:4-6位' ELSE '4:7位↓' END band,
   CASE WHEN c.追い切り短評 LIKE N'%好調%' OR c.追い切り短評 LIKE N'%抜群%' OR c.追い切り短評 LIKE N'%鋭%' OR c.追い切り短評 LIKE N'%上々%' OR c.追い切り短評 LIKE N'%先着%' OR c.追い切り短評 LIKE N'%良化%' OR c.追い切り短評 LIKE N'%動き良%' OR c.追い切り短評 LIKE N'%仕上が%' OR c.追い切り短評 LIKE N'%持続%' OR c.追い切り短評 LIKE N'%文句%' OR c.追い切り短評 LIKE N'%軽快%' OR c.追い切り短評 LIKE N'%互角%' THEN 1 ELSE 0 END spos,
   CASE WHEN c.追い切り短評 LIKE N'%一杯%' OR c.追い切り短評 LIKE N'%促%' OR c.追い切り短評 LIKE N'%追われ%' OR c.追い切り短評 LIKE N'%案外%' OR c.追い切り短評 LIKE N'%平凡%' OR c.追い切り短評 LIKE N'%物足%' OR c.追い切り短評 LIKE N'%鈍%' OR c.追い切り短評 LIKE N'%重め%' OR c.追い切り短評 LIKE N'%見劣%' OR c.追い切り短評 LIKE N'%余裕%' OR c.追い切り短評 LIKE N'%息持%' THEN 1 ELSE 0 END sneg,
   p.up3
 FROM cy c
 JOIN cp ON cp.rn=1 AND cp.開催日=c.開催日 AND cp.開催場所=c.開催場所 AND cp.レース番号=c.レース番号 AND cp.馬番=c.馬番
 JOIN レース情報 r ON r.開催日=c.開催日 AND r.開催場所=c.開催場所 AND r.レース番号=c.レース番号 AND r.馬番=c.馬番 AND r.着順>0
 CROSS APPLY (SELECT SUM(CASE WHEN 矢印 LIKE N'%↗%' OR 矢印 LIKE N'%↑%' THEN 1 ELSE 0 END) up3
   FROM (SELECT TOP 3 z.矢印 FROM (SELECT 矢印,開催日,レース番号,ROW_NUMBER() OVER(PARTITION BY 開催日,開催場所,レース番号 ORDER BY 取得日時 DESC) rr FROM 調教 WHERE 馬名=c.馬名 AND 開催日<=c.開催日) z WHERE z.rr=1 ORDER BY z.開催日 DESC,z.レース番号 DESC) q) p
 WHERE c.rn=1 AND r.着順>0
)
"@
function Seg($label,$cond){
  $m=(Q @"
WITH $CTE
SELECT COUNT(*) N,100.0*SUM(CASE WHEN 着順=1 THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) 勝,100.0*SUM(CASE WHEN 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) 複
FROM d WHERE $cond
"@)[0]
  "    {0,-24} N={1,6} 勝率={2,5:N1}% 複勝率={3,5:N1}%" -f $label,$m.N,$m.勝,$m.複
}
$bands=@(@('今走1位','指数順位=1'),@('今走2-3位','指数順位 BETWEEN 2 AND 3'),@('今走4-6位','指数順位 BETWEEN 4 AND 6'),@('今走7位↓','指数順位>=7'))

"===== (基準) 今走band 複勝率  ($From〜$To, 完全な調教窓) ====="
foreach($b in $bands){ Seg $b[0] $b[1] }
""
"===== (A) band × 今走矢印 ====="
foreach($b in $bands){ "-- $($b[0]) --"; foreach($a in 'up','flat','down'){ Seg "今走矢印=$a" "$($b[1]) AND a0='$a'" } }
""
"===== (B) band × 直近3走の↗回数(今走含む) ====="
foreach($b in $bands){ "-- $($b[0]) --"; for($k=0;$k -le 3;$k++){ Seg "↗ $k回" "$($b[1]) AND up3=$k" } }
""
"===== (C) band × 今走短評センチメント (買い=ポジ/消し=ネガ) ====="
foreach($b in $bands){ "-- $($b[0]) --"
  Seg "短評ポジ(ネガ無)" "$($b[1]) AND spos=1 AND sneg=0"
  Seg "短評ネガ(ポジ無)" "$($b[1]) AND sneg=1 AND spos=0"
  Seg "短評中立" "$($b[1]) AND spos=0 AND sneg=0"
}
""
"===== (D) 消し候補の年別頑健性: 今走1位×(今走flat&↗0回) と 今走1位×短評ネガ ====="
foreach($y in 2022,2023,2024){
 $b1=(Q "WITH $CTE SELECT 100.0*SUM(CASE WHEN 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) 複,COUNT(*) N FROM d WHERE 指数順位=1 AND YEAR(開催日)=$y")[0]
 $b2=(Q "WITH $CTE SELECT 100.0*SUM(CASE WHEN 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) 複,COUNT(*) N FROM d WHERE 指数順位=1 AND a0='flat' AND up3=0 AND YEAR(開催日)=$y")[0]
 $b3=(Q "WITH $CTE SELECT 100.0*SUM(CASE WHEN 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) 複,COUNT(*) N FROM d WHERE 指数順位=1 AND sneg=1 AND spos=0 AND YEAR(開催日)=$y")[0]
 "  {0}: 基準{1,5:N1}% / flat&↗0回 {2,5:N1}%(N={3,4}) / 短評ネガ {4,5:N1}%(N={5,4})" -f $y,$b1.複,$b2.複,$b2.N,$b3.複,$b3.N
}
$conn.Close()
