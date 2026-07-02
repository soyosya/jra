<#
  自動予想ループ用の汎用通知送信。任意の件名/本文を Send-Mail(Graphメール+Teams) で送る。
  本文は -BodyFile(UTF8テキスト) 推奨(多行/日本語のクォート回避)。[[jra-auto-renotify]]
#>
param([Parameter(Mandatory)][string]$Subject, [string]$BodyFile='', [string]$Body='')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'mail-lib.ps1')
if($BodyFile){ if(Test-Path $BodyFile){ $Body=[IO.File]::ReadAllText($BodyFile,[Text.Encoding]::UTF8) } else { Write-Output "BodyFile無し: $BodyFile"; return } }
if(-not $Body){ Write-Output '本文空。送信中止。'; return }
try{ Send-Mail $Subject $Body; Write-Output "送信OK: $Subject" }catch{ Write-Output ("送信失敗: "+$_.Exception.Message) }
