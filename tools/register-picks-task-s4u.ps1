<#
.SYNOPSIS
  JRA_PicksMail タスクを「ログオンしているかに関わらず実行」(S4U・パスワード保存不要)で登録/更新する。
  管理者権限が必要。下記の自己昇格ワンライナーから呼ぶ想定。
#>
$ErrorActionPreference='Stop'
$userId   = 'um790pro\suzukih'   # タスク実行アカウント(このPCの自分)
$ps       = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
$script   = 'C:\jra\tools\jra-picks-scheduled.ps1'

$act = New-ScheduledTaskAction -Execute $ps -Argument ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $script)
$trg = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Friday,Saturday,Sunday -At 8:00PM
$set = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 2) -MultipleInstances IgnoreNew
$prn = New-ScheduledTaskPrincipal -UserId $userId -LogonType S4U -RunLevel Limited

Register-ScheduledTask -TaskName 'JRA_PicksMail' -Action $act -Trigger $trg -Settings $set -Principal $prn `
  -Description '翌日JRA完全版買目を前日夜にメール送信。ログオフ中も実行(S4U)' -Force | Out-Null

$t = Get-ScheduledTask -TaskName 'JRA_PicksMail'
Write-Host ("登録OK: LogonType={0} UserId={1} State={2}" -f $t.Principal.LogonType,$t.Principal.UserId,$t.State)
Write-Host '金土日20:00に翌日分を実行(ログオフ中も可)。このウィンドウは閉じてOK。'
Start-Sleep -Seconds 5
