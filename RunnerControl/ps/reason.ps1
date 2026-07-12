# 指定レースの「買目選定理由」(JSON)。JRA版。読み取り専用。
#  買目(buyme.ps1)の全頭データ(コンピ/h2h/予測脚質/Δ指数/現オッズ/確定着順/印/調教・厩舎定性)に、
#  jra-card の評価ラベル(適/不適/⚡単/危/前敗/長休/完 等=選定・消しの理由)と総合スコアを重ねる。
#  + 予想突合(◎システム軸/コンピ1位/1番人気→着) + IPAT投票結果。
#  源: buyme.ps1 / jra-card.ps1 -ExportBets -ExportHorses(HORSE|R|馬番|評価|コンピ|総合 / EXPORT|R|距離|軸|軸評価|相手)
#      → 場単位キャッシュ C:\temp\jra_reason_<ymd>_<場>.json(確定 or 20分以内は再利用=jra-card再実行を回避)
param([string]$Venue='',[int]$Race=0,[string]$Date='')
$OutputEncoding=[Console]::OutputEncoding=[System.Text.Encoding]::UTF8
$ErrorActionPreference='SilentlyContinue'
if([string]::IsNullOrWhiteSpace($Venue) -or $Race -le 0){ [ordered]@{ error='venue/race が必要です' } | ConvertTo-Json -Compress; return }
$date= if($Date){$Date}else{(Get-Date -Format 'yyyy-MM-dd')}; $ymd=($date -replace '[^0-9]','')
$psdir=$PSScriptRoot

# 1) 買目全頭データ(既存buyme.ps1を流用)
$bm=$null
try{ $bmRaw = & (Join-Path $psdir 'buyme.ps1') -Venue $Venue -Race $Race -Date $date | Out-String; if($bmRaw){ $bm = $bmRaw | ConvertFrom-Json } }catch{}
if($null -eq $bm -or $bm.error){ [ordered]@{ error='買目データ取得失敗(コンピ/出馬未取得の可能性)'; date=$date; venue=$Venue; race=$Race } | ConvertTo-Json -Compress; return }

# 2) jra-card 評価/総合(バックグラウンドのウォーマーが書いた場単位キャッシュを読むだけ。同期でjra-cardは実行しない=157秒回避)
$cacheF="C:\temp\jra_reason_${ymd}_${Venue}.json"
$card=$null; $cardSrc='none'
if(Test-Path $cacheF){ try{ $card=Get-Content $cacheF -Raw -Encoding UTF8|ConvertFrom-Json; $cardSrc='cache' }catch{} }
# 対象レースの評価マップ(馬番文字列→{eval,compi,sougou}) + 軸/相手
$evalOf=@{}; $axisU2=''; $axisLab=''; $partners=''
if($card){ $prop=$card.PSObject.Properties["$Race"]; if($prop){ $rc=$prop.Value
  if($rc.axis){$axisU2="$($rc.axis)"}; if($rc.axisLab){$axisLab="$($rc.axisLab)"}; if($rc.partners){$partners="$($rc.partners)"}
  if($rc.horses){ foreach($pp in $rc.horses.PSObject.Properties){ $evalOf[$pp.Name]=$pp.Value } } } }

# 3) マージ + 予想突合
$chOf=@{}; foreach($h in $bm.horses){ $chOf[[int]$h.uma]=[int]("0"+"$($h.chaku)") }
$axisU=0; foreach($h in $bm.horses){ if("$($h.mark)" -eq '◎'){ $axisU=[int]$h.uma; break } }
if($axisU -eq 0 -and $axisU2 -ne ''){ $axisU=[int]$axisU2 }
$c1U=0; foreach($h in $bm.horses){ if([int]$h.rk -eq 1){ $c1U=[int]$h.uma; break } }
$p1U=0; foreach($h in $bm.horses){ if([int]("0"+"$($h.pop)") -eq 1){ $p1U=[int]$h.uma; break } }

$senkoCnt=0
$horses=@()
foreach($h in $bm.horses){
  $u="$([int]$h.uma)"; $ev= if($evalOf.ContainsKey($u)){$evalOf[$u]}else{$null}
  $st="$($h.style)"; if($st -eq '逃げ' -or $st -eq '先行'){ $senkoCnt++ }
  $horses += [ordered]@{
    mark="$($h.mark)"; uma=[int]$h.uma; name="$($h.name)"; idx=[int]("0"+"$($h.idx)"); rk=[int]("0"+"$($h.rk)")
    sougou=$(if($ev -and "$($ev.sougou)" -ne ''){[math]::Round([double]("0"+"$($ev.sougou)"),3)}else{''})
    eval=$(if($ev){"$($ev.eval)"}else{''})
    h2h="$($h.h2h)"; style=$st; dz=$(if("$($h.dz)" -eq ''){''}else{[int]$h.dz}); pop=[int]("0"+"$($h.pop)")
    tan=[double]("0"+"$($h.tan)"); pfuku=$(if("$($h.pfuku)" -eq ''){''}else{[double]$h.pfuku})
    jk="$($h.jk)"; qual="$($h.qual)"; chaku=[int]("0"+"$($h.chaku)"); scratched=[bool]$h.scratched
  }
}
# 総合スコア順(降順)→無評価は末尾→コンピ順位。予想段階のjra-card総合の並び。
$horses=@($horses | Sort-Object @{Expression={ if("$($_.sougou)" -eq ''){[double]-999}else{[double]$_.sougou} };Descending=$true}, @{Expression={[int]$_.rk};Descending=$false})

$taikou=$null
if($bm.finished){
  $taikou=[ordered]@{
    axis=[ordered]@{uma=$axisU; chaku=$(if($chOf.ContainsKey($axisU)){$chOf[$axisU]}else{0}); lab=$axisLab}
    compi1=[ordered]@{uma=$c1U; chaku=$(if($chOf.ContainsKey($c1U)){$chOf[$c1U]}else{0})}
    ninki1=[ordered]@{uma=$p1U; chaku=$(if($chOf.ContainsKey($p1U)){$chOf[$p1U]}else{0})}
  }
}

# 4) 深掘り振り返り(確定後に1レースずつ手で書く散文分析。地方と同形式。keiba-daily-retro-granularity 絶対ルール)
$narr=''
$nf="C:\jra\reasons\$date\${Venue}_${Race}.md"
if(Test-Path $nf){ $narr=Get-Content $nf -Raw -Encoding UTF8 }

[ordered]@{ date=$date; venue=$Venue; race=$Race; dist=$bm.dist; post=$bm.post; raceName=$bm.raceName; tou=@($bm.horses).Count
  finished=$bm.finished; cancelled=$bm.cancelled; meta=$bm.meta; senkoCnt=$senkoCnt
  axis=$axisU; axisLab=$axisLab; partners=$partners; cardSrc=$cardSrc
  horses=$horses; taikou=$taikou; voted=$bm.voted; narrative=$narr } | ConvertTo-Json -Depth 6 -Compress
