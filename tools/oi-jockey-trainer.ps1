<#
.SYNOPSIS
  大井の騎手・調教師を払戻ベース単勝回収率でランキングし、市場の過小/過大評価を炙り出します。

.DESCRIPTION
  レース情報(騎手/調教師)×競走結果(着順)×払戻金(単勝)を結合し、騎手別・調教師別に
  騎乗数/勝率/複勝率/単勝回収率を集計。回収率降順で表示します。

  読み方(重要):
    - 低騎乗・低勝率・超高回収(例: 200騎乗・勝率3%・回収240%)は高配当一発の分散で、信用できない。
    - 大サンプル(>=数百)かつ勝率も伴う高回収が「市場の過小評価」候補。
    - 高勝率なのに高回収の組は特に異質(通常は人気で回収が下がる)→ 過小評価の本命。
    - 必ず -Detail <名前> で年次分解と最高配当を確認し、単年の高回収や巨大配当一発を除外して判断する。

  既知(2024-01〜2026-06): 調教師 荒山勝 が高勝率(22→35%)×単回収~130%で3年安定・外れ値非依存=頑健な過小評価。
  立花伸は次点。騎手は大サンプルでの頑健な過小評価は乏しく、吉井章112%は2024の263倍一発依存(過学習)。

.PARAMETER From / To / Venue / MinRides / Top
  集計範囲と最小騎乗数・表示件数。既定 2024-01-01〜2026-06-14 / 大井 / 150 / 15。
.PARAMETER Detail
  指定した騎手または調教師名の年次分解(件数/勝率/単回収/最高単勝)を表示。

.EXAMPLE
  .\oi-jockey-trainer.ps1
  .\oi-jockey-trainer.ps1 -Detail 荒山勝
#>
[CmdletBinding()]
param(
    [string]$From = '2024-01-01',
    [string]$To   = '2026-06-14',
    [string]$Venue = '大井',
    [int]$MinRides = 150,
    [int]$Top = 15,
    [string]$Detail
)

$ErrorActionPreference = 'Stop'

$appsettings = Join-Path $PSScriptRoot '..\共通\appsettings.json'
if (-not (Test-Path $appsettings)) { throw "appsettings.json が見つかりません: $appsettings" }
$connStr = (Get-Content $appsettings -Raw -Encoding UTF8 | ConvertFrom-Json).ConnectionStrings.DefaultConnection
if ([string]::IsNullOrWhiteSpace($connStr)) { throw 'ConnectionStrings:DefaultConnection を取得できませんでした。' }

# rinfo別名(ri は Remove-Item 誤検知のため不可)。単勝払戻を各馬に結合。
$cte = @"
WITH rk AS (
  SELECT rinfo.騎手, rinfo.調教師, kk.着順, YEAR(rinfo.開催日) 年, tan.金額 単払
  FROM レース情報 rinfo
  JOIN 競走結果 kk ON kk.開催場所=rinfo.開催場所 AND kk.開催日=rinfo.開催日 AND kk.レース番号=rinfo.レース番号 AND kk.馬番=rinfo.馬番
  LEFT JOIN 払戻金 tan ON tan.開催場所=rinfo.開催場所 AND tan.開催日=rinfo.開催日 AND tan.レース番号=rinfo.レース番号 AND tan.馬券=N'単勝' AND LTRIM(RTRIM(tan.組番))=CAST(rinfo.馬番 AS nvarchar)
  WHERE rinfo.開催場所=@venue AND rinfo.開催日 BETWEEN @from AND @to AND kk.着順>0
)
"@

function Invoke-Sql([string]$tail, [hashtable]$extra) {
    $conn = New-Object System.Data.SqlClient.SqlConnection($connStr); $conn.Open()
    try {
        $cmd = $conn.CreateCommand(); $cmd.CommandTimeout = 240
        $cmd.CommandText = $cte + $tail
        [void]$cmd.Parameters.AddWithValue('@from', $From)
        [void]$cmd.Parameters.AddWithValue('@to', $To)
        [void]$cmd.Parameters.AddWithValue('@venue', $Venue)
        if ($extra) { foreach ($k in $extra.Keys) { [void]$cmd.Parameters.AddWithValue($k, $extra[$k]) } }
        $r = $cmd.ExecuteReader(); $rows = @()
        while ($r.Read()) { $o = [ordered]@{}; for ($i=0;$i -lt $r.FieldCount;$i++){ $o[$r.GetName($i)] = $r.GetValue($i) }; $rows += [PSCustomObject]$o }
        $r.Close(); return $rows
    } finally { $conn.Close() }
}

Write-Host ("対象: {0}  期間 {1}〜{2}  最小騎乗 {3}" -f $Venue, $From, $To, $MinRides)

if ($Detail) {
    $d = Invoke-Sql @"
SELECT 年, COUNT(*) 件, SUM(CASE WHEN 着順=1 THEN 1 ELSE 0 END) 勝, SUM(COALESCE(単払,0)) 単, MAX(単払) 最高
FROM rk WHERE 騎手=@name OR 調教師=@name GROUP BY 年 ORDER BY 年
"@ @{ '@name' = $Detail }
    Write-Host ("`n【年次分解】 {0}  (騎手/調教師いずれか一致)" -f $Detail)
    Write-Host '年    件数  勝率   単回収  最高単勝'
    foreach ($x in $d) { $n=[int]$x.件; Write-Host ("{0}  {1,4} {2,6:P1} {3,6:P1}  {4}" -f $x.年,$n,([int]$x.勝/$n),([double]$x.単/(100*$n)),$x.最高) }
    return
}

foreach ($role in @('騎手','調教師')) {
    $rows = Invoke-Sql @"
SELECT TOP $Top $role 名, COUNT(*) 件, SUM(CASE WHEN 着順=1 THEN 1 ELSE 0 END) 勝, SUM(CASE WHEN 着順<=3 THEN 1 ELSE 0 END) 複, SUM(COALESCE(単払,0)) 単
FROM rk GROUP BY $role HAVING COUNT(*)>=@min ORDER BY SUM(COALESCE(単払,0))*1.0/COUNT(*) DESC
"@ @{ '@min' = $MinRides }
    Write-Host ("`n=== {0} 単回収トップ{1} ===" -f $role, $Top)
    Write-Host '名前          件数  勝率   複勝率 単回収'
    foreach ($x in $rows) { $n=[int]$x.件; Write-Host ("{0,-12} {1,5} {2,6:P1} {3,6:P1} {4,6:P1}" -f $x.名,$n,([int]$x.勝/$n),([int]$x.複/$n),([double]$x.単/(100*$n))) }
}
Write-Host "`n※低騎乗・低勝率の高回収は分散(高配当一発)。-Detail <名前> で年次・最高配当を確認のこと。"
