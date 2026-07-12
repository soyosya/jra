# JRA RunnerControl(5081) 常駐ガード。単一インスタンス(mutex)。5081がリッスンでなければJRA用exeを(再)起動し続ける。
# DB未起動等で起動失敗しても30秒毎に回復を試み続ける(Task SchedulerのRestartCount短時間リトライでは足りないケースの保険)。
# 地方(C:\keiba\...5080)には手を出さない(ExecutablePathでC:\jra\に限定)。
$ErrorActionPreference='SilentlyContinue'
$mtx = New-Object System.Threading.Mutex($false,'Global\JRA_RunnerControl_Guard')
if(-not $mtx.WaitOne(0)){ return }   # 既にガードが稼働中なら何もせず終了(多重起動防止)
try {
  $exe  = 'C:\jra\RunnerControl\bin\Release\net10.0\RunnerControl.exe'
  $port = 5081
  while($true){
    try {
      $listen = [bool](Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)
      if(-not $listen){
        # 5081を掴めていないJRA用の古いプロセスがいれば掃除(ハング対策)。地方(C:\keiba)は除外。
        Get-CimInstance Win32_Process -Filter "Name='RunnerControl.exe'" -ErrorAction SilentlyContinue |
          Where-Object { $_.ExecutablePath -like 'C:\jra\*' } |
          ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        Start-Sleep -Seconds 2
        Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe) -WindowStyle Hidden
        Start-Sleep -Seconds 12   # 起動待ち(次ループのリッスン判定まで猶予)
      }
    } catch {}
    Start-Sleep -Seconds 30
  }
} finally { $mtx.ReleaseMutex() }
