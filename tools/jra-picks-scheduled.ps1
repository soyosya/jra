<#
.SYNOPSIS
  タスクスケジューラから呼ぶ「翌日の買目 朝メール」一括ラッパー。
.DESCRIPTION
  前日夜に実行し、対象日(既定=翌日)について以下を順に行う:
    (1) fetch-compi  --date  … コンピ指数(軸/相手・出走馬)
    (2) fetch-danwa  --date  … 厩舎の話(印)
    (3) fetch-cyokyo --date  … 調教(矢印)
    (4) jra-fetch-shutuba … 出馬表(レース情報)を nittei+コンピ から充填
    (5) jra-card-full.ps1 -Notify … 地方競馬同形式の全馬カード(発走時刻順・印◎○△+調教矢印+コンピ順位(指数)+JRAフラグ)をメール送信
        ※出馬表が入らない場合のみ notify-jra-compi(コンピ簡易版)にフォールバック
  非開催日(対象日のコンピ指数が0件)なら (4)(5) をスキップしメール送信しない。
  ConsoleApp.exe は bin 配下を自動探索(Release優先→新しいもの)。全出力を _picks_scheduled.log へ。
.PARAMETER Date  対象日 yyyy-MM-dd。既定=翌日。
.PARAMETER Exe   ConsoleApp.exe を明示する場合に指定。
#>
[CmdletBinding()]
param([string]$Date=((Get-Date).AddDays(1).ToString('yyyy-MM-dd')),[string]$Exe)
$ErrorActionPreference='Continue'
$tools=$PSScriptRoot
$root=Split-Path $tools -Parent
$log=Join-Path $tools '_picks_scheduled.log'
function L($m){ ("{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$m) | Out-File $log -Append -Encoding utf8 }
L "==== 開始 対象日=$Date ===="

try {
  # ConsoleApp.exe 探索(Release優先→更新日時の新しいもの)
  if(-not $Exe -or -not (Test-Path $Exe)){
    $cands=Get-ChildItem -Path (Join-Path $root 'ConsoleApp\bin') -Recurse -Filter 'ConsoleApp.exe' -ErrorAction SilentlyContinue
    if(-not $cands){ throw "ConsoleApp.exe が見つかりません: $(Join-Path $root 'ConsoleApp\bin')" }
    $Exe=($cands | Sort-Object @{e={$_.FullName -match '\\Release\\'}},LastWriteTime -Descending | Select-Object -First 1).FullName
  }
  L "Exe=$Exe"

  foreach($cmd in 'fetch-compi','fetch-danwa','fetch-cyokyo'){
    L "-- $cmd --"
    & $Exe $cmd --date $Date *>> $log
  }

  # 非開催判定: 対象日のコンピ指数が無ければ以降をスキップ
  $cs=(Get-Content (Join-Path $root '共通\appsettings.json') -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
  $conn=New-Object System.Data.SqlClient.SqlConnection($cs);$conn.Open()
  $c=$conn.CreateCommand();$c.CommandText="SELECT COUNT(*) FROM コンピ指数 WHERE 開催日=@d";[void]$c.Parameters.AddWithValue('@d',$Date)
  $cnt=[int]$c.ExecuteScalar();$conn.Close()
  if($cnt -eq 0){ L "コンピ指数0件=非開催/未掲載。メール送信をスキップ。"; L "==== 終了(スキップ) ===="; return }
  L "コンピ指数 $cnt 行 → メール送信へ"

  # 出馬表(レース情報)を充填 → 入れば地方競馬同形式の全頭カード(jra-card-full)、入らなければコンピ簡易版にフォールバック。
  L "-- jra-fetch-shutuba(出馬表充填) --"
  try { & "$tools\jra-fetch-shutuba.ps1" -Date $Date *>> $log } catch { L "shutuba失敗(無視): $($_.Exception.Message)" }
  $conn2=New-Object System.Data.SqlClient.SqlConnection($cs);$conn2.Open()
  $c2=$conn2.CreateCommand();$c2.CommandText="SELECT COUNT(*) FROM レース情報 WHERE 開催日=@d";[void]$c2.Parameters.AddWithValue('@d',$Date)
  $shutuba=[int]$c2.ExecuteScalar();$conn2.Close()
  if($shutuba -gt 0){
    L "-- jra-card-full(地方競馬同形式・送信) 出馬表=$shutuba行 --"
    & "$tools\jra-card-full.ps1" -Date $Date -Notify *>> $log
  } else {
    L "-- 出馬表0=notify-jra-compi(コンピ簡易版)にフォールバック送信 --"
    & "$tools\notify-jra-compi.ps1" -Date $Date *>> $log
  }

  L "==== 正常終了 ===="
} catch {
  L "!! 例外: $($_.Exception.Message)"
}
