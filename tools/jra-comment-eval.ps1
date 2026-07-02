<#
.SYNOPSIS
  厩舎の話(印/本文)・調教(矢印)が「コンピ指数を制御した上で」着順/回収に上乗せするか検証。
.DESCRIPTION
  1馬行=コンピ順位+厩舎印+調教矢印+本文前向き/弱気語+着順+単勝払戻(勝時)。
  (A)コンピrank帯×厩舎印で複勝率→印が帯内で効くか。(B)コンピ1位×各コメント信号で勝率/複勝率/単回収。(C)複合の年別頑健性。
  市場効率の規律([[jra-axis-prob-model]])で「織込済か(回収>100%か)」「年別頑健か」を判定。
#>
[CmdletBinding()]param([string]$From='2022-01-01',[string]$To='2026-12-31')
$ErrorActionPreference='Stop'
$cs=(Get-Content (Join-Path $PSScriptRoot '..\共通\appsettings.json') -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
$conn=New-Object System.Data.SqlClient.SqlConnection($cs);$conn.Open()
function Q($s){$c=$conn.CreateCommand();$c.CommandText=$s;$c.CommandTimeout=600;[void]$c.Parameters.AddWithValue('@f',$From);[void]$c.Parameters.AddWithValue('@t',$To);$r=$c.ExecuteReader();$o=@();while($r.Read()){$row=[ordered]@{};for($i=0;$i -lt $r.FieldCount;$i++){$row[$r.GetName($i)]=$r.GetValue($i)};$o+=[pscustomobject]$row};$r.Close();$o}

# CTE定義(cp/dn/cy) と 1馬行SELECT(d) を分離して1つのWITHチェーンに連結する。
$CTE=@"
cp AS (SELECT 開催日,開催場所,レース番号,馬番,指数順位,ROW_NUMBER() OVER(PARTITION BY 開催日,開催場所,レース番号,馬番 ORDER BY 取得日時 DESC) rn FROM コンピ指数 WHERE 開催日 BETWEEN @f AND @t),
dn AS (SELECT 開催日,開催場所,レース番号,馬番,印,コメント,ROW_NUMBER() OVER(PARTITION BY 開催日,開催場所,レース番号,馬番 ORDER BY 取得日時 DESC) rn FROM 厩舎の話 WHERE 開催日 BETWEEN @f AND @t),
cy AS (SELECT 開催日,開催場所,レース番号,馬番,矢印,ROW_NUMBER() OVER(PARTITION BY 開催日,開催場所,レース番号,馬番 ORDER BY 取得日時 DESC) rn FROM 調教 WHERE 開催日 BETWEEN @f AND @t),
d AS (
 SELECT r.開催日,r.開催場所,r.レース番号,r.馬番,r.着順,cp.指数順位,dn.印 danwa印,dn.コメント,cy.矢印,
  CASE WHEN dn.コメント LIKE N'%上々%' OR dn.コメント LIKE N'%良化%' OR dn.コメント LIKE N'%上向%' OR dn.コメント LIKE N'%上昇%' OR dn.コメント LIKE N'%自信%' OR dn.コメント LIKE N'%順調%' OR dn.コメント LIKE N'%絶好%' OR dn.コメント LIKE N'%良くな%' OR dn.コメント LIKE N'%動きがい%' OR dn.コメント LIKE N'%仕上がりは上%' OR dn.コメント LIKE N'%勝ち負け%' OR dn.コメント LIKE N'%チャンス%' THEN 1 ELSE 0 END pos,
  CASE WHEN dn.コメント LIKE N'%鍵に%' OR dn.コメント LIKE N'%課題%' OR dn.コメント LIKE N'%厳しい%' OR dn.コメント LIKE N'%難しい%' OR dn.コメント LIKE N'%不安%' OR dn.コメント LIKE N'%物足り%' OR dn.コメント LIKE N'%様子を%' OR dn.コメント LIKE N'%半信半疑%' OR dn.コメント LIKE N'%微妙%' OR dn.コメント LIKE N'%叩き%' OR dn.コメント LIKE N'%度外視%' THEN 1 ELSE 0 END neg,
  pay.金額 tan
 FROM レース情報 r
 JOIN cp ON cp.rn=1 AND cp.開催日=r.開催日 AND cp.開催場所=r.開催場所 AND cp.レース番号=r.レース番号 AND cp.馬番=r.馬番
 LEFT JOIN dn ON dn.rn=1 AND dn.開催日=r.開催日 AND dn.開催場所=r.開催場所 AND dn.レース番号=r.レース番号 AND dn.馬番=r.馬番
 LEFT JOIN cy ON cy.rn=1 AND cy.開催日=r.開催日 AND cy.開催場所=r.開催場所 AND cy.レース番号=r.レース番号 AND cy.馬番=r.馬番
 OUTER APPLY (SELECT TOP 1 TRY_CONVERT(int,金額) 金額 FROM 払戻金 p WHERE p.開催日=r.開催日 AND p.開催場所=r.開催場所 AND p.レース番号=r.レース番号 AND p.馬券=N'単勝' AND TRY_CONVERT(int,p.組番)=r.馬番) pay
 WHERE r.着順>0
)
"@

"===== (A) コンピrank帯 × 厩舎印 → 複勝率 (印が帯内で効くか) ($From〜$To) ====="
Q @"
WITH $CTE
SELECT 帯,印,COUNT(*) N,100.0*SUM(CASE WHEN 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/COUNT(*) 複勝率,100.0*SUM(CASE WHEN 着順=1 THEN 1 ELSE 0 END)/COUNT(*) 勝率
FROM (SELECT 着順,CASE WHEN 指数順位=1 THEN '1:1位' WHEN 指数順位 BETWEEN 2 AND 3 THEN '2:2-3位' WHEN 指数順位 BETWEEN 4 AND 6 THEN '3:4-6位' ELSE '4:7位↓' END 帯,
  CASE WHEN danwa印 IN (N'◎',N'○',N'◯') THEN N'◎○' WHEN danwa印 IN (N'▲',N'△') THEN N'▲△' ELSE N'無/他' END 印 FROM d) x
GROUP BY 帯,印 HAVING COUNT(*)>=200 ORDER BY 帯,印
"@ | %{ "  {0} 印[{1}] N={2,6} 複勝率={3,5:N1}% 勝率={4,5:N1}%" -f $_.帯,$_.印,$_.N,$_.複勝率,$_.勝率 }
""
"===== (B) コンピ1位 を コメント信号で分解 (勝率/複勝率/単回収) ====="
function Seg($label,$cond){
  $m=(Q @"
WITH $CTE
SELECT COUNT(*) N,100.0*SUM(CASE WHEN 着順=1 THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) 勝率,
 100.0*SUM(CASE WHEN 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) 複勝率,
 100.0*SUM(CASE WHEN 着順=1 THEN ISNULL(tan,0) ELSE 0 END)/NULLIF(100.0*COUNT(*),0) 単回収
FROM d WHERE 指数順位=1 AND ($cond)
"@)[0]
  "  {0,-26} N={1,5} 勝率={2,5:N1}% 複勝率={3,5:N1}% 単回収={4,6:N1}%" -f $label,$m.N,$m.勝率,$m.複勝率,$m.単回収
}
Seg "コンピ1位 全体(基準)"        "1=1"
Seg "  x厩舎◎○"                  "danwa印 IN (N'◎',N'○',N'◯')"
Seg "  x厩舎▲△/無"               "danwa印 IS NULL OR danwa印 NOT IN (N'◎',N'○',N'◯')"
Seg "  x調教矢印 上向"             "矢印 LIKE N'%↗%' OR 矢印 LIKE N'%↑%' OR 矢印 LIKE N'%上%'"
Seg "  x調教矢印 下向"             "矢印 LIKE N'%↘%' OR 矢印 LIKE N'%↓%' OR 矢印 LIKE N'%下%'"
Seg "  x本文 前向き語"             "pos=1 AND neg=0"
Seg "  x本文 弱気語"               "neg=1 AND pos=0"
Seg "  x厩舎◎○ & 矢印上向(複合)"   "danwa印 IN (N'◎',N'○',N'◯') AND (矢印 LIKE N'%↗%' OR 矢印 LIKE N'%↑%' OR 矢印 LIKE N'%上%')"
""
"===== (C) 複合 コンピ1位x厩舎◎○x矢印上向x前向き語 の年別頑健性 ====="
foreach($y in 2022,2023,2024,2025,2026){
  $m=(Q @"
WITH $CTE
SELECT COUNT(*) N,100.0*SUM(CASE WHEN 着順=1 THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) 勝率,
 100.0*SUM(CASE WHEN 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) 複勝率,
 100.0*SUM(CASE WHEN 着順=1 THEN ISNULL(tan,0) ELSE 0 END)/NULLIF(100.0*COUNT(*),0) 単回収
FROM d WHERE 指数順位=1 AND danwa印 IN (N'◎',N'○',N'◯') AND (矢印 LIKE N'%↗%' OR 矢印 LIKE N'%↑%' OR 矢印 LIKE N'%上%') AND pos=1 AND YEAR(開催日)=$y
"@)[0]
  "  {0}: N={1,4} 勝率={2,5:N1}% 複勝率={3,5:N1}% 単回収={4,6:N1}%" -f $y,$m.N,$m.勝率,$m.複勝率,$m.単回収
}
$conn.Close()
