# JRAランナー稼働状況をJSONで出力(/api/status)。読み取り専用。
$OutputEncoding=[Console]::OutputEncoding=[System.Text.Encoding]::UTF8  # パイプ経由の日本語(curMode等)CP932化け防止
$ErrorActionPreference='SilentlyContinue'
$TASK='JRA_WeightLoop'
$paramsPath='C:\jra\RunnerControl\runner-params.json'
$cs=(Get-Content 'C:\jra\共通\appsettings.json' -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
# 投票内容(実投票=IPAT投票履歴)の式別/軸/相手を読みやすく整形。順不同券種(馬連/枠連/ワイド/三連複)は「-」、着順あり(三連単/馬単/枠単)は「→」。フォーメーション(F:)/ボックス(BOX:)対応。
function FmtBet($bt,$axis,$aite){
  $a="$aite".Trim(); $ax=[int]("0"+"$axis")
  if($a -match '^F:'){ $segs=@($a.Substring(2) -split '/'); $lbl= if("$bt" -match '三連'){@('1着','2着','3着')}else{@('1着','2着')}; $parts=@(); for($i=0;$i -lt $segs.Count;$i++){ $l= if($i -lt $lbl.Count){$lbl[$i]}else{"($($i+1))"}; $parts+=("{0}:{1}" -f $l,($segs[$i] -replace '-',',')) }; return ("{0} フォメ {1}" -f $bt,($parts -join ' / ')) }
  if($a -match '^BOX:'){ return ("{0} BOX {1}" -f $bt,($a.Substring(4) -replace '-',',')) }
  if($ax -gt 0 -and $a){ $sep=$(if("$bt" -match '馬連|枠連|ワイド|三連複'){'-'}else{'→'}); return ("{0} {1}{2}{3}" -f $bt,$ax,$sep,$a) }
  if($ax -gt 0){ return ("{0} {1}" -f $bt,$ax) }
  return ("{0} {1}" -f $bt,($a -replace '-',','))
}
$allps = Get-CimInstance Win32_Process -Filter "Name='pwsh.exe' OR Name='powershell.exe'"
$runners = @($allps | Where-Object { $_.CommandLine -match '-File\s+"?[^"]*jra-weight-loop(-task)?\.ps1' } | ForEach-Object {
  $st=''; try{ $st=(Get-Process -Id $_.ProcessId -ErrorAction Stop).StartTime.ToString('HH:mm:ss') }catch{}
  [ordered]@{ pid=$_.ProcessId; start=$st }
})
# 現在のパラメータ
$cur=@{ mode='通知のみ'; betType='ワイド'; partners=3; stake=100 }
if(Test-Path $paramsPath){ try{ $j=Get-Content $paramsPath -Raw -Encoding UTF8 | ConvertFrom-Json
  foreach($k in 'mode','betType','partners','stake'){ if($null -ne $j.$k){ $cur[$k]=$j.$k } } }catch{} }
# 確定収支(dbo.IPAT投票履歴・確定済=1): 地方と同じく 自動(ランナー)/手動 を分け、全体(自動+手動)も表示。
#   ★対象=実投票'投票完了'のみ(計画/DryRun/通知のみのペーパーは実賭けでないので除外=実投票ゼロの日は0)。計画のペーパー成績は/historyで確認。的中=払戻金額>0。
$plToday=$null;$plRet=0;$plInv=0;$plHit=0;$plDone=0;$plTotal=$null              # 自動(ランナー)
$plManToday=$null;$plManRet=0;$plManInv=0;$plManHit=0;$plManDone=0;$plManTotal=$null  # 手動
$plAllToday=$null;$plAllRet=0;$plAllInv=0;$plAllHit=0;$plAllDone=0;$plAllTotal=$null  # 全体(自動+手動)
try{
  $cn=New-Object System.Data.SqlClient.SqlConnection $cs; $cn.Open()
  try{
    $today=(Get-Date -Format 'yyyy-MM-dd')
    function Get-PL($conn,$srcWhere,$dateWhere,$dayVal){
      $cmd=$conn.CreateCommand()
      $cmd.CommandText="SELECT ISNULL(SUM(投票金額),0) inv, ISNULL(SUM(CASE WHEN 払戻金額>0 THEN 払戻金額 ELSE 0 END),0) ret, ISNULL(SUM(CASE WHEN 払戻金額>0 THEN 1 ELSE 0 END),0) hit, COUNT(*) done FROM dbo.IPAT投票履歴 WHERE 結果=N'投票完了' AND 確定済=1 $dateWhere $srcWhere"
      if($dayVal){ [void]$cmd.Parameters.AddWithValue('@d',$dayVal) }
      $dt=New-Object System.Data.DataTable; (New-Object System.Data.SqlClient.SqlDataAdapter $cmd).Fill($dt)|Out-Null
      $r=$dt.Rows[0]; return [pscustomobject]@{ inv=[int]$r.inv; ret=[int]$r.ret; hit=[int]$r.hit; done=[int]$r.done; pl=([int]$r.ret-[int]$r.inv) }
    }
    $a=Get-PL $cn "AND 取得元<>N'手動'" "AND 開催日=@d" $today      # 自動 本日
    $plInv=$a.inv;$plRet=$a.ret;$plHit=$a.hit;$plDone=$a.done; if($a.done -gt 0){ $plToday=$a.pl }
    $at=Get-PL $cn "AND 取得元<>N'手動'" "AND 開催日=@d" $today;  $plTotal=$at.pl   # 自動 累計(当日のみ=ユーザ指定。過去の較正/テスト投票を含めない)
    $m=Get-PL $cn "AND 取得元=N'手動'" "AND 開催日=@d" $today        # 手動 本日
    $plManInv=$m.inv;$plManRet=$m.ret;$plManHit=$m.hit;$plManDone=$m.done; if($m.done -gt 0){ $plManToday=$m.pl }
    $mt=Get-PL $cn "AND 取得元=N'手動'" "AND 開催日=@d" $today; $plManTotal=$mt.pl   # 手動 累計(当日のみ)
    $al=Get-PL $cn "" "AND 開催日=@d" $today                         # 全体 本日
    $plAllInv=$al.inv;$plAllRet=$al.ret;$plAllHit=$al.hit;$plAllDone=$al.done; if($al.done -gt 0){ $plAllToday=$al.pl }
    $alt=Get-PL $cn "" "AND 開催日=@d" $today; $plAllTotal=$alt.pl                 # 全体 累計(当日のみ)
  } finally { $cn.Close() }
}catch{}
# --- 次レース + 投票内容(スマホで次に何をどう買うか一目) ---
$nextVenue=$null;$nextRace=$null;$nextPost=$null;$nextVoteAt=$null;$nextAxis=$null;$nextAxisName=$null;$nextPartners=$null;$nextBet=$null;$nextConf=$null
$today2=(Get-Date -Format 'yyyy-MM-dd')
try{
  $cn3=New-Object System.Data.SqlClient.SqlConnection $cs; $cn3.Open()
  try{
    $nowt=(Get-Date -Format 'HH:mm:ss')
    # 発走時刻>now の最短未発走レース(全開催場で最短)
    $c=$cn3.CreateCommand()
    $c.CommandText="SELECT TOP 1 開催場所 v,レース番号 r,発走時刻 p FROM レース情報 WHERE 開催日=@d AND 発走時刻 IS NOT NULL AND CONVERT(time,発走時刻)>CONVERT(time,@now) GROUP BY 開催場所,レース番号,発走時刻 ORDER BY 発走時刻"
    [void]$c.Parameters.AddWithValue('@d',$today2);[void]$c.Parameters.AddWithValue('@now',$nowt)
    $d1=New-Object System.Data.DataTable;(New-Object System.Data.SqlClient.SqlDataAdapter $c).Fill($d1)|Out-Null
    if($d1.Rows.Count){
      $row=$d1.Rows[0]; $nextVenue=[string]$row.v; $nextRace=[int]$row.r
      try{ $post=[datetime]$row.p; $nextPost=$post.ToString('HH:mm'); $vw=25; if(Test-Path $paramsPath){try{$jj=Get-Content $paramsPath -Raw -Encoding UTF8|ConvertFrom-Json; if($jj.voteWithin){$vw=[int]$jj.voteWithin}}catch{}}; $nextVoteAt=$post.AddMinutes(-$vw).ToString('HH:mm') }catch{}
      # 軸確度ラダー(コンピ指数 g12/range16/idx1)[[jra-chihou-signal-verify]]
      $c2=$cn3.CreateCommand()
      $c2.CommandText="SELECT 指数順位 rk,指数 val FROM (SELECT 指数順位,指数,ROW_NUMBER() OVER(PARTITION BY 馬番 ORDER BY 取得日時 DESC) rn FROM コンピ指数 WHERE 開催日=@d AND 開催場所=@v AND レース番号=@r AND 指数順位 IS NOT NULL) t WHERE rn=1"
      [void]$c2.Parameters.AddWithValue('@d',$today2);[void]$c2.Parameters.AddWithValue('@v',$nextVenue);[void]$c2.Parameters.AddWithValue('@r',$nextRace)
      $d2=New-Object System.Data.DataTable;(New-Object System.Data.SqlClient.SqlDataAdapter $c2).Fill($d2)|Out-Null
      $iv=@{}; foreach($rr in $d2.Rows){ if($rr.val -isnot [System.DBNull]){ $iv[[int]$rr.rk]=[int]$rr.val } }
      if($iv.ContainsKey(1) -and $iv.ContainsKey(2)){
        $g12=$iv[1]-$iv[2]; $r16= if($iv.ContainsKey(6)){$iv[1]-$iv[6]}else{$null}
        $nextConf= if($g12 -ge 10 -or ($null -ne $r16 -and $r16 -ge 33) -or $iv[1] -ge 88){'鉄板'}elseif($g12 -le 4 -and $iv[1] -lt 76){'警戒'}else{'標準'}
      }
      # 軸馬名(レース情報) - 買目読込後に馬番が決まるので後段で取得
    }
  } finally { $cn3.Close() }
}catch{}
# 買目(jra-weight-loopが生成するCSV)から軸/相手/券種
$betCsv="C:\temp\ipat_bets_$((Get-Date -Format 'yyyyMMdd')).csv"
if($nextVenue -and (Test-Path $betCsv)){
  try{
    $brow=Import-Csv $betCsv | Where-Object{ $_.venue -eq $nextVenue -and [int]$_.race -eq $nextRace } | Select-Object -First 1
    if($brow){
      $nextAxis=[string]$brow.axis
      $plist=@(($brow.partners -split '\|') | Where-Object{ $_ -ne '' })
      $nextPartners=($plist -join ' ')
      $nextBet="$($brow.bettype) 軸流し(相手$($plist.Count))"
    }
  }catch{}
}
# 軸馬名(レース情報)
if($nextVenue -and $nextAxis){
  try{
    $cn4=New-Object System.Data.SqlClient.SqlConnection $cs; $cn4.Open()
    $c3=$cn4.CreateCommand(); $c3.CommandText="SELECT TOP 1 馬名 FROM レース情報 WHERE 開催日=@d AND 開催場所=@v AND レース番号=@r AND 馬番=TRY_CAST(@u AS int)"
    [void]$c3.Parameters.AddWithValue('@d',$today2);[void]$c3.Parameters.AddWithValue('@v',$nextVenue);[void]$c3.Parameters.AddWithValue('@r',$nextRace);[void]$c3.Parameters.AddWithValue('@u',$nextAxis)
    $nm=$c3.ExecuteScalar(); if($null -ne $nm -and $nm -isnot [System.DBNull]){ $nextAxisName=[string]$nm }
    $cn4.Close()
  }catch{}
}
# 投票前後の出し分け: 次レースの実投票(dbo.IPAT投票履歴・「計画」=DryRun計画は除外)
$nextVoted=$false; $nextActual=$null
if($nextVenue){
  try{
    $cnv=New-Object System.Data.SqlClient.SqlConnection $cs; $cnv.Open()
    $cv=$cnv.CreateCommand()
    $cv.CommandText="SELECT 式別,軸馬番,相手馬番,ISNULL(投票金額,0) amt,結果 FROM dbo.IPAT投票履歴 WHERE 開催日=@d AND 開催場所=@v AND レース番号=@r AND (結果=N'投票完了' OR 結果 LIKE N'%見送り%' OR 結果 LIKE N'%失敗%' OR 結果 LIKE N'%締切%') ORDER BY 投票日時"
    [void]$cv.Parameters.AddWithValue('@d',$today2);[void]$cv.Parameters.AddWithValue('@v',$nextVenue);[void]$cv.Parameters.AddWithValue('@r',$nextRace)
    $dv=New-Object System.Data.DataTable;(New-Object System.Data.SqlClient.SqlDataAdapter $cv).Fill($dv)|Out-Null
    if($dv.Rows.Count){
      $nextVoted=$true; $sumAmt=0; $parts=@(); $resRank=@{'投票完了'=4;'締切'=3;'失敗'=2;'見送り'=1}; $bestR=0; $bestKey='見送り'
      foreach($vr in $dv.Rows){
        $sumAmt += [int]$vr.amt
        $parts += (FmtBet "$($vr.式別)" "$($vr.軸馬番)" "$($vr.相手馬番)")
        $rs=[string]$vr.結果
        $key= if($rs -eq '投票完了'){'投票完了'}elseif($rs -match '締切'){'締切'}elseif($rs -match '失敗'){'失敗'}else{'見送り'}
        if($resRank[$key] -gt $bestR){ $bestR=$resRank[$key]; $bestKey=$key }
      }
      $mark= switch($bestKey){ '投票完了'{'✅投票完了'} '締切'{'⏰締切'} '失敗'{'❌投票失敗'} default{'⏭見送り'} }
      $nextActual = (($parts | Select-Object -Unique) -join ' / ') + ("　計¥{0:N0}　{1}" -f $sumAmt,$mark)
    }
    $cnv.Close()
  }catch{}
}
$t=Get-ScheduledTask -TaskName $TASK
$i=Get-ScheduledTaskInfo -TaskName $TASK
[ordered]@{
  runnerCount=$runners.Count
  runners=$runners
  plToday=$plToday
  plRet=$plRet
  plInv=$plInv
  plHit=$plHit
  plDone=$plDone
  plTotal=$plTotal
  plManToday=$plManToday
  plManRet=$plManRet
  plManInv=$plManInv
  plManHit=$plManHit
  plManDone=$plManDone
  plManTotal=$plManTotal
  plAllToday=$plAllToday
  plAllRet=$plAllRet
  plAllInv=$plAllInv
  plAllHit=$plAllHit
  plAllDone=$plAllDone
  plAllTotal=$plAllTotal
  curMode=$cur.mode
  curBet=$cur.betType
  curPartners=$cur.partners
  curStake=$cur.stake
  taskState="$($t.State)"
  lastRun=$(if($i.LastRunTime){ $i.LastRunTime.ToString('MM-dd HH:mm') }else{''})
  lastResult=("0x{0:X}" -f $i.LastTaskResult)
  nextVenue=$nextVenue
  nextRace=$nextRace
  nextPost=$nextPost
  nextVoteAt=$nextVoteAt
  nextAxis=$nextAxis
  nextAxisName=$nextAxisName
  nextPartners=$nextPartners
  nextBet=$nextBet
  nextConf=$nextConf
  nextVoted=$nextVoted
  nextActual=$nextActual
  now=(Get-Date -Format 'HH:mm:ss')
} | ConvertTo-Json -Depth 5 -Compress
