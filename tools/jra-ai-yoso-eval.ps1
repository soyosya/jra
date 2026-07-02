<#
.SYNOPSIS
  極ウマAI予想(前日rt0/直前rt9)の軸有用性 + 直前変化の価値を検証。
.DESCRIPTION
  AI予想を レース情報(着順) と結合し、本命(rank1)等の勝率/複勝率/単勝回収(払戻金・単勝)を算出。
  コンピ1位と比較。直前で昇格/降格した馬の成績で「直前変化の価値」を検証。年別頑健性も。
#>
[CmdletBinding()]param([string]$From='2022-01-01',[string]$To='2026-12-31')
$ErrorActionPreference='Stop'
$cs=(Get-Content (Join-Path $PSScriptRoot '..\共通\appsettings.json') -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
$conn=New-Object System.Data.SqlClient.SqlConnection($cs);$conn.Open()
function Q($s){$c=$conn.CreateCommand();$c.CommandText=$s;$c.CommandTimeout=600;[void]$c.Parameters.AddWithValue('@f',$From);[void]$c.Parameters.AddWithValue('@t',$To);$r=$c.ExecuteReader();$o=@();while($r.Read()){$row=[ordered]@{};for($i=0;$i -lt $r.FieldCount;$i++){$row[$r.GetName($i)]=$r.GetValue($i)};$o+=[pscustomobject]$row};$r.Close();$o}

# セレクタ(1レース1本命: 開催日/開催場所/レース番号/馬番)→ N/勝率/複勝率/単回収
function Metrics($selCte){
@"
WITH sel AS ($selCte)
SELECT COUNT(*) N,
 100.0*SUM(CASE WHEN r.着順=1 THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) 勝率,
 100.0*SUM(CASE WHEN r.着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) 複勝率,
 100.0*SUM(CASE WHEN r.着順=1 THEN ISNULL(pay.金額,0) ELSE 0 END)/NULLIF(100.0*COUNT(*),0) 単回収
FROM sel s
JOIN レース情報 r ON r.開催日=s.開催日 AND r.開催場所=s.開催場所 AND r.レース番号=s.レース番号 AND r.馬番=s.馬番 AND r.着順>0
OUTER APPLY (SELECT TOP 1 TRY_CONVERT(int,金額) 金額 FROM 払戻金 p WHERE p.開催日=s.開催日 AND p.開催場所=s.開催場所 AND p.レース番号=s.レース番号 AND p.馬券=N'単勝' AND TRY_CONVERT(int,p.組番)=s.馬番) pay
"@
}
function Show($label,$selCte){ $m=(Q (Metrics $selCte))[0]; "{0,-30} N={1,5} 勝率={2,5:N1}% 複勝率={3,5:N1}% 単回収={4,6:N1}%" -f $label,$m.N,$m.勝率,$m.複勝率,$m.単回収 }

$base="開催日 BETWEEN @f AND @t"
# 共通セレクタ
$aiZen="SELECT 開催日,開催場所,レース番号,MIN(馬番) 馬番 FROM AI予想 WHERE run_type=0 AND AI順位=1 AND $base GROUP BY 開催日,開催場所,レース番号"
$aiCho="SELECT 開催日,開催場所,レース番号,MIN(馬番) 馬番 FROM AI予想 WHERE run_type=9 AND AI順位=1 AND $base GROUP BY 開催日,開催場所,レース番号"
$compi="SELECT 開催日,開催場所,レース番号,MIN(馬番) 馬番 FROM コンピ指数 WHERE 指数順位=1 AND $base GROUP BY 開催日,開催場所,レース番号"
# 直前本命を前日順位で分解(c=直前rank1, z=前日同馬)
function ChoByZen($cond){ "SELECT c.開催日,c.開催場所,c.レース番号,c.馬番 FROM AI予想 c LEFT JOIN AI予想 z ON z.run_type=0 AND z.開催日=c.開催日 AND z.開催場所=c.開催場所 AND z.レース番号=c.レース番号 AND z.馬番=c.馬番 WHERE c.run_type=9 AND c.AI順位=1 AND c.$base AND ($cond)" }
# 前日本命を直前順位で分解(z=前日rank1, c=直前同馬)
function ZenByCho($cond){ "SELECT z.開催日,z.開催場所,z.レース番号,z.馬番 FROM AI予想 z LEFT JOIN AI予想 c ON c.run_type=9 AND c.開催日=z.開催日 AND c.開催場所=z.開催場所 AND c.レース番号=z.レース番号 AND c.馬番=z.馬番 WHERE z.run_type=0 AND z.AI順位=1 AND z.$base AND ($cond)" }

"===== (1) 本命(rank1)基礎: 前日AI / 直前AI / コンピ1位  ($From〜$To) ====="
Show "前日AI 本命"  $aiZen
Show "直前AI 本命"  $aiCho
Show "コンピ1位"    $compi
""
"===== (2) AI印×着順 (直前rt9) ====="
Q @"
SELECT a.AI印 印,COUNT(*) N,
 100.0*SUM(CASE WHEN r.着順=1 THEN 1 ELSE 0 END)/COUNT(*) 勝率,
 100.0*SUM(CASE WHEN r.着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/COUNT(*) 複勝率
FROM AI予想 a JOIN レース情報 r ON r.開催日=a.開催日 AND r.開催場所=a.開催場所 AND r.レース番号=a.レース番号 AND r.馬番=a.馬番 AND r.着順>0
WHERE a.run_type=9 AND a.$base AND a.AI印 IS NOT NULL GROUP BY a.AI印 ORDER BY 複勝率 DESC
"@ | %{ "  印[{0}] N={1,6} 勝率={2,5:N1}% 複勝率={3,5:N1}%" -f $_.印,$_.N,$_.勝率,$_.複勝率 }
""
"===== (3) 直前変化の価値: 直前本命(◎)を『前日の順位』で分解 ====="
Show "直前◎ × 前日も1位(継続)"      (ChoByZen "z.AI順位=1")
Show "直前◎ × 前日2-3位(小昇格)"    (ChoByZen "z.AI順位 IN (2,3)")
Show "直前◎ × 前日4位↓/印無(大昇格)" (ChoByZen "z.AI順位 IS NULL OR z.AI順位>=4")
""
"===== (4) 逆: 前日本命(◎)を『直前の順位』で分解 ====="
Show "前日◎ × 直前も1位(継続)"      (ZenByCho "c.AI順位=1")
Show "前日◎ × 直前2-3位(小降格)"    (ZenByCho "c.AI順位 IN (2,3)")
Show "前日◎ × 直前4位↓/印落ち(大降格)"(ZenByCho "c.AI順位 IS NULL OR c.AI順位>=4")
""
"===== (5) 直前AI◎ × コンピ1位 の一致/不一致 ====="
$agree="SELECT a.開催日,a.開催場所,a.レース番号,a.馬番 FROM (SELECT 開催日,開催場所,レース番号,MIN(馬番) 馬番 FROM AI予想 WHERE run_type=9 AND AI順位=1 AND $base GROUP BY 開催日,開催場所,レース番号) a JOIN (SELECT 開催日,開催場所,レース番号,MIN(馬番) 馬番 FROM コンピ指数 WHERE 指数順位=1 AND $base GROUP BY 開催日,開催場所,レース番号) k ON k.開催日=a.開催日 AND k.開催場所=a.開催場所 AND k.レース番号=a.レース番号 AND k.馬番=a.馬番"
$disag="SELECT a.開催日,a.開催場所,a.レース番号,a.馬番 FROM (SELECT 開催日,開催場所,レース番号,MIN(馬番) 馬番 FROM AI予想 WHERE run_type=9 AND AI順位=1 AND $base GROUP BY 開催日,開催場所,レース番号) a JOIN (SELECT 開催日,開催場所,レース番号,MIN(馬番) 馬番 FROM コンピ指数 WHERE 指数順位=1 AND $base GROUP BY 開催日,開催場所,レース番号) k ON k.開催日=a.開催日 AND k.開催場所=a.開催場所 AND k.レース番号=a.レース番号 WHERE k.馬番<>a.馬番"
$disagK="SELECT k.開催日,k.開催場所,k.レース番号,k.馬番 FROM (SELECT 開催日,開催場所,レース番号,MIN(馬番) 馬番 FROM AI予想 WHERE run_type=9 AND AI順位=1 AND $base GROUP BY 開催日,開催場所,レース番号) a JOIN (SELECT 開催日,開催場所,レース番号,MIN(馬番) 馬番 FROM コンピ指数 WHERE 指数順位=1 AND $base GROUP BY 開催日,開催場所,レース番号) k ON k.開催日=a.開催日 AND k.開催場所=a.開催場所 AND k.レース番号=a.レース番号 WHERE k.馬番<>a.馬番"
Show "AI◎=コンピ1位(一致)"         $agree
Show "不一致時のAI◎"               $disag
Show "不一致時のコンピ1位"         $disagK
""
"===== (6) 直前AI本命 年別頑健性 ====="
foreach($y in 2022,2023,2024,2025,2026){
  $yf="$y-01-01"; $yt="$y-12-31"
  $sel="SELECT 開催日,開催場所,レース番号,MIN(馬番) 馬番 FROM AI予想 WHERE run_type=9 AND AI順位=1 AND 開催日 BETWEEN '$yf' AND '$yt' GROUP BY 開催日,開催場所,レース番号"
  $m=(Q (Metrics $sel))[0]
  "  {0}: N={1,5} 勝率={2,5:N1}% 複勝率={3,5:N1}% 単回収={4,6:N1}%" -f $y,$m.N,$m.勝率,$m.複勝率,$m.単回収
}
$conn.Close()
