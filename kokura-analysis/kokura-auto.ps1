<#
  小倉 自動予想ループのヘルパ（共通仕様 [[jra-auto-renotify]] 準拠）。
  -Pending N: レースNが確定(着順≥3頭)かを判定→確定ならN結果(1-3着)＋次レースN+1の予想/買目を出力。
  -Notify   : 次レースN+1の「予想・結論・買い目フル通知」をメール+Teams(Send-Mail)で送信。通知のみ・実投票なし。
  軸/相手はjra-card -ExportBets(Write-Output=確実)、確度ヘッダは通常出力を 6>&1 で捕捉、根拠は出馬表(コ順/指/人気)。本文は文字列補間(-f回避)。
  買い目規律: (a)確度でステーク段階化 (b)人気1-2は相手から外さない (c)新馬/未勝利=高分散は3連複相手広め (e)基本ワイド軸流し。
#>
param([Parameter(Mandatory)][int]$Pending, [string]$Date='2026-06-28', [string]$Venue='小倉', [int]$MaxR=12, [switch]$Notify)
[Console]::OutputEncoding=[Text.Encoding]::UTF8
$ErrorActionPreference='Stop'
$cs=(Get-Content 'C:\jra\共通\appsettings.json' -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
$cn=New-Object System.Data.SqlClient.SqlConnection $cs;$cn.Open()
function Q($sql,$r){ $c=$cn.CreateCommand();$c.CommandText=$sql;[void]$c.Parameters.AddWithValue('@d',$Date);[void]$c.Parameters.AddWithValue('@v',$Venue);[void]$c.Parameters.AddWithValue('@r',$r);$dt=New-Object System.Data.DataTable;(New-Object System.Data.SqlClient.SqlDataAdapter $c).Fill($dt)|Out-Null;,$dt.Rows }

# 1) 確定判定
$fin=[int](Q 'SELECT COUNT(*) n FROM dbo.競走結果 WHERE 開催日=@d AND 開催場所=@v AND レース番号=@r AND TRY_CONVERT(int,着順)>0' $Pending)[0].n
if($fin -lt 3){ Write-Output "STATE=PENDING race=$Pending fin=$fin"; $cn.Close(); return }
Write-Output "STATE=CONFIRMED race=$Pending"

# 2) 直前結果(1-3着)
$res=Q @'
SELECT TRY_CONVERT(int,k.着順) ch, k.馬番, k.馬名, o.人気
FROM dbo.競走結果 k
LEFT JOIN (SELECT 馬番,人気,ROW_NUMBER() OVER(PARTITION BY 馬番 ORDER BY 日時 DESC) sn FROM dbo.リアルタイムオッズ WHERE 開催日=@d AND 開催場所=@v AND レース番号=@r) o ON o.馬番=k.馬番 AND o.sn=1
WHERE k.開催日=@d AND k.開催場所=@v AND k.レース番号=@r AND TRY_CONVERT(int,k.着順) BETWEEN 1 AND 3 ORDER BY ch
'@ $Pending
$resLine = ($res | ForEach-Object{ $p= if($_.人気 -is [DBNull]){'-'}else{$_.人気}; "$($_.ch)着 馬番$($_.馬番) $($_.馬名)($($p)人気)" }) -join '  '
Write-Output "RESULT race=$Pending : $resLine"

# 3) 次レース
$next=$Pending+1
if($next -gt $MaxR){ Write-Output "NONEXT (最終レース終了)"; $cn.Close(); return }
$hasNext=[int](Q 'SELECT COUNT(*) n FROM dbo.コンピ指数 WHERE 開催日=@d AND 開催場所=@v AND レース番号=@r' $next)[0].n
if($hasNext -lt 1){ Write-Output "NONEXT (race $next のコンピ無し)"; $cn.Close(); return }
$ent=Q @'
SELECT c.馬番, c.馬名, c.指数順位 ord, c.指数 idx, o.人気
FROM (SELECT 馬番,馬名,指数順位,指数,ROW_NUMBER() OVER(PARTITION BY 馬番 ORDER BY 取得日時 DESC) sn FROM dbo.コンピ指数 WHERE 開催日=@d AND 開催場所=@v AND レース番号=@r) c
LEFT JOIN (SELECT 馬番,人気,ROW_NUMBER() OVER(PARTITION BY 馬番 ORDER BY 日時 DESC) sn FROM dbo.リアルタイムオッズ WHERE 開催日=@d AND 開催場所=@v AND レース番号=@r) o ON o.馬番=c.馬番 AND o.sn=1
WHERE c.sn=1 ORDER BY c.指数順位
'@ $next
$dr=Q 'SELECT TOP 1 距離,コース種別,条件 FROM dbo.レース情報 WHERE 開催場所=@v AND 開催日=@d AND レース番号=@r' $next
$dist= if($dr.Count -gt 0 -and $dr[0].距離 -isnot [DBNull]){[int]$dr[0].距離}else{0}
$surf= if($dr.Count -gt 0){[string]$dr[0].コース種別}else{''}
$jouken= if($dr.Count -gt 0){[string]$dr[0].条件}else{''}
$cn.Close()
$info=@{}; foreach($x in $ent){ $info[[int]$x.馬番]=@{ord=[int]$x.ord; idx=$x.idx; pop=$(if($x.人気 -is [DBNull]){$null}else{[int]$x.人気}); name=[string]$x.馬名} }
$popNo=@{}; foreach($x in $ent){ if($x.人気 -isnot [DBNull]){ $popNo[[int]$x.人気]=[int]$x.馬番 } }
Write-Output "NEXTCARD race=$next ($dist$surf $jouken)"

# 軸/相手 = EXPORT(Write-Output確実)
$axisNo=0; $aiteNos=@()
$export = & 'C:\jra\tools\jra-card.ps1' -Date $Date -Venue $Venue -ExportBets -ExportN 6 2>$null | Out-String
foreach($ln in ($export -split "`n")){ if($ln -match ("^EXPORT\|{0}\|" -f $next)){ $f=$ln.Trim() -split '\|'; if($f.Count -ge 6){ $axisNo=[int]($f[3] -replace '\D'); $aiteNos=@(($f[5] -split ',')|Where-Object{$_ -match '^\d+$'}|ForEach-Object{[int]$_}) } } }
Write-Output "BETS axis=$axisNo aite=$($aiteNos -join ',')"
# 確度ヘッダ = 通常出力を 6>&1 で捕捉
$tier=''; $fukuPct=''
$full = & 'C:\jra\tools\jra-card.ps1' -Date $Date -Venue $Venue 2>$null 6>&1 | Out-String
foreach($ln in ($full -split "`n")){ if($ln -match ("--- {0}R " -f $next)){ if($ln -match '軸確度:(\S+?)[\s\]]'){$tier=$Matches[1]}; if($ln -match '複勝確率:([0-9]+)%'){$fukuPct=$Matches[1]}; break } }
if(-not $tier){ $tier='標準' }
Write-Output "HEADER tier=$tier fuku=$fukuPct"

$isHiVar = ($jouken -match '新馬|未勝利')
# (b)人気1-2を相手に必ず含める
foreach($pk in 1,2){ if($popNo.ContainsKey($pk)){ $pn=$popNo[$pk]; if($pn -ne $axisNo -and ($aiteNos -notcontains $pn)){ $aiteNos=@($pn)+$aiteNos } } }
$aiteNos=@($aiteNos | Where-Object{ $_ -ne $axisNo } | Select-Object -Unique)
# ○=先頭3 / △=次2
$maru=@($aiteNos | Select-Object -First 3); $sankaku=@($aiteNos | Select-Object -Skip 3 -First 2)

# (a)(c)(e) 買い方
$wN=3; $sN=5; $stake='本命中心・相手標準'
if($tier -match '鉄板'){ $wN=3; $sN=4; $stake='軸厚め・点数集中' }
elseif($tier -match '警戒'){ $wN=4; $sN=6; $stake='両頭軸+相手増し・小点数 or 見送り検討' }
if($isHiVar){ $sN=[Math]::Min($sN+2,$aiteNos.Count) }
$w=@($aiteNos | Select-Object -First $wN); $s=@($aiteNos | Select-Object -First ([Math]::Max($sN,3)))

function NN($no){ $n=[int]$no; $i=$info[$n]; if($i){ $p= if($i.pop){"$($i.pop)人気"}else{'-'}; "馬番$n $($i.name)（コ$($i.ord)位/$p/指$($i.idx)）" }else{ "馬番$n" } }

# 5) フル本文 + 送信
if($Notify){
  $tierTxt= if($fukuPct){"$tier(複勝$fukuPct%)"}else{$tier}
  if($tier -match '鉄板'){ $concl="本命◎馬番$axisNo は信頼度高。軸を厚く相手を絞り点数集中。" }
  elseif($tier -match '警戒'){ $concl="波乱含み。◎馬番$axisNo 単軸に固執せず相手を広げ小点数。妙味薄なら見送りも一案。" }
  else{ $concl="本命◎馬番$axisNo 中心、相手は標準の広さ。" }
  $note='人気1-2番は危険材料あっても相手に残す。' + $(if($isHiVar){'本レースは新馬/未勝利＝高分散につき3連複相手を広めにケア。'}else{''})
  $nl=[Environment]::NewLine
  $lines=@()
  $lines += "■ 小倉 ${next}R  ${dist}${surf} ${jouken}"
  $lines += "軸確度: $tierTxt"
  $lines += ""
  $lines += "【予想】"
  $lines += "◎軸  $(NN $axisNo)"
  foreach($n in $maru){ $lines += "○相手 $(NN $n)" }
  foreach($n in $sankaku){ $lines += "△    $(NN $n)" }
  $lines += ""
  $lines += "【結論】$concl $note 買い方=$stake。"
  $lines += ""
  $lines += "【買い目】(通知のみ・実投票なし)"
  $lines += " ・ワイド(軸流し): $axisNo → $($w -join '・')"
  if($tier -match '警戒' -and $maru.Count -ge 1){ $lines += " ・(警戒)両頭軸ワイド: $axisNo・$($maru[0]) → 相手$($s -join '・')" }
  $lines += " ・三連複(軸-相手): $axisNo - $($s -join '・')"
  $lines += ""
  $lines += "【直前 ${Pending}R 精算】$resLine"
  $body = $lines -join $nl
  try{
    . 'C:\jra\tools\mail-lib.ps1'
    Send-Mail "【小倉自動予想】${next}R 予想・買い目" $body
    Write-Output "NOTIFIED: 小倉 ${next}R フル通知 送信OK"
  }catch{ Write-Output ("NOTIFY_FAIL: "+$_.Exception.Message) }
  Write-Output "----- 本文 -----"
  Write-Output $body
}
