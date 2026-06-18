<#
.SYNOPSIS
  当日の推奨レースを「発走LeadMinutes分前」に: 最新オッズ取得 → ブレンド再分析(標準+コンピ0.5) → RakutenVoteで自動投票。
  既定は安全側 DryRun(無投票)。ConfirmStop=確認画面で停止し人が「投票する」。Auto=実課金。

.DESCRIPTION
  - 発走時刻は当日メニューから取得。各レースの T-Lead 分前に1回だけ処理(processed管理)。
  - 処理時: ConsoleApp fetch-odds(オッズ更新)→ compi-today-blend.ps1(該当場の推奨を再算出, -ExportBets)→
    そのレースが推奨なら1行CSVにして RakutenVote(--mode/--bettype/--partners/--budget)を起動。非推奨は見送り。
  - ブレンドの軸/相手はオッズ非依存(h2h/脚質/騎手/枠/コンピ)。T-5分の再分析は主に最終コンピ/取消反映とオッズ★妙味表示用。
  ※実課金は ConfirmStop/Auto のときのみ。まず DryRun で一日通して動作確認することを推奨。

.PARAMETER Date/LeadMinutes/Mode/Budget/BetType/Partners/PollSeconds/Venue/FieldMax/EhMin
#>
[CmdletBinding()]
param(
  [string]$Date = (Get-Date).ToString('yyyy-MM-dd'),
  [int]$LeadMinutes = 5,
  [ValidateSet('DryRun','ConfirmStop','Auto')][string]$Mode = 'DryRun',
  [int]$Budget = 10000,
  [string]$BetType = 'SanrenpukuNagashi',   # 3連複軸1頭流し / SanrentanMulti=三連単マルチ
  [int]$Partners = 3,
  [int]$PollSeconds = 60,
  [int]$ConfirmWaitSeconds = 180,   # ConfirmStop: 確認画面停止後『投票する』押下を待つ最大秒数(超過で見送り)
  [string]$Venue = '',
  [int]$FieldMax = 8,
  [double]$EhMin = 0.55
)
$ErrorActionPreference='Stop'
$root = Split-Path $PSScriptRoot -Parent
$appsettings = Join-Path $root '共通\appsettings.json'
$connStr=(Get-Content $appsettings -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
$consoleExe = Join-Path $root 'ConsoleApp\bin\Debug\net10.0\win-x64\ConsoleApp.exe'
$rakutenExe = Join-Path $root 'RakutenVote\bin\Debug\net10.0\RakutenVote.exe'
$blend = Join-Path $PSScriptRoot 'compi-today-blend.ps1'
$pwsh = (Get-Command powershell.exe).Source
$tmpDir = Join-Path $env:TEMP 'compi-autovote'; New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
foreach($p in @($consoleExe,$rakutenExe,$blend)){ if(-not (Test-Path $p)){ Write-Host "見つかりません: $p"; return } }

function Log($m){ Write-Host ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'),$m) }

# dbo.投票履歴 が無ければ作成(RakutenVote と同じ定義。推奨外を先に記録する場合に備える)
function Ensure-VoteHistoryTable {
  try{
    $cn=New-Object System.Data.SqlClient.SqlConnection $connStr; $cn.Open()
    try{ $cmd=$cn.CreateCommand(); $cmd.CommandText=@'
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'投票履歴')
CREATE TABLE dbo.投票履歴 (
  Id INT IDENTITY(1,1) CONSTRAINT PK_投票履歴 PRIMARY KEY,
  投票日時 DATETIME2 NOT NULL, 開催日 DATE NOT NULL, 場名 NVARCHAR(20) NOT NULL,
  レース番号 INT NOT NULL, 式別 NVARCHAR(10) NOT NULL, 軸馬番 INT NOT NULL,
  相手馬番 NVARCHAR(50) NOT NULL, 点数 INT NOT NULL, 一点金額 INT NOT NULL,
  投票金額 INT NOT NULL, モード NVARCHAR(20) NOT NULL, 結果 NVARCHAR(20) NOT NULL,
  確定済 BIT NOT NULL CONSTRAINT DF_投票履歴_確定済 DEFAULT(0),
  的中 BIT NULL, 払戻金 INT NULL, 確定日時 DATETIME2 NULL);
'@; [void]$cmd.ExecuteNonQuery() } finally { $cn.Close() }
  } catch { Log "  投票履歴テーブル確認に失敗: $($_.Exception.Message)" }
}

# 推奨外レースの would-be 買い目を 投票履歴 に記録(モード=分析/結果=推奨外、重複はスキップ)
function Record-Suggestless($r){
  try{
    $isFuku = ($BetType -match 'Sanrenpuku|3puku|三連複')
    $type = if($isFuku){'三連複'}else{'三連単'}
    $rel = @(@($r.p1,$r.p2,$r.p3,$r.p4) | Where-Object { "$_" -ne '' }) | Select-Object -First $Partners
    $relC = @($rel).Count
    $opp = (@($rel) -join ',')
    $pts = if($isFuku){ if($relC -ge 2){[int]($relC*($relC-1)/2)}else{0} } else { [int](3*$relC*($relC-1)) }
    $unit = 100; $amt = $pts*$unit
    $cn=New-Object System.Data.SqlClient.SqlConnection $connStr; $cn.Open()
    try{
      $cmd=$cn.CreateCommand()
      $cmd.CommandText=@'
IF NOT EXISTS (SELECT 1 FROM dbo.投票履歴 WHERE 開催日=@d AND 場名=@v AND レース番号=@r)
INSERT INTO dbo.投票履歴 (投票日時,開催日,場名,レース番号,式別,軸馬番,相手馬番,点数,一点金額,投票金額,モード,結果,確定済)
VALUES (SYSDATETIME(),@d,@v,@r,@type,@ax,@opp,@pts,@unit,@amt,N'分析',N'推奨外',0);
'@
      [void]$cmd.Parameters.AddWithValue('@d',[datetime]$r.date)
      [void]$cmd.Parameters.AddWithValue('@v',[string]$r.venue)
      [void]$cmd.Parameters.AddWithValue('@r',[int]$r.race)
      [void]$cmd.Parameters.AddWithValue('@type',$type)
      [void]$cmd.Parameters.AddWithValue('@ax',[int]$r.axis_uma)
      [void]$cmd.Parameters.AddWithValue('@opp',$opp)
      [void]$cmd.Parameters.AddWithValue('@pts',$pts)
      [void]$cmd.Parameters.AddWithValue('@unit',$unit)
      [void]$cmd.Parameters.AddWithValue('@amt',$amt)
      [void]$cmd.ExecuteNonQuery()
    } finally { $cn.Close() }
  } catch { Log "  推奨外の記録に失敗: $($_.Exception.Message)" }
}
Ensure-VoteHistoryTable

# 当日メニューから 発走時刻 を取得(場|R -> 発走DateTime)
$schedule=@{}
$cn=New-Object System.Data.SqlClient.SqlConnection $connStr; $cn.Open(); $cm=$cn.CreateCommand()
$venSql= if($Venue -ne ''){ "AND 開催場所=@v" } else { "AND 開催場所 NOT LIKE '%ば'" }
$cm.CommandText="SELECT 開催場所,レース番号,発走時刻 FROM 当日メニュー WHERE 開催日=@d AND レース番号>0 $venSql"
[void]$cm.Parameters.AddWithValue('@d',[datetime]$Date); if($Venue -ne ''){ [void]$cm.Parameters.AddWithValue('@v',$Venue) }
$r=$cm.ExecuteReader(); while($r.Read()){ $k='{0}|{1}' -f $r.GetString(0),$r.GetInt32(1); $schedule[$k]=[datetime]$r.GetValue(2) }; $r.Close(); $cn.Close()
if($schedule.Count -eq 0){ Log "当日メニューにレースがありません: $Date"; return }

Log ("自動投票ランナー開始: {0} / モード={1} / 券種={2} 相手{3}頭 / 1日上限{4:N0}円 / T-{5}分 / 全{6}レース" -f $Date,$Mode,$BetType,$Partners,$Budget,$LeadMinutes,$schedule.Count)
if($Mode -ne 'DryRun'){ Log "★実課金モード($Mode)。ConfirmStopは確認画面で停止→ブラウザで内容確認後『投票する』を押すだけ(コンソール操作不要、最大${ConfirmWaitSeconds}秒待機・超過で見送り)。" }

# 先行分析: 全場のレースを起動時に1回だけ blend(-ExportAll)で解析し、軸/相手/推奨をキャッシュ。
# 買い目はライブオッズに依存しないため、T-5では再分析せず投票のみ=遅延を解消する。
function Build-Plan {
  $p=@{}; $tot=0
  $venues = @($schedule.Keys | ForEach-Object { $_.Split('|')[0] } | Sort-Object -Unique)
  foreach($ven in $venues){
    $csv = Join-Path $tmpDir ("plan_{0}_{1}.csv" -f ($Date -replace '-',''),$ven)
    if(Test-Path $csv){ Remove-Item $csv -Force }
    try{ & $pwsh -NoProfile -ExecutionPolicy Bypass -File $blend -Date $Date -Venue $ven -FieldMax $FieldMax -EhMin $EhMin -ExportAll $csv 2>$null | Out-Null }catch{ Log "  先行分析失敗: $ven ($($_.Exception.Message))" }
    $c=0; if(Test-Path $csv){ foreach($r in (Import-Csv $csv -Encoding UTF8)){ $p["$($r.venue)|$([int]$r.race)"]=$r; $c++ } }
    Log ("  先行分析 {0}: {1}レース" -f $ven,$c); $tot+=$c
  }
  Log ("先行分析 完了: 計 {0}レース" -f $tot)
  return $p
}
Log "先行分析を実行します(全場・1回)..."
$plan = Build-Plan

$processed=@{}
while($true){
  $now=Get-Date
  $maxPost=($schedule.Values | Measure-Object -Maximum).Maximum
  if($now -gt $maxPost.AddMinutes(2)){ Log "本日の全レース発走済み。終了します。"; break }

  foreach($k in ($schedule.Keys | Sort-Object {$schedule[$_]})){
    if($processed.ContainsKey($k)){ continue }
    $post=$schedule[$k]; $trigger=$post.AddMinutes(-$LeadMinutes)
    if($now -lt $trigger){ continue }            # まだT-Lead前
    if($now -ge $post){ $processed[$k]=$true; continue }  # 発走済み=見送り
    $processed[$k]=$true
    $parts=$k.Split('|'); $ven=$parts[0]; $rno=[int]$parts[1]
    Log ("─ T-{0}分 {1} {2}R (発走 {3:HH:mm}) 処理開始" -f $LeadMinutes,$ven,$rno,$post)

    # 先行分析プランから取得。無ければ当該場のみその場で再分析(出馬表が後から確定した場合の保険)。
    $arow = $plan["$ven|$rno"]
    if(-not $arow){
      $csv = Join-Path $tmpDir ("plan_{0}_{1}.csv" -f ($Date -replace '-',''),$ven)
      try{ & $pwsh -NoProfile -ExecutionPolicy Bypass -File $blend -Date $Date -Venue $ven -FieldMax $FieldMax -EhMin $EhMin -ExportAll $csv 2>$null | Out-Null }catch{}
      if(Test-Path $csv){ foreach($r in (Import-Csv $csv -Encoding UTF8)){ $plan["$($r.venue)|$([int]$r.race)"]=$r } }
      $arow = $plan["$ven|$rno"]
    }
    if(-not $arow){ Log "  ${ven} ${rno}R は解析対象外(出走少等で見送り)"; Log ("─ {0} {1}R 処理終了" -f $ven,$rno); continue }

    if("$($arow.推奨)" -ne '1'){
      # 推奨外: 投票せず would-be 買い目を履歴に記録(重複スキップ)
      Record-Suggestless $arow
      Log ("  ${ven} ${rno}R は推奨外 → 履歴に記録(軸{0} 相手 {1},{2},{3} / 期待的中{4})" -f $arow.axis_uma,$arow.p1,$arow.p2,$arow.p3,$arow.eh)
      Log ("─ {0} {1}R 処理終了" -f $ven,$rno); continue
    }

    # 推奨: RakutenVote で投票(分析は先行済み=T-5は投票のみ)
    $one = Join-Path $tmpDir ("one_{0}_{1}_{2}.csv" -f ($Date -replace '-',''),$ven,$rno)
    $arow | Select-Object date,venue,race,axis_uma,axis_name,p1,p2,p3,p4 | Export-Csv -Path $one -NoTypeInformation -Encoding UTF8
    Log ("  推奨: 軸{0}({1}) 相手 {2},{3},{4}{5}" -f $arow.axis_uma,$arow.axis_name,$arow.p1,$arow.p2,$arow.p3,$(if($arow.p4){','+$arow.p4}else{''}))
    Log ("  RakutenVote 起動: mode=$Mode bettype=$BetType partners=$Partners budget=$Budget")
    try{ & $rakutenExe $one --mode $Mode --bettype $BetType --partners $Partners --budget $Budget --confirm-wait $ConfirmWaitSeconds --date $Date }
    catch{ Log "  RakutenVote 起動エラー: $($_.Exception.Message)" }
    Log ("─ {0} {1}R 処理終了" -f $ven,$rno)
  }
  Start-Sleep -Seconds $PollSeconds
}
Log "自動投票ランナー終了。"
