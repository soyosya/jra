# JRA_OddsLoop スケジュールタスク用ラッパ。単複オッズループ(既定5分間隔/30分前開始)を起動。
#   パラメータ(oddsInterval)は RunnerControl の runner-params.json から読む。非開催日はループ即終了。
$ErrorActionPreference='Continue'
try { [Console]::OutputEncoding=[Text.Encoding]::UTF8 } catch {}
$log = 'C:\temp\jra_odds_loop_{0}.log' -f (Get-Date -Format 'yyyyMMdd')
$paramsPath='C:\jra\RunnerControl\runner-params.json'
$interval=5
if(Test-Path $paramsPath){ try{ $j=Get-Content $paramsPath -Raw -Encoding UTF8|ConvertFrom-Json; if($null -ne $j.oddsInterval){$interval=[int]$j.oddsInterval} }catch{} }
"[task] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') オッズループ起動 interval=$interval" | Out-File -FilePath $log -Encoding utf8
& (Join-Path $PSScriptRoot 'jra-odds-loop.ps1') -Date (Get-Date -Format 'yyyy-MM-dd') -OddsIntervalMin $interval *>> $log
