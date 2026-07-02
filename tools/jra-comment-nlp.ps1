<#
.SYNOPSIS
  厩舎の話 本文の洗練センチメント(句レベル+否定考慮)が、コンピ順位帯ごとに着順へ上乗せするか検証。
.DESCRIPTION
  pos句/neg句のヒット数からスコア=pos-neg。強気(pos>=1&neg=0)/弱気(neg>=1&pos=0)/中立。
  コンピ帯(1位/2-3/4-6/7↓)別に強気vs弱気の複勝率/勝率/単回収を比較。相手・穴(低人気帯)で効くか。
#>
[CmdletBinding()]param([string]$From='2022-01-01',[string]$To='2026-12-31')
$ErrorActionPreference='Stop'
$cs=(Get-Content (Join-Path $PSScriptRoot '..\共通\appsettings.json') -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
$conn=New-Object System.Data.SqlClient.SqlConnection($cs);$conn.Open()
function Q($s){$c=$conn.CreateCommand();$c.CommandText=$s;$c.CommandTimeout=600;[void]$c.Parameters.AddWithValue('@f',$From);[void]$c.Parameters.AddWithValue('@t',$To);$r=$c.ExecuteReader();$o=@();while($r.Read()){$row=[ordered]@{};for($i=0;$i -lt $r.FieldCount;$i++){$row[$r.GetName($i)]=$r.GetValue($i)};$o+=[pscustomobject]$row};$r.Close();$o}

# 句レベル センチメント辞書(厩舎の話の語法に合わせ調整)
$pos=@('上々','絶好','勝ち負け','勝機','勝てる','勝負強','通用','堅実','完成度','申し分','順調','攻め駆け','気配は良','気配いい','動きがい','動き抜群','絞れ','仕上がり良','力は上位','能力は高','地力上位','自信','上昇度','上向','良化','良くなっ','見せ場','楽しみ','態勢は整','態勢が整','態勢は万全','態勢は整','一変')
$neg=@('鍵を握','鍵に','課題','厳しい','難しい','半信半疑','物足り','詰めが甘','ひと息','もう一息','叩き台','叩き2','叩き二','試走','度外視','様子を','微妙','不安','平凡','良くない','上がってこ','上がらな','ノド鳴','善戦','展開次第','流れ次第','できれば','ならば面白','甘い面','甘く')
function CaseSum($arr){ (($arr|ForEach-Object{ "CASE WHEN コメント LIKE N'%$($_ -replace "'","''")%' THEN 1 ELSE 0 END" }) -join '+') }
$posSql=CaseSum $pos; $negSql=CaseSum $neg

$CTE=@"
cp AS (SELECT 開催日,開催場所,レース番号,馬番,指数順位,ROW_NUMBER() OVER(PARTITION BY 開催日,開催場所,レース番号,馬番 ORDER BY 取得日時 DESC) rn FROM コンピ指数 WHERE 開催日 BETWEEN @f AND @t),
dn AS (SELECT 開催日,開催場所,レース番号,馬番,コメント,ROW_NUMBER() OVER(PARTITION BY 開催日,開催場所,レース番号,馬番 ORDER BY 取得日時 DESC) rn FROM 厩舎の話 WHERE 開催日 BETWEEN @f AND @t AND コメント IS NOT NULL AND LEN(コメント)>=8),
d AS (
 SELECT r.開催日,r.着順,cp.指数順位,
   CASE WHEN cp.指数順位=1 THEN '1:1位' WHEN cp.指数順位 BETWEEN 2 AND 3 THEN '2:2-3位' WHEN cp.指数順位 BETWEEN 4 AND 6 THEN '3:4-6位' ELSE '4:7位↓' END 帯,
   ($posSql) pos, ($negSql) neg, pay.金額 tan
 FROM レース情報 r
 JOIN cp ON cp.rn=1 AND cp.開催日=r.開催日 AND cp.開催場所=r.開催場所 AND cp.レース番号=r.レース番号 AND cp.馬番=r.馬番
 JOIN dn ON dn.rn=1 AND dn.開催日=r.開催日 AND dn.開催場所=r.開催場所 AND dn.レース番号=r.レース番号 AND dn.馬番=r.馬番
 OUTER APPLY (SELECT TOP 1 TRY_CONVERT(int,金額) 金額 FROM 払戻金 p WHERE p.開催日=r.開催日 AND p.開催場所=r.開催場所 AND p.レース番号=r.レース番号 AND p.馬券=N'単勝' AND TRY_CONVERT(int,p.組番)=r.馬番) pay
 WHERE r.着順>0
)
"@

"===== 本文センチメント × コンピ帯 (強気=pos>=1&neg=0 / 弱気=neg>=1&pos=0) $From〜$To ====="
"  pos辞書${($pos.Count)}句 / neg辞書${($neg.Count)}句"
Q @"
WITH $CTE
SELECT 帯,
 CASE WHEN pos>=1 AND neg=0 THEN '強気' WHEN neg>=1 AND pos=0 THEN '弱気' ELSE '中立' END senti,
 COUNT(*) N,
 100.0*SUM(CASE WHEN 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/COUNT(*) 複勝率,
 100.0*SUM(CASE WHEN 着順=1 THEN 1 ELSE 0 END)/COUNT(*) 勝率,
 100.0*SUM(CASE WHEN 着順=1 THEN ISNULL(tan,0) ELSE 0 END)/(100.0*COUNT(*)) 単回収
FROM d
GROUP BY 帯,CASE WHEN pos>=1 AND neg=0 THEN '強気' WHEN neg>=1 AND pos=0 THEN '弱気' ELSE '中立' END
HAVING COUNT(*)>=150 ORDER BY 帯,senti
"@ | %{ "  {0} [{1}] N={2,6} 複勝率={3,5:N1}% 勝率={4,5:N1}% 単回収={5,6:N1}%" -f $_.帯,$_.senti,$_.N,$_.複勝率,$_.勝率,$_.単回収 }
""
"===== 低人気帯(4-6位/7位↓)で 強気 が効くかの年別頑健性(複勝率) ====="
foreach($band in '4-6位','7位↓'){
  $cond= if($band -eq '4-6位'){'cp.指数順位 BETWEEN 4 AND 6'}else{'cp.指数順位>=7'}
  "  -- $band 強気 --"
  foreach($y in 2022,2023,2024){
    $m=(Q @"
WITH cp AS (SELECT 開催日,開催場所,レース番号,馬番,指数順位,ROW_NUMBER() OVER(PARTITION BY 開催日,開催場所,レース番号,馬番 ORDER BY 取得日時 DESC) rn FROM コンピ指数),
dn AS (SELECT 開催日,開催場所,レース番号,馬番,コメント,ROW_NUMBER() OVER(PARTITION BY 開催日,開催場所,レース番号,馬番 ORDER BY 取得日時 DESC) rn FROM 厩舎の話 WHERE コメント IS NOT NULL AND LEN(コメント)>=8)
SELECT COUNT(*) N,100.0*SUM(CASE WHEN r.着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) 複,100.0*SUM(CASE WHEN r.着順=1 THEN ISNULL(pay.金額,0) ELSE 0 END)/NULLIF(100.0*COUNT(*),0) 単回
FROM レース情報 r
JOIN cp ON cp.rn=1 AND cp.開催日=r.開催日 AND cp.開催場所=r.開催場所 AND cp.レース番号=r.レース番号 AND cp.馬番=r.馬番
JOIN dn ON dn.rn=1 AND dn.開催日=r.開催日 AND dn.開催場所=r.開催場所 AND dn.レース番号=r.レース番号 AND dn.馬番=r.馬番
OUTER APPLY (SELECT TOP 1 TRY_CONVERT(int,金額) 金額 FROM 払戻金 p WHERE p.開催日=r.開催日 AND p.開催場所=r.開催場所 AND p.レース番号=r.レース番号 AND p.馬券=N'単勝' AND TRY_CONVERT(int,p.組番)=r.馬番) pay
WHERE r.着順>0 AND YEAR(r.開催日)=$y AND $cond AND ($posSql)>=1 AND ($negSql)=0
"@)[0]
    "    {0}: N={1,5} 複勝率={2,5:N1}% 単回収={3,6:N1}%" -f $y,$m.N,$m.複,$m.単回
  }
}
$conn.Close()
