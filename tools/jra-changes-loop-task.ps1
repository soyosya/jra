# JRA_ChangesLoop スケジュールタスク用ラッパ。変更情報ループ(3分間隔/30分前開始)を起動。
#   パラメータ(changeLeadMin/changeInterval)は RunnerControl の runner-params.json から読む。
#   非開催日はループ即終了(数秒)。レース情報に当日開催が無ければ抜ける。
$ErrorActionPreference='Continue'
try { [Console]::OutputEncoding=[Text.Encoding]::UTF8 } catch {}
$log = 'C:\temp\jra_changes_loop_{0}.log' -f (Get-Date -Format 'yyyyMMdd')
$paramsPath='C:\jra\RunnerControl\runner-params.json'
$lead=30; $interval=3
if(Test-Path $paramsPath){ try{ $j=Get-Content $paramsPath -Raw -Encoding UTF8|ConvertFrom-Json; if($null -ne $j.changeLeadMin){$lead=[int]$j.changeLeadMin}; if($null -ne $j.changeInterval){$interval=[int]$j.changeInterval} }catch{} }
"[task] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') 変更情報ループ起動 lead=$lead interval=$interval" | Out-File -FilePath $log -Encoding utf8
& (Join-Path $PSScriptRoot 'jra-changes-loop.ps1') -Date (Get-Date -Format 'yyyy-MM-dd') -ChangeLeadMin $lead -ChangeIntervalMin $interval *>> $log
