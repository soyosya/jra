<#
.SYNOPSIS
  大井のコース・距離別の脚質有利度と、三→四コーナーの位置変化(まくり)を分解します。

.DESCRIPTION
  競走結果のコーナー通過順から、各馬の「序盤位置(early=最初の非ゼロコーナー)」と
  「四角位置(C4。欠損時はC3にフォールバック)」を頭数で相対化し、距離別に集計します。

  出力は2部:
    (1) 脚質有利度  … 序盤位置で 逃げ/先行/差し/追込 に分類し、距離別の 出走割合/勝率/複勝率/
                      インパクト値(=脚質別勝率/全体平均勝率) を算出。
    (2) まくりクロス … 序盤位置(前/中/後)× 四角位置(前/中/後)の9セルで勝率・複勝率。
                      「序盤中後→四角前」が★まくり、「序盤前→四角中後」が▼後退。

  既知の事実(2024-01以降):
    - 大井は前残り(先行有利)。距離が短いほど極端(逃げIV 1200=3.64 / 1600=2.89 / 1800=2.42)。
    - 勝敗を決めるのは序盤位置より「四角位置」。四角で前(top33%)なら距離問わず勝率20%超。
    - まくり(序盤中後→四角前)は前残りと互角以上。ただし1200mは短すぎて後方→四角前がほぼ不成立、
      1600m以上で有効(1600mは後方→四角前でも勝率24%)。

  コーナー記録の充足(大井): 1200m=C3/C4のみ, 1400m=C4が54%欠損(C3で代替), 1600m+=全周完備。

.PARAMETER From / To / Venue / Distances
  集計対象。既定 2024-01-01〜2026-06-14 / 大井 / 1200,1600,1800。

.EXAMPLE
  .\oi-kyaku-course.ps1
  .\oi-kyaku-course.ps1 -Venue 川崎 -Distances 1400,1500,2000
#>
[CmdletBinding()]
param(
    [string]$From = '2024-01-01',
    [string]$To   = '2026-06-14',
    [string]$Venue = '大井',
    [int[]]$Distances = @(1200, 1600, 1800)
)

$ErrorActionPreference = 'Stop'

$appsettings = Join-Path $PSScriptRoot '..\共通\appsettings.json'
if (-not (Test-Path $appsettings)) { throw "appsettings.json が見つかりません: $appsettings" }
$connStr = (Get-Content $appsettings -Raw -Encoding UTF8 | ConvertFrom-Json).ConnectionStrings.DefaultConnection
if ([string]::IsNullOrWhiteSpace($connStr)) { throw 'ConnectionStrings:DefaultConnection を取得できませんでした。' }

$distList = ($Distances | ForEach-Object { [int]$_ }) -join ','

# 各馬の序盤位置・四角位置を頭数で相対化(rinfo別名: Remove-Item誤検知回避のため ri は使わない)
$cte = @"
WITH base AS (
  SELECT rinfo.距離 dist, k.着順,
    COALESCE(NULLIF(k.一コーナー,0),NULLIF(k.二コーナー,0),NULLIF(k.三コーナー,0),NULLIF(k.四コーナー,0)) early,
    COALESCE(NULLIF(k.四コーナー,0),NULLIF(k.三コーナー,0)) c4,
    COUNT(*) OVER(PARTITION BY k.開催日,k.レース番号) n
  FROM 競走結果 k
  JOIN レース情報 rinfo ON rinfo.開催場所=k.開催場所 AND rinfo.開催日=k.開催日 AND rinfo.レース番号=k.レース番号 AND rinfo.馬番=k.馬番
  WHERE k.開催場所=@venue AND k.開催日 BETWEEN @from AND @to AND rinfo.距離 IN ($distList)
)
"@

function Invoke-Sql([string]$tail) {
    $conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
    $conn.Open()
    try {
        $cmd = $conn.CreateCommand(); $cmd.CommandTimeout = 180
        $cmd.CommandText = $cte + $tail
        [void]$cmd.Parameters.AddWithValue('@from', $From)
        [void]$cmd.Parameters.AddWithValue('@to', $To)
        [void]$cmd.Parameters.AddWithValue('@venue', $Venue)
        $r = $cmd.ExecuteReader()
        $rows = @()
        while ($r.Read()) {
            $o = [ordered]@{}
            for ($i = 0; $i -lt $r.FieldCount; $i++) { $o[$r.GetName($i)] = $r.GetValue($i) }
            $rows += [PSCustomObject]$o
        }
        $r.Close(); return $rows
    } finally { $conn.Close() }
}

Write-Host ("対象: {0}  距離 {1}  期間 {2}〜{3}" -f $Venue, $distList, $From, $To)

# (1) 脚質有利度(序盤位置ベース)
$ky = Invoke-Sql @"
SELECT dist, kyaku, COUNT(*) 頭, SUM(CASE WHEN 着順=1 THEN 1 ELSE 0 END) 勝, SUM(CASE WHEN 着順<=3 THEN 1 ELSE 0 END) 複
FROM (
  SELECT dist, 着順,
    CASE WHEN early=1 THEN N'1逃げ' WHEN early<=n*0.33 THEN N'2先行' WHEN early<=n*0.66 THEN N'3差し' ELSE N'4追込' END kyaku
  FROM base WHERE early IS NOT NULL AND n IS NOT NULL
) t GROUP BY dist, kyaku ORDER BY dist, kyaku
"@
Write-Host "`n【1】脚質有利度(序盤位置)  IV=脚質別勝率/全体平均勝率"
foreach ($d in ($ky | Group-Object dist)) {
    $tot = ($d.Group | Measure-Object 頭 -Sum).Sum
    $totw = ($d.Group | Measure-Object 勝 -Sum).Sum
    $bw = $totw / $tot
    Write-Host ("`n  -- {0}m  全{1}頭 平均勝率{2:P1} --" -f $d.Name, $tot, $bw)
    Write-Host "  脚質    頭数   出走% 勝率   複勝率   IV"
    foreach ($x in ($d.Group | Sort-Object kyaku)) {
        $n = [int]$x.頭
        Write-Host ("  {0,-6} {1,6} {2,5:P0} {3,6:P1} {4,6:P1}  {5,4:N2}" -f $x.kyaku, $n, ($n/$tot), ([int]$x.勝/$n), ([int]$x.複/$n), (([int]$x.勝/$n)/$bw))
    }
}

# (2) まくりクロス(序盤×四角)
$mk = Invoke-Sql @"
SELECT dist, eb, fb, COUNT(*) 頭, SUM(CASE WHEN 着順=1 THEN 1 ELSE 0 END) 勝, SUM(CASE WHEN 着順<=3 THEN 1 ELSE 0 END) 複
FROM (
  SELECT dist, 着順,
    CASE WHEN early<=n*0.33 THEN N'前' WHEN early<=n*0.66 THEN N'中' ELSE N'後' END eb,
    CASE WHEN c4<=n*0.33 THEN N'前' WHEN c4<=n*0.66 THEN N'中' ELSE N'後' END fb
  FROM base WHERE early IS NOT NULL AND c4 IS NOT NULL AND n IS NOT NULL
) t GROUP BY dist, eb, fb ORDER BY dist, eb, fb
"@
$ord = @{ '前'=1; '中'=2; '後'=3 }
Write-Host "`n【2】まくりクロス(序盤→四角)  ★=まくり(後方→前) ▼=後退(前→後方)"
foreach ($d in ($mk | Group-Object dist)) {
    Write-Host ("`n  -- {0}m --" -f $d.Name)
    Write-Host "  序盤→四角  頭数   勝率   複勝率"
    foreach ($x in ($d.Group | Sort-Object @{e={$ord[$_.eb]}}, @{e={$ord[$_.fb]}})) {
        $n = [int]$x.頭
        $tag = "$($x.eb)→$($x.fb)"
        $m = if ($x.eb -ne '前' -and $x.fb -eq '前') { ' ★' } elseif ($x.eb -eq '前' -and $x.fb -ne '前') { ' ▼' } else { '' }
        Write-Host ("  {0,-8} {1,6} {2,6:P1} {3,6:P1}{4}" -f $tag, $n, ([int]$x.勝/$n), ([int]$x.複/$n), $m)
    }
}
