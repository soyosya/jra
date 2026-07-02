# JRA_WeightLoop スケジュールタスク用ラッパ。
#   タスクは早朝に起動するが、ループ自身が「1Rの-LeadMin 分前」まで待機してから取得サイクル開始。
#   レース情報に当日開催が無ければループ即終了(非開催日は数秒で抜ける)。
#   ★パラメータは RunnerControl(Web制御盤・port5081)が書く runner-params.json から読む。
#     無ければ「通知のみ(実投票しない)」の安全既定で起動する。
#     mode=通知のみ → -AutoVote を付けない(=買目CSV生成＋通知のみ)。
#     mode=DryRun/ConfirmStop/Auto → -AutoVote -VoteMode <mode>(実投票が有効化。Auto=無人で実金が動く)。
$ErrorActionPreference='Continue'
try { [Console]::OutputEncoding=[Text.Encoding]::UTF8 } catch {}
$log = 'C:\temp\jra_weight_loop_{0}.log' -f (Get-Date -Format 'yyyyMMdd')
$paramsPath = 'C:\jra\RunnerControl\runner-params.json'
# 既定(通知のみ)
$P=@{ mode='通知のみ'; betType='ワイド'; partners=3; stake=100; lead=40; interval=20; voteWithin=25; noMail=$false; frontFlat=0 }
if(Test-Path $paramsPath){
  try{ $j=Get-Content $paramsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach($k in @($P.Keys)){ if($null -ne $j.$k){ $P[$k]=$j.$k } } }catch{}
}
$splat=@{
  Date       = (Get-Date -Format 'yyyy-MM-dd')
  LeadMin    = [int]$P.lead
  IntervalMin= [int]$P.interval
  BetType    = [string]$P.betType
  Partners   = [int]$P.partners
  Stake      = [int]$P.stake
  FrontFlat  = [int]$P.frontFlat
  VoteWithinMin = [int]$P.voteWithin
}
if($P.mode -ne '通知のみ'){ $splat['AutoVote']=$true; $splat['VoteMode']=[string]$P.mode }  # 実投票を有効化
if($P.noMail){ $splat['NoMail']=$true }
"[task] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') 起動 mode=$($P.mode) bet=$($P.betType) 相手=$($P.partners) 1点=$($P.stake) lead=$($P.lead)" | Out-File -FilePath $log -Encoding utf8
& (Join-Path $PSScriptRoot 'jra-weight-loop.ps1') @splat *>> $log
