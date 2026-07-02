# JRAランナー起動/停止/再起動。停止=既存ランナー(孤児含む)kill+タスクEnd。起動=タスク実行。
param([ValidateSet('start','stop','restart')][string]$Action)
$OutputEncoding=[Console]::OutputEncoding=[System.Text.Encoding]::UTF8
$TASK='JRA_WeightLoop'
function StopRunners{
  $r=@(Get-CimInstance Win32_Process -Filter "Name='pwsh.exe' OR Name='powershell.exe'" | Where-Object { $_.CommandLine -match '-File\s+"?[^"]*jra-weight-loop(-task)?\.ps1' })
  foreach($x in $r){ try{ Stop-Process -Id $x.ProcessId -Force -ErrorAction Stop }catch{} }
  try{ Stop-ScheduledTask -TaskName $TASK -ErrorAction SilentlyContinue }catch{}
  return $r.Count
}
switch($Action){
  'stop'    { $n=StopRunners; Write-Output "停止しました(ランナー${n}本を停止)。" }
  'start'   { Start-ScheduledTask -TaskName $TASK; Write-Output "起動を要求しました(JRA_WeightLoopを実行)。早朝起動でも初R発走の40分前まで待機します。" }
  'restart' { $n=StopRunners; Start-Sleep -Seconds 2; Start-ScheduledTask -TaskName $TASK; Write-Output "再起動しました(ランナー${n}本停止→起動)。" }
  default   { Write-Output "不明なアクション" }
}
