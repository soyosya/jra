<#
.SYNOPSIS
  タスクスケジューラから夜に呼ぶ「当日結果 取込→買目 突合」一括ラッパー。
.DESCRIPTION
  レース確定後(既定=当日19時想定)に、対象日(既定=当日)について順に行う:
    (1) fetch-jra-official <date> … JRA公式から競走結果+払戻金を即時取得(db.netkeibaの翌日ラグ回避)
    (2) jra-export-bets … その日の買目(三連複 軸1頭流し 相手5)をCSV化(コンピ/danwa/調教から決定的)
    (3) jra-reconcile-bets … 競走結果×払戻金で 軸複勝/単勝・三連複的中・回収を集計
    (4) 結果をメール送信(mail-lib/Graph)。買目0(非開催日)ならメールしない。
  全出力を _reconcile_scheduled.log へ。ConsoleApp.exe は bin 配下を自動探索(Release優先)。
.PARAMETER Date  対象日 yyyy-MM-dd。既定=当日。
.PARAMETER Exe   ConsoleApp.exe を明示する場合に指定。
.PARAMETER NoMail メール送信しない(ログ/レポートのみ)。
#>
[CmdletBinding()]
param([string]$Date=((Get-Date).ToString('yyyy-MM-dd')),[string]$Exe,[switch]$NoMail)
$ErrorActionPreference='Continue'
$tools=$PSScriptRoot
$root=Split-Path $tools -Parent
$log=Join-Path $tools '_reconcile_scheduled.log'
function L($m){ ("{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$m) | Tee-Object -FilePath $log -Append }
L "==== 開始 対象日=$Date ===="

try {
  # (1) ConsoleApp.exe 探索(Release優先→更新日時の新しいもの)
  if(-not $Exe -or -not (Test-Path $Exe)){
    $cands=Get-ChildItem -Path (Join-Path $root 'ConsoleApp\bin') -Recurse -Filter 'ConsoleApp.exe' -ErrorAction SilentlyContinue |
      Sort-Object @{e={$_.FullName -match 'Release'}},LastWriteTime -Descending
    if(-not $cands){ throw "ConsoleApp.exe が見つかりません: $(Join-Path $root 'ConsoleApp\bin')" }
    $Exe=$cands[0].FullName
  }
  L "exe=$Exe"

  L "(1) fetch-jra-official $Date"
  & $Exe fetch-jra-official $Date $Date 800 2>&1 | ForEach-Object { L "    $_" }

  # (1.5) IPAT投票履歴 精算: 取得した払戻金で 実投票/計画 の的中・払戻金額・確定済 を更新(→/history・収支に反映)
  L "(1.5) jra-ipat-settle $Date"
  & (Join-Path $tools 'jra-ipat-settle.ps1') -Date $Date 2>&1 | ForEach-Object { L "    $_" }

  # (2) 買目CSV生成
  $csv=Join-Path $env:TEMP ("ipat_bets_{0}.csv" -f ($Date -replace '-',''))
  L "(2) jra-export-bets -> $csv"
  & (Join-Path $tools 'jra-export-bets.ps1') -Date $Date -Out $csv 2>&1 | ForEach-Object { L "    $_" }
  $betRows = if(Test-Path $csv){ @(Get-Content $csv | Select-Object -Skip 1 | Where-Object{$_ -ne ''}).Count } else { 0 }
  if($betRows -eq 0){ L "買目0(非開催日/データ未取得)=突合・メールをスキップ。"; L "==== 終了 ===="; return }

  # (3) 突合
  L "(3) jra-reconcile-bets ($betRows レース)"
  $report = (& (Join-Path $tools 'jra-reconcile-bets.ps1') -BetsCsv $csv 2>&1 | Out-String)
  $report -split "`r?`n" | ForEach-Object { if($_ -ne ''){ L "    $_" } }
  $rep=Join-Path $tools ("_reconcile_{0}.txt" -f ($Date -replace '-',''))
  $report | Out-File $rep -Encoding utf8
  L "レポート: $rep"

  # (3b) 全馬・着順 振り返りカード(朝メール同形式+着順)を生成し、メール本文に結合する。
  L "(3b) jra-card-full -WithResult (振り返りカード)"
  $reviewFile=Join-Path $env:TEMP ("jra_review_{0}.txt" -f ($Date -replace '-',''))
  try { & (Join-Path $tools 'jra-card-full.ps1') -Date $Date -WithResult -ExportTxt $reviewFile 2>&1 | ForEach-Object { L "    $_" } } catch { L "振り返りカード生成失敗(無視): $($_.Exception.Message)" }
  $reviewTxt = if(Test-Path $reviewFile){ Get-Content $reviewFile -Raw -Encoding UTF8 } else { '' }

  # (4) メール(集計行を件名に / 本文=回収突合 + 着順付き振り返りカードを1通に結合)
  if($NoMail){ L "NoMail指定=送信せず。"; L "==== 終了 ===="; return }
  $sum = ($report -split "`r?`n" | Where-Object { $_ -match '回収率|的中' }) -join ' / '
  $roi = ([regex]::Match($report,'回収率\s*([\d\.]+)%')).Groups[1].Value
  try {
    . (Join-Path $tools 'mail-lib.ps1')
    $subj = "【中央競馬】買目突合+振り返り {0} 回収{1}%" -f $Date,$(if($roi){$roi}else{'-'})
    $body = "JRA 当日買目の競走結果突合 (三連複 軸1頭流し 相手5 / 1点100円)`n対象日: $Date`n`n$report"
    if($reviewTxt.Trim()){ $body += "`r`n`r`n" + ('═'*48) + "`r`n" + $reviewTxt }
    Send-Mail $subj $body
    L "メール送信: $subj"
  } catch { L "メール送信失敗(無視): $($_.Exception.Message)" }
}
catch { L "致命的エラー: $($_.Exception.Message)" }
L "==== 終了 ===="
