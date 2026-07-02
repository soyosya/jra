<#
.SYNOPSIS
  netkeiba 競走結果バックフィルの駆動スクリプト。欠損年を OOS価値順(2024→2025→2022→2026)に取得。
.DESCRIPTION
  fetch-jra-range は未取得レースのみ取得=再開可能。各範囲を順に実行し、IPブロック時の例外でも
  次範囲へ進む。進捗は標準出力(=ログ)とDB件数で確認。1日約80秒(待機1500ms)。
  独立プロセスとして Start-Process で起動する想定(セッションを越えて継続)。
.PARAMETER DelayMs  レース間待機。既定1500。
#>
[CmdletBinding()] param([int]$DelayMs=1500)
$ErrorActionPreference='Continue'
$proj="C:\jra"
Set-Location $proj
$ranges=@(
  @{f='2024-01-01';t='2024-12-31'},
  @{f='2025-01-01';t='2025-12-31'},
  @{f='2022-01-01';t='2022-12-31'},
  @{f='2026-01-01';t='2026-06-30'}
)
"==== backfill 開始 $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===="
foreach($rg in $ranges){
  "---- 範囲 $($rg.f) 〜 $($rg.t) 開始 $(Get-Date -Format 'HH:mm:ss') ----"
  try {
    dotnet run --project ConsoleApp -c Release -- fetch-jra-range $rg.f $rg.t $DelayMs
  } catch {
    "!! 範囲 $($rg.f) で例外: $($_.Exception.Message) — 次へ"
  }
  "---- 範囲 $($rg.f) 終了 $(Get-Date -Format 'HH:mm:ss') ----"
}
"==== backfill 完了 $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===="
