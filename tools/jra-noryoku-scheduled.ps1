<#
.SYNOPSIS
  タスクスケジューラから呼ぶ 能力ファクター収集ラッパー。当日(土)と翌日(日)を取得、ログ付き。
#>
$ErrorActionPreference='Continue'
$tools=$PSScriptRoot
$log=Join-Path $tools '_noryoku_scheduled.log'
("==== {0} 開始 ====" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) | Out-File $log -Append -Encoding utf8
try {
  $d0=(Get-Date).Date
  foreach($off in 0,1){
    $d=$d0.AddDays($off).ToString('yyyy-MM-dd')
    ("-- {0} --" -f $d) | Out-File $log -Append -Encoding utf8
    & "$tools\jra-keibabook-noryoku.ps1" -Date $d *>> $log
  }
  ("==== 正常終了 {0} ====" -f (Get-Date -Format 'HH:mm:ss')) | Out-File $log -Append -Encoding utf8
} catch {
  ("!! 例外: {0}" -f $_.Exception.Message) | Out-File $log -Append -Encoding utf8
}
