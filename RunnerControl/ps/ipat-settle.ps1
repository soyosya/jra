# 全体収支「更新」ボタン(/api/ipat-settle)。IPAT投票履歴(未確定)を当日の払戻結果と突合して 確定/払戻 を最新化(jra-ipat-settle)。DB操作のみ・高速・ログイン不要。
$OutputEncoding=[Console]::OutputEncoding=[System.Text.Encoding]::UTF8
$ErrorActionPreference='SilentlyContinue'
$today=(Get-Date -Format 'yyyy-MM-dd')
$out=''
try{ $out = & 'C:\jra\tools\jra-ipat-settle.ps1' -Date $today 2>&1 | Out-String }catch{ $out="エラー: $($_.Exception.Message)" }
$m=[regex]::Match("$out",'SETTLED\|(\d+)\|HIT\|(\d+)\|PAY\|(\d+)')
if($m.Success){ [ordered]@{ok=$true;settled=[int]$m.Groups[1].Value;hit=[int]$m.Groups[2].Value;pay=[int]$m.Groups[3].Value;date=$today} | ConvertTo-Json -Compress }
elseif($out -match 'エラー'){ [ordered]@{ok=$false;message=("$out".Trim())} | ConvertTo-Json -Compress }
else{ [ordered]@{ok=$true;settled=0;hit=0;pay=0;date=$today;note='精算対象なし(結果未確定/新規なし)'} | ConvertTo-Json -Compress }
