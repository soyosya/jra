<#
.SYNOPSIS
  タスクスケジューラから呼ぶ ピックアップ収集ラッパー。ログ付きで本体を実行。
#>
$ErrorActionPreference='Continue'
$tools=$PSScriptRoot
$log=Join-Path $tools '_pickup_scheduled.log'
("==== {0} 開始 ====" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) | Out-File $log -Append -Encoding utf8
try {
  & "$tools\jra-keibabook-pickup.ps1" -Categories best,hanasi,cyokyo,cpubest *>> $log
  ("==== 正常終了 {0} ====" -f (Get-Date -Format 'HH:mm:ss')) | Out-File $log -Append -Encoding utf8
} catch {
  ("!! 例外: {0}" -f $_.Exception.Message) | Out-File $log -Append -Encoding utf8
}
