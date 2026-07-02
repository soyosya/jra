<#
.SYNOPSIS
  指定日(既定=当日)の自動投票買目を、投票履歴(IPAT投票履歴)に『計画』として記録する(DryRun=実金ゼロ・ブラウザ非起動)。
  発走窓に関係なく全レースを対象=「通知のみ」運用で既に発走済のレースも含めて当日分を一括記録するバックフィル用。
.DESCRIPTION
  runner-params.json の式別/相手/金額/前半フラットで jra-export-bets により買目CSVを生成→各レースを IpatVote --mode DryRun で記録。
  weight-loop と同じ votedFile(C:\temp\jra_voted_<ymd>.txt)で二重記録を防止(ここで記録した分はループが再記録しない/その逆も)。
  危険軸除外(-SkipRisk)は買目CSV側で反映済。実金は一切動かない。
.PARAMETER Date  対象日 yyyy-MM-dd。既定=当日。
#>
[CmdletBinding()]
param([string]$Date=(Get-Date).ToString('yyyy-MM-dd'))
$ErrorActionPreference='Continue'
try { [Console]::OutputEncoding=[Text.Encoding]::UTF8 } catch {}
$tools=$PSScriptRoot
$exportBets=Join-Path $tools 'jra-export-bets.ps1'
$ipatExe=Join-Path (Split-Path $tools -Parent) 'IpatVote\bin\Release\net10.0\IpatVote.exe'
$ymd=($Date -replace '[^0-9]','')
$csvOut="C:\temp\ipat_bets_$ymd.csv"
$votedFile="C:\temp\jra_voted_$ymd.txt"
if(-not (Test-Path $ipatExe)){ Write-Output "IpatVote.exe が見つかりません: $ipatExe"; return }

# runner-params から買目パラメータ(無ければ既定)
$pp='C:\jra\RunnerControl\runner-params.json'; $bt='ワイド';$mt='流し';$pn=3;$st=100;$ff=0
if(Test-Path $pp){ try{ $j=Get-Content $pp -Raw -Encoding UTF8|ConvertFrom-Json; if($j.betType){$bt=$j.betType}; if($j.partners){$pn=[int]$j.partners}; if($j.stake){$st=[int]$j.stake}; if($null -ne $j.frontFlat){$ff=[int]$j.frontFlat} }catch{} }
Write-Output ("買目CSV生成: 式別=$bt 方式=$mt 相手=$pn 1点=$st 前半フラット=$ff")
& $exportBets -Date $Date -BetType $bt -Method $mt -Partners $pn -Stake $st -FrontFlat $ff -SkipRisk -Out $csvOut 2>&1 | Where-Object{ "$_" -match '買目CSV出力|EXPORT|R ' } | Select-Object -First 1 | ForEach-Object { Write-Output "  $_" }
if(-not (Test-Path $csvOut)){ Write-Output "買目CSV未生成(非開催日/データ未取得)。終了。"; return }

$all=@(Get-Content $csvOut); if($all.Count -le 1){ Write-Output "買目0件。終了。"; return }
$hdr=$all[0]
if(-not (Test-Path $votedFile)){ New-Item -ItemType File -Path $votedFile -Force | Out-Null }
$voted=@{}; foreach($l in (Get-Content $votedFile -ErrorAction SilentlyContinue)){ $t="$l".Trim(); if($t){ $voted[$t]=$true } }

$races=@($all | Select-Object -Skip 1 | ForEach-Object { $f=$_ -split ','; if($f.Count -ge 3){ "{0}|{1}" -f $f[1],$f[2] } } | Select-Object -Unique)
$rec=0; $skip=0
foreach($k in $races){
  if($voted.ContainsKey($k)){ $skip++; continue }
  $kp=$k.Split('|'); $kv=$kp[0]; $kr=$kp[1]
  $rows=@($hdr) + @($all | Select-Object -Skip 1 | Where-Object { $f=$_ -split ','; $f.Count -ge 3 -and $f[1] -eq $kv -and $f[2] -eq $kr })
  if($rows.Count -le 1){ $skip++; continue }
  $voteCsv="C:\temp\ipat_plan_{0}_{1}R.csv" -f $ymd,$kr
  [IO.File]::WriteAllLines($voteCsv,$rows,[Text.UTF8Encoding]::new($false))
  & $ipatExe $voteCsv '--mode' 'DryRun' '--date' $Date 2>&1 | Out-Null
  Add-Content -Path $votedFile -Value $k
  $rec++; Write-Output ("  📝 計画記録: {0}" -f $k)
}
Write-Output ("計画記録 完了: 記録{0}レース / スキップ{1}(既記録・買目なし)" -f $rec,$skip)
