<#
.SYNOPSIS
  高知競馬の払戻ベース回収率検証。脚質別(今走/前走)に単勝・複勝を機械的に
  ¥100ずつ買った場合の回収率を、全頭買い基準と比較します。

.DESCRIPTION
  オッズ/人気はDB未保存のため、払戻金テーブル(馬券・組番・金額=¥100あたり払戻)
  から払戻ベース回収率を算出します。
    - 脚質は競走結果のコーナー通過順(early_pos=最初の非0コーナー)を頭数で相対化。
        逃げ: early_pos=1 / 先行: <=頭数*0.33 / 差し: <=頭数*0.66 / 追込: それ以降
    - 「今走脚質」… そのレースで実際に示した脚質(事前購入不可。バイアスの上限を示す)
    - 「前走脚質」… 直近の高知前走で示した脚質(事前購入可能=実戦的)
    - 回収率 = 的中時の払戻合計 / (100 * 賭け数)
  接続文字列は 共通/appsettings.json から読み込みます(無ければ既定接続)。

.PARAMETER From
  集計開始日(yyyy-MM-dd)。既定 2024-01-01。

.PARAMETER To
  集計終了日(yyyy-MM-dd, この日を含む)。既定は未指定(最新まで)。

.EXAMPLE
  .\kochi-roi.ps1 -From 2024-01-01
#>
[CmdletBinding()]
param(
    [string]$From = '2024-01-01',
    [string]$To   = ''
)
$ErrorActionPreference = 'Stop'

$appsettings = Join-Path $PSScriptRoot '..\共通\appsettings.json'
if (Test-Path $appsettings) {
    $connStr = (Get-Content $appsettings -Raw -Encoding UTF8 | ConvertFrom-Json).ConnectionStrings.DefaultConnection
}
if ([string]::IsNullOrWhiteSpace($connStr)) {
    $connStr = "Server=192.168.168.81\SQLEXPRESS;Database=中央競馬;User Id=sa;Password=$($env:KEIBA_SA_PASSWORD);TrustServerCertificate=True;Connect Timeout=10"
}

$toClause = if ([string]::IsNullOrWhiteSpace($To)) { '' } else { 'AND cur.開催日 <= @to' }

$sql = @"
DECLARE @venue nvarchar(10)=N'高知';

-- 高知 全レースの出走馬: early_pos / 頭数 / 馬名 / 距離
IF OBJECT_ID('tempdb..#r') IS NOT NULL DROP TABLE #r;
SELECT k.開催日, k.レース番号, k.馬番, k.着順, rinfo.馬名, rinfo.距離,
  COALESCE(NULLIF(k.一コーナー,0),NULLIF(k.二コーナー,0),NULLIF(k.三コーナー,0),NULLIF(k.四コーナー,0)) early_pos,
  cnt.頭数
INTO #r
FROM 競走結果 k
JOIN レース情報 rinfo ON rinfo.開催場所=@venue AND rinfo.開催日=k.開催日 AND rinfo.レース番号=k.レース番号 AND rinfo.馬番=k.馬番
CROSS APPLY (SELECT COUNT(*) 頭数 FROM 競走結果 k2
   WHERE k2.開催場所=@venue AND k2.開催日=k.開催日 AND k2.レース番号=k.レース番号 AND k2.着順>0) cnt
WHERE k.開催場所=@venue AND k.着順>0;
CREATE INDEX ix_r ON #r(馬名, 開催日, レース番号);

-- 各馬に単勝/複勝の払戻(¥100あたり)と前走脚質を付与
SELECT cur.開催日, cur.レース番号, cur.馬番, cur.着順, cur.距離, cur.頭数, cur.early_pos,
  prv.early_pos prev_early, prv.頭数 prev_頭数,
  ptan.金額 win_pay, pfuku.金額 place_pay
FROM #r cur
OUTER APPLY (
  SELECT TOP 1 p.early_pos, p.頭数 FROM #r p
  WHERE p.馬名=cur.馬名 AND (p.開催日<cur.開催日 OR (p.開催日=cur.開催日 AND p.レース番号<cur.レース番号))
  ORDER BY p.開催日 DESC, p.レース番号 DESC
) prv
LEFT JOIN 払戻金 ptan  ON ptan.開催場所=@venue AND ptan.開催日=cur.開催日 AND ptan.レース番号=cur.レース番号
   AND ptan.馬券=N'単勝' AND ptan.組番=CAST(cur.馬番 AS nvarchar(8))
LEFT JOIN 払戻金 pfuku ON pfuku.開催場所=@venue AND pfuku.開催日=cur.開催日 AND pfuku.レース番号=cur.レース番号
   AND pfuku.馬券=N'複勝' AND pfuku.組番=CAST(cur.馬番 AS nvarchar(8))
WHERE cur.開催日>=@from $toClause;
"@

function Style([object]$ep, [object]$n) {
    if ($ep -is [DBNull] -or $null -eq $ep) { return '?' }
    $e=[int]$ep; $h=[int]$n
    if ($e -eq 1) { return '逃げ' }
    elseif ($e -le $h*0.33) { return '先行' }
    elseif ($e -le $h*0.66) { return '差し' }
    else { return '追込' }
}

$conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
$conn.Open()
try {
    $cmd = $conn.CreateCommand(); $cmd.CommandTimeout=300; $cmd.CommandText=$sql
    [void]$cmd.Parameters.AddWithValue('@from', $From)
    if (-not [string]::IsNullOrWhiteSpace($To)) { [void]$cmd.Parameters.AddWithValue('@to', $To) }
    $r = $cmd.ExecuteReader()
    $rows = New-Object System.Collections.Generic.List[object]
    while ($r.Read()) {
        $rows.Add([PSCustomObject]@{
            dist     = [int]$r['距離']
            heads    = [int]$r['頭数']
            win      = ($r['着順'] -eq 1)
            curStyle = Style $r['early_pos'] $r['頭数']
            prevStyle= Style $r['prev_early'] $r['prev_頭数']
            winPay   = if ($r['win_pay'] -is [DBNull]) { 0 } else { [double]$r['win_pay'] }
            placePay = if ($r['place_pay'] -is [DBNull]) { 0 } else { [double]$r['place_pay'] }
            placed   = (-not ($r['place_pay'] -is [DBNull]))
        })
    }
    $r.Close()

    Write-Host ("高知 払戻ベース回収率  期間: {0} 〜 {1}  対象出走数: {2}" -f $From, ($(if($To){$To}else{'最新'})), $rows.Count)

    function Roi($subset, $label) {
        $n = $subset.Count
        if ($n -eq 0) { return }
        $winN  = ($subset | Where-Object win).Count
        $winPaySum = ($subset | Measure-Object winPay -Sum).Sum
        $plN   = ($subset | Where-Object placed).Count
        $plPaySum  = ($subset | Measure-Object placePay -Sum).Sum
        "{0,-18} 賭{1,6}  単勝[勝率{2,5:P1} 回収{3,6:P1}]  複勝[複勝率{4,5:P1} 回収{5,6:P1}]" -f `
            $label, $n, ($winN/$n), ($winPaySum/($n*100)), ($plN/$n), ($plPaySum/($n*100))
    }

    Write-Host "`n■ 全体(今走脚質ベース=事前購入不可・バイアスの上限)"
    Roi $rows '全頭買い'
    foreach ($s in '逃げ','先行','差し','追込') { Roi ($rows | Where-Object {$_.curStyle -eq $s}) "今走$s" }

    Write-Host "`n■ 実戦(前走脚質ベース=事前購入可能)"
    foreach ($s in '逃げ','先行','差し','追込') { Roi ($rows | Where-Object {$_.prevStyle -eq $s}) "前走$s" }
    Roi ($rows | Where-Object {$_.prevStyle -eq '逃げ' -or $_.prevStyle -eq '先行'}) '前走逃げ+先行'

    Write-Host "`n■ 距離別(今走 逃げ+先行 を単勝)"
    foreach ($d in 800,1000,1100,1300,1400,1600,1800,1900,2400) {
        $sub = $rows | Where-Object { $_.dist -eq $d -and ($_.curStyle -eq '逃げ' -or $_.curStyle -eq '先行') }
        if ($sub.Count -ge 30) { Roi $sub "${d}m 今走前々" }
    }
}
finally { $conn.Close() }
