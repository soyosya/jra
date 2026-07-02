<#
.SYNOPSIS
  当日の馬体重を発走前から定期取得し、新しい馬体重が入ったレースの買目を作り直してコンソール＋メール通知する。
.DESCRIPTION
  - 初レース発走の LeadMin 分前から起動し、IntervalMin 分間隔で jra-fetch-weight.ps1(JRA公式出馬表)を実行して
    レース情報.馬体重/馬体重増減 を最新化。
  - 前回からの馬体重シグネチャ(レース内の 馬番:体重 並び)が変化したレースを検知し、その開催場の買目を
    jra-card.ps1 -ExportBets で作り直し → 変化したレースの「軸/相手」をコンソール出力＋メール送信。
  - 各開催場の最終レースの馬体重を取得したら(=全場の最終R揃ったら)終了。安全のため最終発走+EndBufferMin でも終了。
  ※買目は遠征(遠)・休み明け(休)×馬体重の相手絞りが体重発表後に作動する([[jra-ensei-weight]][[jra-layoff-weight]])。
.PARAMETER Date         既定=当日。
.PARAMETER IntervalMin  取得間隔(分)。既定20。
.PARAMETER LeadMin      初R発走の何分前から開始するか。既定20。
.PARAMETER NoMail       メールを送らずコンソール出力のみ(検証用)。
.PARAMETER DryRunWeights 馬体重をDB更新しない(jra-fetch-weight -DryRun)。検証用。
.PARAMETER Once         1サイクルだけ実行して終了(検証用)。
#>
[CmdletBinding()]
param(
  [string]$Date=(Get-Date).ToString('yyyy-MM-dd'),
  [int]$IntervalMin=20,
  [int]$LeadMin=20,
  [int]$EndBufferMin=30,
  [string]$BetType='ワイド',   # 買目CSVの式別。検証[[jra-bettype-roi]]: ワイド軸流しが回収最良(全年77-79%)・三連複は最劣(72%)
  [string]$Method='流し',       # 軸1頭流し(流し)
  [int]$Partners=3,             # 相手頭数。絞るほど回収↑(相手3=78.2%>5=77.6%>7=76.3%)・的中52%・300円/R
  [int]$Stake=100,              # 1点金額
  [int]$FrontFlat=0,            # 前半フラット: ≤このRを1点100円固定(0=無効)。[[keiba-ledger]]地方の前半フラット100円
  [switch]$AutoVote,            # ★実投票を有効化(既定OFF=通知のみ)。実金が動く
  [ValidateSet('DryRun','ConfirmStop','Auto')][string]$VoteMode='ConfirmStop', # 投票モード(既定=人が最終操作。無人化はAuto)
  [int]$VoteWithinMin=25,       # 発走の何分前から投票対象にするか(全頭体重発表後の窓)
  [int]$VoteBufferMin=1,        # 発走の何分前で締切とみなし投票しないか
  [switch]$NoMail,
  [switch]$DryRunWeights,
  [switch]$Once
)
$ErrorActionPreference='Stop'
try { [Console]::OutputEncoding=[Text.Encoding]::UTF8; $OutputEncoding=[Text.Encoding]::UTF8 } catch {}  # ログ(リダイレクト)を文字化けさせない
$tools=$PSScriptRoot
$fetch=Join-Path $tools 'jra-fetch-weight.ps1'
$card =Join-Path $tools 'jra-card.ps1'
$exportBets=Join-Path $tools 'jra-export-bets.ps1'
$ipatExe=Join-Path (Split-Path $tools -Parent) 'IpatVote\bin\Release\net10.0\IpatVote.exe'
$ymd=($Date -replace '[^0-9]','')
$csvOut="C:\temp\ipat_bets_$ymd.csv"
$votedFile="C:\temp\jra_voted_$ymd.txt"   # 投票済(venue|R)を永続化=二重投票防止(再起動でも保持)
. (Join-Path $tools 'mail-lib.ps1')
$cs=(Get-Content 'C:\jra\共通\appsettings.json' -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
function Rows($sql,$p){ $cn=New-Object System.Data.SqlClient.SqlConnection $cs;$cn.Open();$c=$cn.CreateCommand();$c.CommandText=$sql; if($p){foreach($k in $p.Keys){[void]$c.Parameters.AddWithValue($k,$p[$k])}}; $da=New-Object System.Data.SqlClient.SqlDataAdapter $c;$ds=New-Object System.Data.DataSet;$da.Fill($ds)|Out-Null;$cn.Close(); if($ds.Tables.Count){,$ds.Tables[0].Rows}else{,@()} }
function Log($m){ Write-Output ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'),$m) }

# --- 当日の開催/レース構成 ---
$meta=Rows "SELECT 開催場所,COUNT(DISTINCT レース番号) 最終R,MIN(発走時刻) 初発走,MAX(発走時刻) 終発走 FROM レース情報 WHERE 開催日=@d GROUP BY 開催場所" @{'@d'=$Date}
if(@($meta).Count -eq 0){ Log "対象なし($Date): レース情報が未取得。終了。"; return }
$venues=@($meta | ForEach-Object { [string]$_.開催場所 })
$finalR=@{}; foreach($m in $meta){ $finalR[[string]$m.開催場所]=[int]$m.最終R }
$firstPost=($meta | ForEach-Object { [datetime]$_.初発走 } | Sort-Object | Select-Object -First 1)
$lastPost =($meta | ForEach-Object { [datetime]$_.終発走 } | Sort-Object | Select-Object -Last 1)
$endBy=$lastPost.AddMinutes($EndBufferMin)
Log ("対象 {0} / 初発走 {1} / 最終発走 {2} / 終了予定 {3}" -f ($venues -join ','),$firstPost.ToString('HH:mm'),$lastPost.ToString('HH:mm'),$endBy.ToString('HH:mm'))
if($AutoVote){
  Log ("★自動投票 有効: モード={0} / 投票窓=発走{1}〜{2}分前 / 式別={3} {4} 相手{5} {6}円 / 投票済={7}" -f $VoteMode,$VoteWithinMin,$VoteBufferMin,$BetType,$Method,$Partners,$Stake,$votedFile)
  if($VoteMode -eq 'Auto'){ Log "  ⚠⚠ Auto=実課金・無人で実際に賭けます。1日上限20,000円(IpatVote側)・各レース1回のみ・体重全頭発表後のみ。" }
  if($VoteMode -eq 'ConfirmStop'){ Log "  ※ConfirmStop=各レースで購入ボタンを人が押す必要あり(フォアグラウンド実行向け。無人化はAuto)。" }
} else { Log "自動投票 無効(通知のみ)。実投票は行いませんが、自動投票の買目を投票履歴に『計画』として記録します(DryRun=実金ゼロ・ブラウザ非起動)。" }

# --- 初R LeadMin前まで待機 ---
$startAt=$firstPost.AddMinutes(-$LeadMin)
if((Get-Date) -lt $startAt -and -not $Once){
  $wait=[int]([Math]::Ceiling(($startAt-(Get-Date)).TotalSeconds))
  Log ("開始 {0} まで待機({1}秒)" -f $startAt.ToString('HH:mm'),$wait); Start-Sleep -Seconds $wait
}

$sig=@{}     # "venue|R" -> 馬体重シグネチャ(前回)
$cycle=0
while($true){
  $cycle++
  Log ("=== サイクル {0} 馬体重取得 ===" -f $cycle)
  try { $fargs=@('-NoProfile','-File',$fetch,'-Date',$Date); if($DryRunWeights){$fargs+='-DryRun'}; & pwsh @fargs 2>&1 | ForEach-Object { Log "  $_" } }
  catch { Log ("  馬体重取得エラー: {0}" -f $_.Exception.Message) }

  # 現在の馬体重シグネチャ(レース内 馬番:体重 並び)
  $cur=@{}
  foreach($r in (Rows "SELECT 開催場所,レース番号,馬番,TRY_CAST(馬体重 AS int) w FROM レース情報 WHERE 開催日=@d AND TRY_CAST(馬体重 AS int)>0 ORDER BY 開催場所,レース番号,馬番" @{'@d'=$Date})){
    $k="{0}|{1}" -f $r.開催場所,$r.レース番号
    $cur[$k]=([string]$cur[$k]) + ("{0}:{1}," -f $r.馬番,$r.w)
  }
  # 変化したレースを検知(開催場ごとに集約)
  $changedByVenue=@{}
  foreach($k in $cur.Keys){ if($sig[$k] -ne $cur[$k]){ $v=$k.Split('|')[0]; $rno=[int]$k.Split('|')[1]; if(-not $changedByVenue.ContainsKey($v)){$changedByVenue[$v]=@()}; $changedByVenue[$v]+=$rno; $sig[$k]=$cur[$k] } }

  if($changedByVenue.Count -gt 0){
    # 1) 買目CSVを自動生成(投票用・全開催場の最新。遠/休×馬体重の相手絞りが体重反映後に効く)
    try {
      $expOut = & pwsh -NoProfile -File $exportBets -Date $Date -BetType $BetType -Method $Method -Partners $Partners -Stake $Stake -FrontFlat $FrontFlat -SkipRisk -Out $csvOut 2>&1
      $okln = @($expOut | Where-Object { "$_" -match '買目CSV出力' })
      Log ("買目CSV生成: {0}" -f ($(if($okln.Count){$okln[0]}else{$csvOut})))
    } catch { Log ("買目CSV生成エラー: {0}" -f $_.Exception.Message) }

    # 2) 朝メール形式で最新買目を通知(馬体重更新のあった開催場の軸/相手)
    $legend="凡例: ◎堅軸/◎軸強=堅い本命, 安/安★=コンピ安定(確度up), 信=指数2連続上昇, ↗/↗↗=調教上昇, ◎軸弱・注危・△危・▼降・▽調・▽話=割引, ★=上り連続好調, 格=格上挑戦, ▽後/▽逃=脚質割引, ▽遠/△遠=遠征(関東⇄関西)×馬体重大幅減で相手割引, ▽休/△休=休み明け×馬体重減で相手割引"
    $body="中央競馬 馬体重反映 最新の軸/相手  {0}  (サイクル{1} {2})`n{3}`n`n買目CSV: {4}`n`n" -f $Date,$cycle,(Get-Date -Format 'HH:mm'),$legend,$csvOut
    # ★メールには毎回「全開催場」を掲載(更新があった会場だけだと、その回に体重変化が無い福島等が抜けて見える問題への対処)。
    #   今回どこが変わったかを一目で分かるように: 冒頭に更新サマリー + 変化したレース行に🔔マーカー + 会場見出しに更新有無。
    #   送信トリガーは従来通り「どこかで変化があった時」(changedByVenue.Count>0)。
    $chgSummary = (($changedByVenue.Keys | Sort-Object) | ForEach-Object { "{0}({1})" -f $_,(($changedByVenue[$_] | Sort-Object -Unique | ForEach-Object{"${_}R"}) -join ',') }) -join ' / '
    $body += "🔔 今回の更新: {0}`n（各買目の 🔔 が今回 馬体重が変化したレース）`n`n" -f $chgSummary
    foreach($v in ($venues | Sort-Object)){
      $chg=@($changedByVenue[$v] | Sort-Object -Unique)
      $tag= if($chg.Count){ "🔔更新 " + (($chg|ForEach-Object{"${_}R"}) -join ',') } else { "更新なし(最新の軸/相手)" }
      Log ("◆ {0}: {1} → 最新買目を抽出(朝メール形式)" -f $v,$tag)
      $nlines = & pwsh -NoProfile -File $card -Date $Date -Venue $v -Notify 2>$null
      # 別プロセス実行でjra-cardのWrite-Host見出し(=== / ---)も拾うため除外し、軸/相手行だけ残す
      $nlines = @($nlines | Where-Object { $t="$_".Trim(); $t -ne '' -and $t -notmatch '^===' -and $t -notmatch '^---' })
      # 変化したレース行の先頭に🔔(行頭の "NR" でレース番号を判定)。未変化行は字下げを揃える。
      $marked = @($nlines | ForEach-Object { $rm=[regex]::Match("$_",'^\s*(\d+)\s*R'); if($rm.Success -and ([int]$rm.Groups[1].Value -in $chg)){ "🔔 " + "$_".TrimStart() } else { "・ " + "$_".TrimStart() } })
      $head= if($chg.Count){ "🔔 " }else{ "　 " }
      $blk="{0}■ {1} ({2}R・{3})`n{4}" -f $head,$v,$nlines.Count,$tag,(($marked) -join "`n")
      Write-Output $blk; $body += $blk + "`n`n"
    }
    if(-not $NoMail){
      try { Send-Mail ("【中央競馬】馬体重反映 最新買目 {0} {1}" -f $Date,(Get-Date -Format 'HH:mm')) $body; Log "メール送信済" }
      catch { Log ("メール送信エラー: {0}" -f $_.Exception.Message) }
    } else { Log "(NoMail: メール送信スキップ)" }
  } else { Log "新しい馬体重なし(更新レースなし)" }

  # --- 自動投票/買目記録: 発走手前の窓で、全頭体重発表済みのレースを1回だけ処理。二重処理は永続ファイルで防止 ---
  #   AutoVote=実投票 / 通知のみ=DryRunで投票履歴に『計画』記録(実金ゼロ・ブラウザ非起動。ユーザ要望2026-06-27)。
  $recordOnly = -not $AutoVote
  $effMode = if($AutoVote){ $VoteMode } else { 'DryRun' }
  if($AutoVote -or $recordOnly){
    if(-not (Test-Path $votedFile)){ New-Item -ItemType File -Path $votedFile -Force | Out-Null }
    $voted=@{}; foreach($l in (Get-Content $votedFile -ErrorAction SilentlyContinue)){ $t="$l".Trim(); if($t){ $voted[$t]=$true } }
    # B/A9: レース単位 自動投票OFF + 取りやめ を毎サイクル フレッシュ読込(RunnerControl 5081のトグルが書く)。OFF/取りやめは投票対象外。
    $avDisabled=@{}; $avCancel=@{}
    try{ $af='C:\jra\RunnerControl\race-autovote.json'; if(Test-Path $af){ $aj=Get-Content $af -Raw -Encoding UTF8|ConvertFrom-Json; if($aj -and "$($aj.date)" -eq $Date){ foreach($x in @($aj.disabled)){ if($x){$avDisabled["$x"]=$true} } } } }catch{}
    try{ $cf='C:\jra\RunnerControl\race-cancel.json'; if(Test-Path $cf){ $cj=Get-Content $cf -Raw -Encoding UTF8|ConvertFrom-Json; if($cj -and "$($cj.date)" -eq $Date){ foreach($x in @($cj.cancelled)){ if($x){$avCancel["$x"]=$true} } } } }catch{}
    $nowT=Get-Date
    $eligible=@()
    foreach($r in (Rows "SELECT 開催場所,レース番号,発走時刻,COUNT(*) c,SUM(CASE WHEN TRY_CAST(馬体重 AS int)>0 THEN 1 ELSE 0 END) w FROM レース情報 WHERE 開催日=@d GROUP BY 開催場所,レース番号,発走時刻" @{'@d'=$Date})){
      if($r.発走時刻 -is [DBNull]){ continue }
      $k="{0}|{1}" -f $r.開催場所,$r.レース番号
      if($voted.ContainsKey($k)){ continue }
      $mins=([datetime]$r.発走時刻 - $nowT).TotalMinutes
      if($mins -le $VoteBufferMin -or $mins -gt $VoteWithinMin){ continue }   # 窓外/締切間際は対象外
      if([int]$r.w -lt [int]$r.c){ continue }                                  # 全頭の馬体重が出そろってから
      if($avDisabled.ContainsKey($k)){ Log ("自動投票OFF設定によりスキップ: {0}" -f $k); continue }   # B: /races トグルでOFF
      if($avCancel.ContainsKey($k)){ Log ("取りやめ設定によりスキップ: {0}" -f $k); continue }          # A9: 取りやめ(中止)
      $eligible+=$k
    }
    if($eligible.Count -gt 0 -and (Test-Path $csvOut)){
      # ★1レース=1回のIpatVote呼び出しに分離(毎回ログイン・新ブラウザ)。
      #   同一ブラウザで複数レース連続投票すると、前レースの実課金購入後に次レースが前画面状態で失敗する不具合を回避。
      $all=@(Get-Content $csvOut); $hdr=$all[0]
      foreach($k in $eligible){
        $kp=$k.Split('|'); $kv=$kp[0]; $kr=$kp[1]
        $rows=@($hdr) + @($all | Select-Object -Skip 1 | Where-Object { $f=$_ -split ','; $f.Count -ge 3 -and $f[1] -eq $kv -and $f[2] -eq $kr })
        if($rows.Count -le 1){ Log ("自動投票: {0} は買目CSVに無し(危険軸除外/相手不足等)→スキップ" -f $k); continue }
        $voteCsv="C:\temp\ipat_autovote_{0}_{1}_{2}R.csv" -f $ymd,(Get-Date -Format 'HHmmss'),$kr
        [IO.File]::WriteAllLines($voteCsv,$rows,[Text.UTF8Encoding]::new($false))
        Log ("{0} {1} → {2}" -f $(if($recordOnly){'📝 買目記録[計画]'}else{'◎ 自動投票['+$VoteMode+']'}),$k,$voteCsv)
        $okVote=$false; $outTxt=''
        if(Test-Path $ipatExe){
          try { $vout=@(& $ipatExe $voteCsv '--mode' $effMode '--date' $Date 2>&1); $vout | ForEach-Object { Log "    $_" }; $outTxt=($vout -join "`n") }
          catch { Log ("    自動投票エラー: {0}" -f $_.Exception.Message) }
          # 約定確認: Auto=「投票(実課金): 1レース」、当該レースが「投票完了」
          if($outTxt -match '投票\(実課金\):\s*1' -or $outTxt -match ([regex]::Escape("$kv$kr") + 'R:\s*投票完了')){ $okVote=$true }
        } else { Log ("    ⚠ IpatVote.exe が見つかりません: {0}" -f $ipatExe) }
        if($recordOnly -or $VoteMode -ne 'DryRun'){
          # at-most-once(二重処理防止): 試行/記録したら処理済みに記録。再処理しない(通知のみの計画も1レース1回)。
          Add-Content -Path $votedFile -Value $k
          if($VoteMode -eq 'Auto'){
            if($okVote){ Log ("    ✅ {0} 約定を確認(投票済み記録)" -f $k) }
            else { Log ("    ⚠⚠ {0} 未約定の可能性=取りこぼし。IPAT投票履歴で要確認(安全のため再投票しません)" -f $k) }
          }
        }
        Start-Sleep -Seconds 2
      }
    } else { if($eligible.Count -gt 0){ Log "自動投票: 買目CSV未生成のためスキップ" } }
  }

  # 終了判定: 通知のみでも買目記録のため最終Rの窓(発走25分前〜)まで回す必要があるので、時間(最終発走+EndBuffer)で終了する。
  #   (旧: 通知のみは「全場最終Rの馬体重が揃った」で早期終了していたが、買目の計画記録のため窓到達まで継続に変更。)
  if($Once){ Log "Once指定: 1サイクルで終了。"; break }
  if((Get-Date) -gt $endBy){ Log ("最終発走+{0}分を超過。終了。" -f $EndBufferMin); break }
  Log ("次サイクルまで {0}分待機" -f $IntervalMin); Start-Sleep -Seconds ($IntervalMin*60)
}
Log "ループ終了。"
