<#
.SYNOPSIS
  指定レースの出走馬を、共通対戦相手の着差で相互比較してランク付けします。

.DESCRIPTION
  同一レース内の着差(走破時計差)は馬場・展開の影響を受けない条件フリーな比較になる、
  という性質を使い、直接対決→共通相手経由で各馬の力量差を推定します。

  比較の優先順位(各ペアA,B):
    1. 直接対決      … A,Bが過去に同じレースを走っていれば、その着差(時計差)
    2. 同レース共通相手 … 今回の出走馬Cで、A,B両方と過去対戦があれば A-B = (A-C) − (B-C)
    3. 近走共通相手   … 上が無ければ、A・Bそれぞれの近走(既定5走/183日)に共通する馬Dで同様に較正

  着差は「1馬身 = 0.2秒」で馬身換算(値が大きいほど速い=強い)。
  同一レース内の差を起点にするため馬場差補正は不要(共通相手の race 内で相殺)。

.PARAMETER Date / Venue / Race
  対象レースの 開催日(yyyy-MM-dd) / 開催場所 / レース番号。

.PARAMETER RecentN / RecentDays
  近走の対象(既定: 直近5走 かつ 183日以内)。

.EXAMPLE
  .\race-h2h.ps1 -Date 2026-06-12 -Venue 大井 -Race 9
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$Date,
    [Parameter(Mandatory)] [string]$Venue,
    [Parameter(Mandatory)] [int]$Race,
    [int]$RecentN = 5,
    [int]$RecentDays = 183
)
$ErrorActionPreference = 'Stop'
$SecPerLength = 0.2

$appsettings = Join-Path $PSScriptRoot '..\共通\appsettings.json'
$connStr = (Get-Content $appsettings -Raw -Encoding UTF8 | ConvertFrom-Json).ConnectionStrings.DefaultConnection
$conn = New-Object System.Data.SqlClient.SqlConnection($connStr); $conn.Open()

function Invoke-Rows([string]$sql, [hashtable]$p) {
    $cmd = $conn.CreateCommand(); $cmd.CommandTimeout = 120; $cmd.CommandText = $sql
    foreach ($k in $p.Keys) { [void]$cmd.Parameters.AddWithValue($k, $p[$k]) }
    $r = $cmd.ExecuteReader(); $rows = @()
    while ($r.Read()) { $o = @{}; for ($i = 0; $i -lt $r.FieldCount; $i++) { $o[$r.GetName($i)] = $r.GetValue($i) }; $rows += [PSCustomObject]$o }
    $r.Close(); return $rows
}

try {
    $dmin = ([datetime]$Date).AddDays(-$RecentDays).ToString('yyyy-MM-dd')

    # 出走馬(出馬表)+ 今回着順(過去レースなら検証用に表示)
    $entrants = Invoke-Rows @"
SELECT r.馬番, r.馬名, kk.着順 AS 今回着順
FROM レース情報 r
LEFT JOIN 競走結果 kk ON kk.開催場所=@v AND kk.開催日=@d AND kk.レース番号=@rno AND kk.馬番=r.馬番
WHERE r.開催場所=@v AND r.開催日=@d AND r.レース番号=@rno
ORDER BY r.馬番
"@ @{ '@v' = $Venue; '@d' = $Date; '@rno' = $Race }

    if ($entrants.Count -eq 0) { Write-Host "出走馬が見つかりません(出馬表未取得?): $Date $Venue ${Race}R"; return }
    $field = $entrants | ForEach-Object { [string]$_.馬名 }
    $fieldSet = @{}; $field | ForEach-Object { $fieldSet[$_] = $true }

    # 各馬の近走レースキーを収集(対象日より前・183日以内・走破時計あり、直近N走)
    $recentKeys = @{}   # 馬名 -> [keys]
    $allKeys = @{}      # key -> @{場;日;R}
    foreach ($h in $field) {
        $rk = Invoke-Rows @"
SELECT TOP ($RecentN) 開催場所, 開催日, レース番号
FROM 競走結果 WHERE 馬名=@h AND 開催日<@d AND 開催日>=@dmin AND 走破時計>0
ORDER BY 開催日 DESC, レース番号 DESC
"@ @{ '@h' = $h; '@d' = $Date; '@dmin' = $dmin }
        $keys = @()
        foreach ($x in $rk) {
            $k = '{0}|{1:yyyy-MM-dd}|{2}' -f $x.開催場所, $x.開催日, $x.レース番号
            $keys += $k
            if (-not $allKeys.ContainsKey($k)) { $allKeys[$k] = @{ v = [string]$x.開催場所; d = ([datetime]$x.開催日).ToString('yyyy-MM-dd'); r = [int]$x.レース番号 } }
        }
        $recentKeys[$h] = $keys
    }

    # 近走レースの全出走馬と走破時計を取得(キャッシュ)
    $raceRows = @{}     # key -> @{ 馬名 -> time(double) }
    foreach ($k in $allKeys.Keys) {
        $info = $allKeys[$k]
        $rows = Invoke-Rows @"
SELECT 馬名, 走破時計 FROM 競走結果
WHERE 開催場所=@v AND 開催日=@d AND レース番号=@rno AND 走破時計>0 AND 着順>0
"@ @{ '@v' = $info.v; '@d' = $info.d; '@rno' = $info.r }
        $m = @{}; foreach ($row in $rows) { $m[[string]$row.馬名] = [double]$row.走破時計 }
        $raceRows[$k] = $m
    }
    # レースごとの勝ち時計(最小時計)。距離・馬場の違いを正規化する分母に使う。
    $raceWinner = @{}
    foreach ($k in $raceRows.Keys) {
        $vals = @($raceRows[$k].Values)
        if ($vals.Count -gt 0) { $raceWinner[$k] = ($vals | Measure-Object -Minimum).Minimum }
    }

    # 各出走馬 A について、近走で対戦した相手Xとの着差(馬身, +=Aが速い) を平均
    $margin = @{}       # A -> @{ X -> 平均着差(馬身) }
    $meet   = @{}       # A -> @{ X -> 対戦回数 }
    foreach ($a in $field) {
        $margin[$a] = @{}; $meet[$a] = @{}
        foreach ($k in $recentKeys[$a]) {
            $rr = $raceRows[$k]; if (-not $rr.ContainsKey($a)) { continue }
            $ta = $rr[$a]; $wt = $raceWinner[$k]; if (-not $wt) { continue }
            foreach ($x in $rr.Keys) {
                if ($x -eq $a) { continue }
                # 着差を勝ち時計比(%)に正規化(距離・馬場非依存)。+ならAが速い。
                $rel = ($rr[$x] - $ta) / $wt * 100.0
                if (-not $margin[$a].ContainsKey($x)) { $margin[$a][$x] = 0.0; $meet[$a][$x] = 0 }
                $margin[$a][$x] += $rel; $meet[$a][$x] += 1
            }
        }
        foreach ($x in @($margin[$a].Keys)) { $margin[$a][$x] = $margin[$a][$x] / $meet[$a][$x] }
    }

    # ペア A,B の着差(馬身, +=Aが速い)を 直接→同レース共通→近走共通 で推定
    function Estimate-Pair([string]$a, [string]$b) {
        # 1. 直接
        $vals = @()
        if ($margin[$a].ContainsKey($b)) { $vals += $margin[$a][$b] }
        if ($margin[$b].ContainsKey($a)) { $vals += (-1.0 * $margin[$b][$a]) }
        if ($vals.Count -gt 0) { return @{ m = ($vals | Measure-Object -Average).Average; level = '直接'; n = $vals.Count } }

        # 共通相手(A,B双方が近走で対戦)
        $common = @($margin[$a].Keys | Where-Object { $margin[$b].ContainsKey($_) -and $_ -ne $a -and $_ -ne $b })
        if ($common.Count -eq 0) { return $null }
        # 2. 同レース出走馬を優先
        $fieldCommon = @($common | Where-Object { $fieldSet.ContainsKey($_) })
        $useC = if ($fieldCommon.Count -gt 0) { $fieldCommon } else { $common }
        $lvl = if ($fieldCommon.Count -gt 0) { '同レース経由' } else { '近走経由' }
        $est = foreach ($c in $useC) { $margin[$a][$c] - $margin[$b][$c] }
        return @{ m = ($est | Measure-Object -Average).Average; level = $lvl; n = $useC.Count }
    }

    # 各馬スコア = 他の全出走馬に対する推定着差の平均(+=速い)
    $result = foreach ($a in $field) {
        $ms = @(); $levels = @{}; $linked = 0
        foreach ($b in $field) {
            if ($a -eq $b) { continue }
            $e = Estimate-Pair $a $b
            if ($e -ne $null) { $ms += $e.m; $linked++; $levels[$e.level] = ($levels[$e.level] + 1) }
        }
        $ent = $entrants | Where-Object { [string]$_.馬名 -eq $a } | Select-Object -First 1
        [PSCustomObject]@{
            馬番   = [int]$ent.馬番
            馬名   = $a
            着     = if ($ent.今回着順 -is [DBNull] -or $null -eq $ent.今回着順) { '' } else { [int]$ent.今回着順 }
            スコア = if ($ms.Count -gt 0) { [Math]::Round(($ms | Measure-Object -Average).Average, 2) } else { $null }
            比較数 = $linked
            内訳   = (($levels.GetEnumerator() | Sort-Object Name | ForEach-Object { '{0}{1}' -f $_.Name, $_.Value }) -join '/')
        }
    }

    Write-Host ("対象: {0} {1} {2}R  近走={3}走/{4}日  (スコア=出走全馬への平均着差・勝ち時計比%・+が速い。約0.2%≒1馬身)" -f $Date, $Venue, $Race, $RecentN, $RecentDays)
    $result | Sort-Object { if ($null -eq $_.スコア) { -999 } else { $_.スコア } } -Descending |
        Format-Table 馬番, 馬名, 着, スコア, 比較数, 内訳 -AutoSize | Out-String -Width 200 | Write-Host
    $unlinked = $result | Where-Object { $null -eq $_.スコア }
    if ($unlinked) { Write-Host ('  ※接続なし(比較不能): ' + (($unlinked | ForEach-Object { $_.馬名 }) -join ', ')) }
}
finally { $conn.Close() }
