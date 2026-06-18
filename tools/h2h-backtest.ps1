<#
.SYNOPSIS
  race-h2h(共通対戦相手の着差比較)の予測力を過去レースで一括検証します。

.DESCRIPTION
  指定場・期間の各レースについて、出走馬を「直接対決→同レース共通相手→近走共通相手」
  の着差(勝ち時計比%で距離正規化)で比較し、最上位スコア馬を選定。実際の着順で
  勝率・複勝率を、払戻金(単勝)で回収率を集計します。

  改良(単発版からの差分):
   - 共通相手経由の推定は中央値で集約(弱敵大差などの外れに強い)
   - 1対戦あたりの着差は ±CapPct% で上限クリップ(破損/異常値対策)
   - 比較数が MinCompare 未満の馬は選定対象外(接続が薄い=信頼低)

  メモリに競走結果(全場・履歴含む)を一度だけ読み込み、各対象レースを評価します。
  ばんえいは除外。馬の同定は馬名。

.PARAMETER Venue / TestFrom / TestTo
  検証する開催場と対象期間(yyyy-MM-dd)。
.PARAMETER RecentN / RecentDays
  近走の対象(既定 直近5走/183日)。
.PARAMETER MinCompare
  選定に必要な最低比較数(既定4)。
.PARAMETER CapPct
  1対戦あたり着差(勝ち時計比%)の上限(既定8.0)。
#>
[CmdletBinding()]
param(
    [string]$Venue = '大井',
    [string]$TestFrom = '2025-09-01',
    [string]$TestTo = '2026-06-14',
    [int]$RecentN = 5,
    [int]$RecentDays = 183,
    [int]$MinCompare = 4,
    [double]$CapPct = 8.0
)
$ErrorActionPreference = 'Stop'
$appsettings = Join-Path $PSScriptRoot '..\共通\appsettings.json'
$connStr = (Get-Content $appsettings -Raw -Encoding UTF8 | ConvertFrom-Json).ConnectionStrings.DefaultConnection
$conn = New-Object System.Data.SqlClient.SqlConnection($connStr); $conn.Open()

function Median($arr) {
    $s = @($arr | Sort-Object); $n = $s.Count
    if ($n -eq 0) { return $null }
    if ($n % 2 -eq 1) { return [double]$s[[int](($n-1)/2)] }
    return ([double]$s[$n/2 - 1] + [double]$s[$n/2]) / 2.0
}

try {
    $histFrom = ([datetime]$TestFrom).AddDays(-$RecentDays).ToString('yyyy-MM-dd')

    # --- 全場の競走結果を一括ロード(履歴含む。ばんえい除外) ---
    Write-Host "競走結果をロード中..."
    $cmd = $conn.CreateCommand(); $cmd.CommandTimeout = 600
    $cmd.CommandText = @"
SELECT 開催場所, 開催日, レース番号, 馬番, 馬名, 着順, 走破時計
FROM 競走結果
WHERE 着順>0 AND 走破時計>0 AND 開催日>=@h AND 開催日<=@t AND 開催場所 NOT LIKE '%ば'
ORDER BY 開催日, レース番号
"@
    [void]$cmd.Parameters.AddWithValue('@h', $histFrom)
    [void]$cmd.Parameters.AddWithValue('@t', $TestTo)
    $r = $cmd.ExecuteReader()
    $races = @{}        # key -> @{ horses=@(@{n;t;c;u}); win=double; venue; date; rno }
    $horseRuns = @{}    # 馬名 -> list of @{date; key}
    while ($r.Read()) {
        $v = $r.GetString(0); $d = $r.GetDateTime(1); $rno = $r.GetInt32(2)
        $u = $r.GetInt32(3); $n = $r.GetString(4); $c = $r.GetInt32(5); $t = [double]$r.GetDecimal(6)
        $key = '{0}|{1:yyyy-MM-dd}|{2}' -f $v, $d, $rno
        if (-not $races.ContainsKey($key)) { $races[$key] = @{ horses = (New-Object System.Collections.Generic.List[object]); win = [double]::MaxValue; venue = $v; date = $d; rno = $rno } }
        $races[$key].horses.Add(@{ n = $n; t = $t; c = $c; u = $u })
        if ($t -lt $races[$key].win) { $races[$key].win = $t }
        if (-not $horseRuns.ContainsKey($n)) { $horseRuns[$n] = (New-Object System.Collections.Generic.List[object]) }
        $horseRuns[$n].Add(@{ date = $d; key = $key })
    }
    $r.Close()
    Write-Host ("  ロード完了: {0:N0}レース / {1:N0}頭" -f $races.Count, $horseRuns.Count)

    # --- 単勝払戻(対象場・期間) ---
    $cmd2 = $conn.CreateCommand(); $cmd2.CommandTimeout = 300
    $cmd2.CommandText = @"
SELECT 開催日, レース番号, 組番, 金額 FROM 払戻金
WHERE 開催場所=@v AND 馬券=N'単勝' AND 開催日>=@f AND 開催日<=@t
"@
    [void]$cmd2.Parameters.AddWithValue('@v', $Venue)
    [void]$cmd2.Parameters.AddWithValue('@f', $TestFrom)
    [void]$cmd2.Parameters.AddWithValue('@t', $TestTo)
    $r2 = $cmd2.ExecuteReader()
    $tansho = @{}   # key -> @{ uma -> payout(per100) }
    while ($r2.Read()) {
        $key = '{0}|{1:yyyy-MM-dd}|{2}' -f $Venue, $r2.GetDateTime(0), $r2.GetInt32(1)
        $uma = ($r2.GetValue(2)).ToString().Trim()
        if (-not $tansho.ContainsKey($key)) { $tansho[$key] = @{} }
        $tansho[$key][$uma] = [double]$r2.GetValue(3)
    }
    $r2.Close()

    # 対象レース(検証期間・指定場)
    $targets = $races.Values | Where-Object { $_.venue -eq $Venue -and $_.date -ge [datetime]$TestFrom -and $_.date -le [datetime]$TestTo } | Sort-Object date, rno

    $nRace = 0; $win = 0; $top3 = 0; $bets = 0; $ret = 0.0
    $favWin = 0   # 参考: 各レースで最も多く比較に勝った…ではなく単純ベース無し

    foreach ($race in $targets) {
        $field = @($race.horses | ForEach-Object { $_.n })
        if ($field.Count -lt 4) { continue }
        $fieldSet = @{}; $field | ForEach-Object { $fieldSet[$_] = $true }
        $td = $race.date

        # 各馬の近走margin( x -> 着差%リスト )
        $margin = @{}
        foreach ($a in $field) {
            $margin[$a] = @{}
            if (-not $horseRuns.ContainsKey($a)) { continue }
            $runs = @($horseRuns[$a] | Where-Object { $_.date -lt $td -and $_.date -ge $td.AddDays(-$RecentDays) } | Sort-Object date -Descending | Select-Object -First $RecentN)
            foreach ($run in $runs) {
                $rr = $races[$run.key]; $wt = $rr.win; if ($wt -le 0) { continue }
                $ta = ($rr.horses | Where-Object { $_.n -eq $a } | Select-Object -First 1).t
                foreach ($h in $rr.horses) {
                    if ($h.n -eq $a) { continue }
                    $rel = ($h.t - $ta) / $wt * 100.0
                    if ($rel -gt $CapPct) { $rel = $CapPct } elseif ($rel -lt -$CapPct) { $rel = -$CapPct }
                    if (-not $margin[$a].ContainsKey($h.n)) { $margin[$a][$h.n] = (New-Object System.Collections.Generic.List[double]) }
                    $margin[$a][$h.n].Add($rel)
                }
            }
        }
        # x -> 平均着差(中央値)
        $mavg = @{}
        foreach ($a in $field) { $mavg[$a] = @{}; foreach ($x in $margin[$a].Keys) { $mavg[$a][$x] = Median $margin[$a][$x] } }

        # ペア推定
        function PairM($a, $b) {
            $v = @()
            if ($mavg[$a].ContainsKey($b)) { $v += $mavg[$a][$b] }
            if ($mavg[$b].ContainsKey($a)) { $v += (-1.0 * $mavg[$b][$a]) }
            if ($v.Count -gt 0) { return (($v | Measure-Object -Average).Average) }
            $common = @($mavg[$a].Keys | Where-Object { $mavg[$b].ContainsKey($_) -and $_ -ne $a -and $_ -ne $b })
            if ($common.Count -eq 0) { return $null }
            $fc = @($common | Where-Object { $fieldSet.ContainsKey($_) })
            $use = if ($fc.Count -gt 0) { $fc } else { $common }
            $est = foreach ($c in $use) { $mavg[$a][$c] - $mavg[$b][$c] }
            return (Median $est)
        }

        $scores = @{}
        foreach ($a in $field) {
            $ms = @()
            foreach ($b in $field) { if ($a -ne $b) { $m = PairM $a $b; if ($null -ne $m) { $ms += $m } } }
            if ($ms.Count -ge $MinCompare) { $scores[$a] = ($ms | Measure-Object -Average).Average }
        }
        if ($scores.Count -eq 0) { continue }

        $nRace++
        $pick = ($scores.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1).Key
        $ph = $race.horses | Where-Object { $_.n -eq $pick } | Select-Object -First 1
        if ($ph.c -eq 1) { $win++ }
        if ($ph.c -le 3) { $top3++ }
        # 単勝回収
        $rkey = '{0}|{1:yyyy-MM-dd}|{2}' -f $race.venue, $race.date, $race.rno
        if ($tansho.ContainsKey($rkey)) {
            $bets++
            if ($ph.c -eq 1) {
                $pay = $tansho[$rkey]["$($ph.u)"]
                if ($pay) { $ret += $pay / 100.0 }
            }
        }
    }

    Write-Host ("`n=== h2h バックテスト ===")
    Write-Host ("場:{0}  期間:{1}〜{2}  近走{3}走/{4}日  最低比較{5}  上限{6}%" -f $Venue, $TestFrom, $TestTo, $RecentN, $RecentDays, $MinCompare, $CapPct)
    Write-Host ("対象レース: {0:N0}" -f $nRace)
    if ($nRace -gt 0) {
        Write-Host ("最上位スコア馬  勝率: {0:P1}  複勝率: {1:P1}" -f ($win/$nRace), ($top3/$nRace))
    }
    if ($bets -gt 0) {
        Write-Host ("単勝回収率: {0:P1}  (購入{1:N0}点)" -f ($ret/$bets), $bets)
    } else {
        Write-Host "単勝払戻データが見つからず回収率は算出不可"
    }
}
finally { $conn.Close() }
