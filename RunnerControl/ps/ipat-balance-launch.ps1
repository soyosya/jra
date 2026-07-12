# 「残高更新」ボタン(投票画面)のランチャ(/api/ipat-balance-refresh)。IpatVote balance をバックグラウンドで実行し状態をJSONに書く。
#  金融サイト(IPAT)へのログインはユーザーが更新ボタンを押した時のみ発生。二重起動はロックで防止。結果は ipat-balance-status.json / ipat-balance.txt。
$OutputEncoding=[Console]::OutputEncoding=[System.Text.Encoding]::UTF8
$ErrorActionPreference='SilentlyContinue'
$dir='C:\jra\RunnerControl'
$statusFile=Join-Path $dir 'ipat-balance-status.json'
$lock=Join-Path $dir 'ipat-balance.lock'
# 二重起動防止(180秒以内のロックは実行中とみなす)
if(Test-Path $lock){ $age=((Get-Date)-(Get-Item $lock).LastWriteTime).TotalSeconds; if($age -lt 180){ [ordered]@{started=$false;busy=$true;message='照会を実行中です…'} | ConvertTo-Json -Compress; return } }
Set-Content -Path $lock -Value (Get-Date -Format o) -Encoding UTF8
[ordered]@{state='running';done=$false;message='IPAT残高を照会中…(ログイン)'} | ConvertTo-Json -Compress | Set-Content -Path $statusFile -Encoding UTF8
# ワーカ(隠しdetached): IpatVote balance → 出力解析 → ipat-balance.txt + status.json
$worker=@'
$ErrorActionPreference='SilentlyContinue'
$dir='C:\jra\RunnerControl'
$exe='C:\jra\IpatVote\bin\Release\net10.0\IpatVote.exe'
$log='C:\jra\IpatVote\bin\Release\net10.0\ipatvote.log'
# 実行(標準出力は日本語エンコーディングがずれるので結果はUTF-8ログから読む)
try{ if(Test-Path $exe){ & $exe balance 2>&1 | Out-Null }else{ throw 'exe無し' } }catch{}
Start-Sleep -Milliseconds 500
$line=''
try{ $line = (Get-Content $log -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_ -match 'balance:' } | Select-Object -Last 1) }catch{}
$m=[regex]::Match("$line",'購入可能額\(残高\)\s*=\s*([\d,]+)')
if($m.Success){
  $amt=[int64](($m.Groups[1].Value) -replace '[^0-9]','')
  Set-Content -Path (Join-Path $dir 'ipat-balance.txt') -Value ((Get-Date -Format o)+"`t"+$amt) -Encoding UTF8
  [ordered]@{state='done';done=$true;balance=$amt;message='更新しました'} | ConvertTo-Json -Compress | Set-Content -Path (Join-Path $dir 'ipat-balance-status.json') -Encoding UTF8
}else{
  $msg= if($line -match 'ログイン不可'){'ログイン不可(認証/2段階認証)'}elseif($line -match '較正'){'残高セレクタ較正要'}elseif($line){"取得失敗: $line"}else{'残高を取得できませんでした(ログ未確認)'}
  [ordered]@{state='done';done=$true;balance=$null;message=$msg} | ConvertTo-Json -Compress | Set-Content -Path (Join-Path $dir 'ipat-balance-status.json') -Encoding UTF8
}
Remove-Item (Join-Path $dir 'ipat-balance.lock') -Force -ErrorAction SilentlyContinue
'@
$b64=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($worker))
Start-Process -FilePath 'C:\Program Files\PowerShell\7\pwsh.exe' -ArgumentList '-NoProfile','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-EncodedCommand',$b64 -WindowStyle Hidden
[ordered]@{started=$true;busy=$false;message='照会を開始しました'} | ConvertTo-Json -Compress
