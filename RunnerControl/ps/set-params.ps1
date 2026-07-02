# JRAランナーのパラメータを検証して runner-params.json に保存(/api/params POST)。
# JRA_WeightLoop タスクが起動する jra-weight-loop-task.ps1 がこのJSONを読んで jra-weight-loop.ps1 に渡す。
# タスク引数を書換えないのでSet-ScheduledTask(管理者)不要。
param(
  [string]$Mode='通知のみ',
  [string]$BetType='ワイド',
  [int]$Partners=3,
  [int]$Stake=100,
  [int]$Lead=40,
  [int]$Interval=20,
  [int]$VoteWithin=25,
  [int]$FrontFlat=0,
  [int]$ChangeLeadMin=30,
  [int]$ChangeInterval=3,
  [int]$OddsInterval=5,
  [switch]$NoMail
)
$OutputEncoding=[Console]::OutputEncoding=[System.Text.Encoding]::UTF8
$paramsPath='C:\jra\RunnerControl\runner-params.json'
if($Mode -notin '通知のみ','DryRun','ConfirmStop','Auto'){ Write-Output 'NG: Modeが不正(通知のみ/DryRun/ConfirmStop/Auto)'; exit 1 }
if($BetType -notin '複勝','ワイド','馬連','三連複','単勝'){ Write-Output 'NG: 式別が不正(複勝/ワイド/馬連/三連複/単勝)'; exit 1 }
if($Partners -lt 1 -or $Partners -gt 7){ Write-Output 'NG: 相手頭数範囲外(1-7)'; exit 1 }
if($Stake -lt 100 -or $Stake -gt 50000){ Write-Output 'NG: 1点金額範囲外(100-50000)'; exit 1 }
if($Lead -lt 0 -or $Lead -gt 120){ Write-Output 'NG: Lead範囲外(0-120)'; exit 1 }
if($Interval -lt 5 -or $Interval -gt 60){ Write-Output 'NG: 取得間隔範囲外(5-60)'; exit 1 }
if($VoteWithin -lt 5 -or $VoteWithin -gt 60){ Write-Output 'NG: 投票窓範囲外(5-60)'; exit 1 }
if($FrontFlat -lt 0 -or $FrontFlat -gt 12){ Write-Output 'NG: 前半フラットR範囲外(0-12)'; exit 1 }
if($ChangeLeadMin -lt 0 -or $ChangeLeadMin -gt 120){ Write-Output 'NG: 変更情報開始(分前)範囲外(0-120)'; exit 1 }
if($ChangeInterval -lt 1 -or $ChangeInterval -gt 30){ Write-Output 'NG: 変更情報取得間隔範囲外(1-30)'; exit 1 }
if($OddsInterval -lt 1 -or $OddsInterval -gt 30){ Write-Output 'NG: オッズ取得間隔範囲外(1-30)'; exit 1 }
$obj=[ordered]@{
  mode=$Mode; betType=$BetType; partners=$Partners; stake=$Stake;
  lead=$Lead; interval=$Interval; voteWithin=$VoteWithin; frontFlat=$FrontFlat;
  changeLeadMin=$ChangeLeadMin; changeInterval=$ChangeInterval; oddsInterval=$OddsInterval; noMail=[bool]$NoMail;
  savedAt=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
}
try{
  [IO.File]::WriteAllText($paramsPath, ($obj | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding($false)))
  Write-Output "OK: パラメータを保存しました(次回の起動/再起動から有効)。"
}catch{ Write-Output "NG: 保存失敗 $($_.Exception.Message)" }
