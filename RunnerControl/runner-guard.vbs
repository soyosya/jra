' JRA RunnerControl 常駐ガードを完全に隠しウィンドウで起動する(0=非表示, False=待たない)
CreateObject("WScript.Shell").Run """C:\Program Files\PowerShell\7\pwsh.exe"" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ""C:\jra\RunnerControl\runner-guard.ps1""", 0, False
