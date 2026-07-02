<#
.SYNOPSIS
  バックフィル後のクロスイヤーOOS評価を一括実行。特徴量を作り直し、学習年→検証年で評価。
.DESCRIPTION
  順序が重要: build-features が 特徴量 を全置換し v3/keshi/h2h を NULL に戻すため、
  (1)スピード指数 →(2)特徴量 →(3)V3更新 →(4)h2h更新(学習年+検証年)→(5)モデルOOS の順で実行。
.PARAMETER Year       検証年(OOS)。既定2024。
.PARAMETER TrainYears 学習年。既定 2023。
#>
[CmdletBinding()] param([int]$Year=2024,[int[]]$TrainYears=@(2023))
$ErrorActionPreference='Stop'
$tools=$PSScriptRoot
function Step($n,$msg){ Write-Host ("`n========== [{0}] {1}  {2} ==========" -f $n,$msg,(Get-Date -Format 'HH:mm:ss')) }
$sw=[System.Diagnostics.Stopwatch]::StartNew()

Step 1 "スピード指数 再構築(全年)"
& "$tools\jra-speed-figure.ps1" | Select-Object -Last 3

Step 2 "特徴量 materialize(全年)"
& "$tools\jra-build-features.ps1" | Select-Object -Last 2

Step 3 "danwa-V3 更新(全年)"
sqlcmd -S '192.168.168.81\SQLEXPRESS' -d '中央競馬' -U sa -P ($(((Get-Content 'C:\jra\共通\appsettings.json' -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection -split ';' | Where-Object{$_ -like 'Password=*'}) -replace '^Password=')) -C -f 65001 -W -i "$tools\jra-danwa-v3-all.sql" | Select-Object -Last 2

Step 4 "h2h 更新(学習年+検証年)"
foreach($y in (@($TrainYears)+$Year | Select-Object -Unique)){
  Write-Host "  -- h2h $y --"
  & "$tools\jra-h2h-features.ps1" -Year $y | Select-Object -Last 1
}

Step 5 "確率モデル OOS(学習 $($TrainYears -join '+') → 検証 $Year)"
Write-Host "`n--- pre-odds(市場非使用) ---"
& "$tools\jra-prob-model.ps1" -TestYear $Year -TrainYears $TrainYears
Write-Host "`n--- +market(市場含意勝率を特徴に追加) ---"
& "$tools\jra-prob-model.ps1" -TestYear $Year -TrainYears $TrainYears -UseMarket

Write-Host ("`n========== OOS完了  経過 {0}分 ==========" -f [math]::Round($sw.Elapsed.TotalMinutes,1))
