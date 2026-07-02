<#
.SYNOPSIS
  コンピ指数を3走前まで(前々々走i3→前々走i2→前走i1→今走i0の順位)見て、今走馬券圏内(着順≤3)になった馬の変遷特徴を分析。
.DESCRIPTION
  各馬の今走順位i0 + 過去3走順位(i1,i2,i3を馬名で参照)。規律=今走順位band固定で効くか・複勝率(軸確度)と単回収(妙味)は別。
  (A)band固定×過去3走の上位(≤3)回数(0-3)→複勝率(安定上位の3走版)。
  (B)band固定×変遷の向き(連続上昇/連続下降/V字回復/山型/混在)→複勝率/単回収。
  (C)有望cutの年別頑健性。3走そろう馬のみ(初出走少走は対象外=割引しない)。
#>
[CmdletBinding()]param([string]$From='2022-01-01',[string]$To='2026-12-31')
$ErrorActionPreference='Stop'
$cs=(Get-Content (Join-Path $PSScriptRoot '..\共通\appsettings.json') -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
$conn=New-Object System.Data.SqlClient.SqlConnection($cs);$conn.Open()
function Q($s){$c=$conn.CreateCommand();$c.CommandText=$s;$c.CommandTimeout=600;[void]$c.Parameters.AddWithValue('@f',$From);[void]$c.Parameters.AddWithValue('@t',$To);$r=$c.ExecuteReader();$o=@();while($r.Read()){$row=[ordered]@{};for($i=0;$i -lt $r.FieldCount;$i++){$row[$r.GetName($i)]=$r.GetValue($i)};$o+=[pscustomobject]$row};$r.Close();$o}

# 今走順位i0 + 過去3走順位r1/r2/r3(馬名参照,レース単位最新スナップ) + 着順 + 単勝払戻。3走そろう馬のみ。
$CTE=@"
cp AS (SELECT 開催日,開催場所,レース番号,馬番,馬名,指数順位 i0 FROM (SELECT *,ROW_NUMBER() OVER(PARTITION BY 開催日,開催場所,レース番号,馬番 ORDER BY 取得日時 DESC) rn FROM コンピ指数 WHERE 開催日 BETWEEN @f AND @t AND 指数順位 IS NOT NULL) z WHERE rn=1),
d AS (
 SELECT r.開催日,r.着順,c.i0,p.r1,p.r2,p.r3,pay.金額 tan,
   CASE WHEN c.i0=1 THEN '1:1位' WHEN c.i0 BETWEEN 2 AND 3 THEN '2:2-3位' WHEN c.i0 BETWEEN 4 AND 6 THEN '3:4-6位' ELSE '4:7位↓' END band
 FROM cp c
 JOIN レース情報 r ON r.開催日=c.開催日 AND r.開催場所=c.開催場所 AND r.レース番号=c.レース番号 AND r.馬番=c.馬番 AND r.着順>0
 CROSS APPLY (SELECT MAX(CASE WHEN rk=1 THEN rank END) r1,MAX(CASE WHEN rk=2 THEN rank END) r2,MAX(CASE WHEN rk=3 THEN rank END) r3
   FROM (SELECT z.指数順位 rank,ROW_NUMBER() OVER(ORDER BY z.開催日 DESC,z.レース番号 DESC) rk
         FROM (SELECT *,ROW_NUMBER() OVER(PARTITION BY 開催日,開催場所,レース番号 ORDER BY 取得日時 DESC) rr FROM コンピ指数 WHERE 馬名=c.馬名 AND 開催日<c.開催日 AND 指数順位 IS NOT NULL) z
         WHERE z.rr=1) y WHERE rk<=3) p
 OUTER APPLY (SELECT TOP 1 TRY_CONVERT(int,金額) 金額 FROM 払戻金 px WHERE px.開催日=r.開催日 AND px.開催場所=r.開催場所 AND px.レース番号=r.レース番号 AND px.馬券=N'単勝' AND TRY_CONVERT(int,px.組番)=c.馬番) pay
 WHERE r.着順>0
)
"@
function Seg($label,$cond){
  $m=(Q @"
WITH $CTE
SELECT COUNT(*) N,100.0*SUM(CASE WHEN 着順=1 THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) 勝,100.0*SUM(CASE WHEN 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) 複,100.0*SUM(CASE WHEN 着順=1 THEN ISNULL(tan,0) ELSE 0 END)/NULLIF(100.0*COUNT(*),0) 単回
FROM d WHERE r1 IS NOT NULL AND r2 IS NOT NULL AND r3 IS NOT NULL AND ($cond)
"@)[0]
  "    {0,-22} N={1,6} 勝率={2,5:N1}% 複勝率={3,5:N1}% 単回収={4,6:N1}%" -f $label,$m.N,$m.勝,$m.複,$m.単回
}
$bands=@(@('今走1位','i0=1'),@('今走2-3位','i0 BETWEEN 2 AND 3'),@('今走4-6位','i0 BETWEEN 4 AND 6'),@('今走7位↓','i0>=7'))

"===== (A) 今走band × 過去3走の上位(≤3)回数 → 複勝率  ($From〜$To, 3走そろう馬) ====="
foreach($b in $bands){ "-- $($b[0]) --"
  for($k=0;$k -le 3;$k++){
    Seg "過去3走で上位$k回" ("$($b[1]) AND (CASE WHEN r1<=3 THEN 1 ELSE 0 END)+(CASE WHEN r2<=3 THEN 1 ELSE 0 END)+(CASE WHEN r3<=3 THEN 1 ELSE 0 END)=$k")
  }
}
""
"===== (B) 今走band × 変遷の向き → 複勝率/単回収 ====="
# 順位は小さいほど良い。連続上昇=i0<=r1<=r2<=r3(過去ほど下位→今走最上位)、連続下降=i0>=r1>=r2>=r3、V字=前走r1が直近3走で最悪かつi0改善、山型=前走r1が最良かつi0悪化。
foreach($b in $bands){ "-- $($b[0]) --"
  Seg "連続上昇(i0≤r1≤r2≤r3)" "$($b[1]) AND i0<=r1 AND r1<=r2 AND r2<=r3"
  Seg "連続下降(i0≥r1≥r2≥r3)" "$($b[1]) AND i0>=r1 AND r1>=r2 AND r2>=r3"
  Seg "V字回復(前走凹→今走改善)" "$($b[1]) AND r1>r2 AND r1>i0 AND i0<=r2"
  Seg "山型(前走凸→今走悪化)" "$($b[1]) AND r1<r2 AND r1<i0 AND i0>=r2"
  Seg "その他(混在)" "$($b[1]) AND NOT(i0<=r1 AND r1<=r2 AND r2<=r3) AND NOT(i0>=r1 AND r1>=r2 AND r2>=r3) AND NOT(r1>r2 AND r1>i0 AND i0<=r2) AND NOT(r1<r2 AND r1<i0 AND i0>=r2)"
}
""
"===== (C) 年別頑健性: 今走1位×過去3走3回上位 vs 0-1回 (複勝率) ====="
foreach($y in 2022,2023,2024,2025,2026){
 $a=(Q "WITH $CTE SELECT COUNT(*) N,100.0*SUM(CASE WHEN 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) 複 FROM d WHERE r1 IS NOT NULL AND r2 IS NOT NULL AND r3 IS NOT NULL AND i0=1 AND r1<=3 AND r2<=3 AND r3<=3 AND YEAR(開催日)=$y")[0]
 $b=(Q "WITH $CTE SELECT COUNT(*) N,100.0*SUM(CASE WHEN 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) 複 FROM d WHERE r1 IS NOT NULL AND r2 IS NOT NULL AND r3 IS NOT NULL AND i0=1 AND ((CASE WHEN r1<=3 THEN 1 ELSE 0 END)+(CASE WHEN r2<=3 THEN 1 ELSE 0 END)+(CASE WHEN r3<=3 THEN 1 ELSE 0 END))<=1 AND YEAR(開催日)=$y")[0]
 "  {0}: 3回上位 複{1,5:N1}%(N={2,4}) / 0-1回 複{3,5:N1}%(N={4,4}) / 差{5,5:N1}pt" -f $y,$a.複,$a.N,$b.複,$b.N,($a.複-$b.複)
}
$conn.Close()
