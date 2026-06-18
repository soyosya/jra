<#
.SYNOPSIS
  中央競馬のイロレーティング(Elo)を競走結果から算出します。

.DESCRIPTION
  各レースを「全出走馬の総当たり」とみなし、着順で勝敗(同着0.5)を決めて
  イロレーティングを時系列に更新します。対戦のない他場の馬とも、複数場を
  走る馬を介して相対的な強さが繋がります(イロ方式の利点)。
  時計・斤量・馬場は見ません(イロ方式の既知の限界)。

  多頭数対応: 1走をN頭の総当たりに分解し、各馬を
    new = R + K * (実際に勝った数 - 期待勝ち数) / (N-1)
  で更新。期待勝ち数は E = Σ_j 1/(1+10^((Rj-Ri)/400))。
  暫定期間(出走 < ProvisionalStarts)は K を ProvisionalFactor 倍にして早く収束。

  馬の同定は競走結果.馬名。ばんえい(場名末尾「ば」)は既定で除外。

.PARAMETER From / To
  対象開催日の範囲(yyyy-MM-dd)。既定は全期間。

.PARAMETER K / InitialRating
  K係数(既定24)、初期レーティング(既定1500)。

.PARAMETER ProvisionalStarts / ProvisionalFactor
  暫定期間の出走数(既定5)とKの倍率(既定2.0)。

.PARAMETER MinStarts
  上位一覧・検証で対象にする最低出走数(既定6)。

.PARAMETER IncludeBanei
  指定するとばんえいも含める。

.PARAMETER OutCsv
  全馬レーティングの出力先CSV。既定 tools\_elo_ratings.csv(.gitignore対象)。

.EXAMPLE
  .\elo-rating.ps1
  .\elo-rating.ps1 -From 2022-01-01 -K 28 -MinStarts 8
#>
[CmdletBinding()]
param(
    [string]$From = '2015-01-01',
    [string]$To = (Get-Date).ToString('yyyy-MM-dd'),
    [double]$K = 24,
    [double]$InitialRating = 1500,
    [int]$ProvisionalStarts = 5,
    [double]$ProvisionalFactor = 2.0,
    [int]$MinStarts = 6,
    [switch]$IncludeBanei,
    [string]$OutCsv
)
$ErrorActionPreference = 'Stop'
if (-not $OutCsv) { $OutCsv = Join-Path $PSScriptRoot '_elo_ratings.csv' }

# --- 接続文字列 ---
$appsettings = Join-Path $PSScriptRoot '..\共通\appsettings.json'
$connStr = (Get-Content $appsettings -Raw -Encoding UTF8 | ConvertFrom-Json).ConnectionStrings.DefaultConnection
if ([string]::IsNullOrWhiteSpace($connStr)) { throw 'DefaultConnection を取得できませんでした。' }

$baneiFilter = if ($IncludeBanei) { '' } else { "AND 開催場所 NOT LIKE '%ば'" }
$sql = @"
SELECT 開催日, 開催場所, レース番号, 馬名, 着順
FROM 競走結果
WHERE 着順 > 0 AND 開催日 BETWEEN @from AND @to $baneiFilter
ORDER BY 開催日, 開催場所, レース番号
"@

$ratings = @{}   # 馬名 -> 現レーティング
$starts  = @{}   # 馬名 -> 出走数
$lastDay = @{}   # 馬名 -> 最終出走日

# 検証カウンタ(レース前最上位レーティング馬の的中)
$evalRaces = 0; $winHit = 0; $top3Hit = 0
$totalRaces = 0; $totalRows = 0

# 1レース分を処理(着順配列・馬名配列)。先に検証→次に更新。
function Process-Race($names, $chakus) {
    $n = $names.Count
    if ($n -lt 2) { return }

    # レース前レーティング
    $pre = New-Object 'double[]' $n
    for ($i = 0; $i -lt $n; $i++) {
        $nm = $names[$i]
        $pre[$i] = if ($ratings.ContainsKey($nm)) { $ratings[$nm] } else { $InitialRating }
    }

    # --- 検証: 出走数が十分な馬の中でレース前最上位を選び、的中を見る ---
    $bestIdx = -1; $bestR = [double]::NegativeInfinity
    for ($i = 0; $i -lt $n; $i++) {
        $nm = $names[$i]
        $st = if ($starts.ContainsKey($nm)) { $starts[$nm] } else { 0 }
        if ($st -ge $script:MinStarts -and $pre[$i] -gt $bestR) { $bestR = $pre[$i]; $bestIdx = $i }
    }
    if ($bestIdx -ge 0) {
        $script:evalRaces++
        if ($chakus[$bestIdx] -eq 1) { $script:winHit++ }
        if ($chakus[$bestIdx] -le 3) { $script:top3Hit++ }
    }

    # --- 更新: 各馬の実際の勝ち数と期待勝ち数 ---
    for ($i = 0; $i -lt $n; $i++) {
        $actual = 0.0; $expected = 0.0
        for ($j = 0; $j -lt $n; $j++) {
            if ($i -eq $j) { continue }
            if ($chakus[$i] -lt $chakus[$j]) { $actual += 1.0 }
            elseif ($chakus[$i] -eq $chakus[$j]) { $actual += 0.5 }
            $expected += 1.0 / (1.0 + [Math]::Pow(10.0, ($pre[$j] - $pre[$i]) / 400.0))
        }
        $nm = $names[$i]
        $st = if ($starts.ContainsKey($nm)) { $starts[$nm] } else { 0 }
        $kEff = if ($st -lt $script:ProvisionalStarts) { $script:K * $script:ProvisionalFactor } else { $script:K }
        $delta = $kEff * ($actual - $expected) / ($n - 1)
        $ratings[$nm] = $pre[$i] + $delta
        $starts[$nm]  = $st + 1
    }
}

$conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
$conn.Open()
try {
    $cmd = $conn.CreateCommand(); $cmd.CommandTimeout = 600; $cmd.CommandText = $sql
    [void]$cmd.Parameters.AddWithValue('@from', $From)
    [void]$cmd.Parameters.AddWithValue('@to', $To)
    $r = $cmd.ExecuteReader()

    $curKey = $null
    $names = New-Object System.Collections.Generic.List[string]
    $chakus = New-Object System.Collections.Generic.List[int]
    $curDay = $null
    while ($r.Read()) {
        $totalRows++
        $day = $r.GetDateTime(0)
        $key = '{0:yyyyMMdd}_{1}_{2}' -f $day, $r.GetString(1), $r.GetInt32(2)
        if ($key -ne $curKey) {
            if ($curKey -ne $null) {
                Process-Race $names $chakus
                $totalRaces++
                foreach ($nm in $names) { $lastDay[$nm] = $curDay }
            }
            $curKey = $key; $curDay = $day
            $names.Clear(); $chakus.Clear()
        }
        $names.Add($r.GetString(3))
        $chakus.Add($r.GetInt32(4))
    }
    if ($curKey -ne $null) {
        Process-Race $names $chakus
        $totalRaces++
        foreach ($nm in $names) { $lastDay[$nm] = $curDay }
    }
    $r.Close()
}
finally { $conn.Close() }

# --- 出力 ---
$all = foreach ($nm in $ratings.Keys) {
    [PSCustomObject]@{
        馬名        = $nm
        レーティング = [Math]::Round($ratings[$nm], 1)
        出走数      = $starts[$nm]
        最終出走日   = $lastDay[$nm].ToString('yyyy-MM-dd')
    }
}
$all | Sort-Object レーティング -Descending | Export-Csv -Path $OutCsv -NoTypeInformation -Encoding UTF8

Write-Host ("処理: {0:N0}行 / {1:N0}レース / 馬{2:N0}頭" -f $totalRows, $totalRaces, $ratings.Count)
Write-Host ("対象: {0} ～ {1}  K={2} 初期={3} 暫定<{4}走(×{5})" -f $From, $To, $K, $InitialRating, $ProvisionalStarts, $ProvisionalFactor)
Write-Host ("出力: {0}" -f $OutCsv)
if ($evalRaces -gt 0) {
    Write-Host ("`n[検証] レース前レーティング最上位(出走{0}走以上)の成績  対象{1:N0}レース" -f $MinStarts, $evalRaces)
    Write-Host ("  勝率(1着)  : {0:P1}" -f ($winHit / $evalRaces))
    Write-Host ("  複勝率(3着内): {0:P1}" -f ($top3Hit / $evalRaces))
}
Write-Host "`n[現役上位30頭] (最終出走が直近・出走$MinStarts走以上)"
$cutoff = (Get-Date).AddMonths(-3).ToString('yyyy-MM-dd')
$all | Where-Object { $_.出走数 -ge $MinStarts -and $_.最終出走日 -ge $cutoff } |
    Sort-Object レーティング -Descending | Select-Object -First 30 |
    Format-Table 馬名, レーティング, 出走数, 最終出走日 -AutoSize | Out-String -Width 200 | Write-Host
