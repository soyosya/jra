<#
.SYNOPSIS
  夜間の欠落補完バッチ。直近数日分の全テーブルを取り直し、コーナー通過順も補完します。

.DESCRIPTION
  ConsoleApp を2段で呼びます。
    1. fetch-range <今日-(Days-1)> <今日> full
       … 当日メニュー・変更情報・レース情報・競走結果・払戻金 の欠落/速報のみ分を取り直す
    2. backfill-corner-positions
       … 競走結果のコーナー通過順(一〜四コーナー)を成績ページから補完
  Windowsタスクスケジューラから powershell.exe -File で呼び出す想定です。

  exeパスは未指定なら、このスクリプトの2つ上(リポジトリ直下)から
  ConsoleApp\bin\**\ConsoleApp.exe を探索します(Release優先→Debug、更新日時が新しいもの)。
  本番で配置が異なる場合は -Exe で明示してください。

.PARAMETER Exe
  ConsoleApp.exe のフルパス。未指定なら自動探索。

.PARAMETER Days
  当日を含めて遡る日数(既定3=今日と前2日)。

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\nightly-backfill.ps1
  powershell -NoProfile -ExecutionPolicy Bypass -File .\nightly-backfill.ps1 -Exe "D:\app\ConsoleApp.exe" -Days 5
#>
[CmdletBinding()]
param(
    [string]$Exe,
    [int]$Days = 3
)
$ErrorActionPreference = 'Stop'

# --- exe の解決 ---
if ([string]::IsNullOrWhiteSpace($Exe)) {
    $repoRoot = Split-Path $PSScriptRoot -Parent   # tools の親 = リポジトリ直下
    $candidates = Get-ChildItem -Path (Join-Path $repoRoot 'ConsoleApp\bin') -Recurse -Filter 'ConsoleApp.exe' -ErrorAction SilentlyContinue
    if (-not $candidates) {
        throw "ConsoleApp.exe が見つかりません。-Exe で明示してください。探索元: $(Join-Path $repoRoot 'ConsoleApp\bin')"
    }
    # Release を優先し、次に更新日時が新しいものを採用
    $Exe = ($candidates |
        Sort-Object @{ Expression = { $_.FullName -match '\\Release\\' }; Descending = $true }, LastWriteTime -Descending |
        Select-Object -First 1).FullName
}
if (-not (Test-Path $Exe)) { throw "指定の ConsoleApp.exe が存在しません: $Exe" }

$workDir = Split-Path $Exe -Parent
$from = (Get-Date).AddDays(-([Math]::Max(1, $Days) - 1)).ToString('yyyy-MM-dd')
$to   = (Get-Date).ToString('yyyy-MM-dd')

Write-Host ("[nightly-backfill] exe={0}" -f $Exe)
Write-Host ("[nightly-backfill] 対象期間: {0} ～ {1} (full)" -f $from, $to)

# 1) 全テーブルの欠落補完(当日メニュー・変更情報・レース情報・競走結果・払戻金)
Write-Host "[nightly-backfill] STEP1: fetch-range full"
& $Exe fetch-range $from $to full
$rc1 = $LASTEXITCODE

# 2) コーナー通過順の補完
Write-Host "[nightly-backfill] STEP2: backfill-corner-positions"
& $Exe backfill-corner-positions
$rc2 = $LASTEXITCODE

Write-Host ("[nightly-backfill] 完了 (fetch-range rc={0}, backfill rc={1})" -f $rc1, $rc2)
if ($rc1 -ne 0 -or $rc2 -ne 0) { exit 1 }
