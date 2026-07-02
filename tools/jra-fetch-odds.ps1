# jra-fetch-odds.ps1 — JRA公式サイト(jra.jp)の最新オッズを accessO.html からたどって取得する。
# ログイン不要・公開ページ・読み取りのみ。POST cname=<doActionの第2引数> で1段ずつ遷移する。
#   開催選択(pw15oli00/6D) → レース選択(pw15orl00…) → 単複オッズ(pw151ou…) → [式別pillから三連単 pw158ou…]
# <select>のoption値やcnameのチェックサム(/F8等)は推測せず、各ページのリンクから辿る(JRAの仕様変更に強い)。
# 文字コードは Shift_JIS。pwsh7 では CodePagesEncodingProvider 登録が必須(罠)。
#
# 使い方:
#   pwsh -File jra-fetch-odds.ps1 -Date 2026-06-21 -Venue 東京 -Race 1 -Type tanpuku
#   pwsh -File jra-fetch-odds.ps1 -Date 2026-06-21 -Venue 東京 -Race 1 -Type sanrentan -OutJson odds.json
#   -Type all で単複+三連単。-OutJson でJSON保存(未指定は標準出力に表)。

[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Date,                       # 2026-06-21 等(YYYY-MM-DD/YYYYMMDD)
  [Parameter(Mandatory)][string]$Venue,                      # 東京/阪神/函館… 競馬場名(部分一致)
  [Parameter(Mandatory)][int]$Race,                          # レース番号 1-12
  [ValidateSet('tanpuku','sanrentan','all')][string]$Type='tanpuku',
  # ↓三連単の組合せ抽出(全オッズ表からローカル合成。指定時は自動でsanrentanも取得)
  [string]$Box,            # ボックス: "3,4,5,7" → P(n,3)順列
  [string]$F1,             # フォーメーション1着: "5,7"
  [string]$F2,             # フォーメーション2着: "3,9"
  [string]$F3,             # フォーメーション3着: "3,6,9"
  [int]$WheelAxis,         # ながし軸馬番
  [ValidateSet('1','2','3')][string]$WheelPos='1', # 軸の着(1着/2着/3着ながし)
  [string]$WheelPartners,  # ながし相手: "5,6,9"
  [switch]$WheelMulti,     # ながしマルチ(軸が1-3着のどこでも)
  [string]$OutJson,
  [int]$TimeoutSec=30
)
$needSan = ($Type -in 'sanrentan','all') -or $Box -or ($F1 -and $F2 -and $F3) -or ($WheelAxis -gt 0 -and $WheelPartners)
if($needSan -and $Type -eq 'tanpuku'){ $Type='all' }   # 組合せ抽出指定時は三連単も取得

$ErrorActionPreference='Stop'
try { [System.Text.Encoding]::RegisterProvider([System.Text.CodePagesEncodingProvider]::Instance) } catch {}
$script:SJIS = [System.Text.Encoding]::GetEncoding(932)
$script:BASE = 'https://jra.jp'
$script:WS   = $null   # WebSession(cookie保持)

# YYYYMMDD へ正規化
$ymd = ($Date -replace '[^0-9]','')
if ($ymd.Length -ne 8) { throw "Date は YYYY-MM-DD か YYYYMMDD で指定してください: $Date" }

function Invoke-Cname {
  param([string]$Cname)
  $args = @{
    Uri='{0}/JRADB/accessO.html' -f $script:BASE
    Method='Post'; Body=("cname={0}" -f $Cname)
    ContentType='application/x-www-form-urlencoded'
    UseBasicParsing=$true; TimeoutSec=$TimeoutSec
  }
  if ($script:WS) { $args.WebSession = $script:WS } else { $args.SessionVariable = 'newws' }
  $r = Invoke-WebRequest @args
  if (-not $script:WS) { $script:WS = $newws }
  return $script:SJIS.GetString($r.RawContentStream.ToArray())
}

# 指定プレフィクスの doAction cname を列挙(出現順・重複排除)
function Get-Cnames {
  param([string]$Html,[string]$Prefix)
  $rx = [regex]("doAction\('/JRADB/accessO\.html',\s*'(" + [regex]::Escape($Prefix) + "[^']+)'\)")
  $seen=[ordered]@{}
  foreach ($m in $rx.Matches($Html)) { $v=$m.Groups[1].Value; if(-not $seen.Contains($v)){ $seen[$v]=$true } }
  return @($seen.Keys)
}

# cname本体からレース番号を取る: pw15Nou + 'S3' + 場(2)+開催(8)+レース(2)+日付(8)+'Z'
function Get-RaceNo {
  param([string]$Cname)
  if ($Cname -match '^pw15.ouS3(\d{2})(\d{8})(\d{2})(\d{8})Z') { return [int]$Matches[3] }
  return -1
}

function Strip-Tags { param([string]$s) ($s -replace '<[^>]+>','' -replace '&nbsp;',' ' -replace '\s+',' ').Trim() }

# ---- 1) 開催選択 → 対象 場×日付 のレース選択cname ----
Write-Host "[1] 開催選択 … " -NoNewline
$h1 = Invoke-Cname 'pw15oli00/6D'
$orl = Get-Cnames $h1 'pw15orl00'
# cname末尾(チェックサム前)8桁が開催日。場名はアンカー内テキスト(<i>アイコンの後)で突合。
$rxOrl=[regex]"(?s)<a[^>]*doAction\('/JRADB/accessO\.html',\s*'(pw15orl00[^']+)'\)[^>]*>(.*?)</a>"
$cand=@()
foreach($m in $rxOrl.Matches($h1)){
  $cn=$m.Groups[1].Value; $label=Strip-Tags $m.Groups[2].Value
  if($cn -match '^pw15orl00(\d{2})(\d{8})(\d{8})/'){ $cand += [pscustomobject]@{Cname=$cn;Venue2=$Matches[1];Date=$Matches[3];Label=$label} }
}
$target = $cand | Where-Object { $_.Date -eq $ymd -and ($_.Label -like "*$Venue*") } | Select-Object -First 1
if(-not $target){ # ラベルで取れない場合は日付一致のみ列挙して案内
  $sameDay = $cand | Where-Object { $_.Date -eq $ymd }
  throw ("対象の開催が見つかりません(Venue=$Venue Date=$ymd)。同日開催: " + (($sameDay|ForEach-Object{$_.Label}) -join ' / '))
}
Write-Host ("→ {0}" -f $target.Label)

# ---- 2) レース選択 → 対象レースの単複cname ----
Write-Host "[2] レース選択 … " -NoNewline
$h2 = Invoke-Cname $target.Cname
$tanAll = Get-Cnames $h2 'pw151ou'
$tanCn = $tanAll | Where-Object { (Get-RaceNo $_) -eq $Race } | Select-Object -First 1
if(-not $tanCn){ throw "レース $Race の単複オッズリンクが見つかりません。" }
Write-Host ("→ {0}R 単複" -f $Race)

# ---- 3) 単複オッズページ取得(式別pillのcnameもここから拾う) ----
$h3 = Invoke-Cname $tanCn
$result = [ordered]@{
  date=$ymd; venue=$target.Label; race=$Race
  retrievedAt=(Get-Date).ToString('s'); asOfText=$null
}
if($h3 -match '(\d{1,2}時\d{1,2}分現在オッズ)'){ $result.asOfText=$Matches[1] }

# 単複パース
function Parse-Tanpuku {
  param([string]$Html)
  $rows=@()
  $rx=[regex]'(?s)<td class="num">(\d+)</td>\s*<td class="horse"><a[^>]*>([^<]*)</a></td>\s*<td class="odds_tan">(.*?)</td>\s*<td class="odds_fuku">(.*?)</td>'
  foreach($m in $rx.Matches($Html)){
    $num=[int]$m.Groups[1].Value
    $name=Strip-Tags $m.Groups[2].Value
    $tan = Strip-Tags $m.Groups[3].Value
    $fukuRaw=$m.Groups[4].Value
    $fmin=$null;$fmax=$null
    if($fukuRaw -match '<span class="min">([^<]*)</span>'){ $fmin=$Matches[1].Trim() }
    if($fukuRaw -match '<span class="max">([^<]*)</span>'){ $fmax=$Matches[1].Trim() }
    $rows += [pscustomobject]@{ umaban=$num; name=$name; tan=$tan; fuku_min=$fmin; fuku_max=$fmax }
  }
  return $rows
}

if($Type -in 'tanpuku','all'){
  $result.tanpuku = Parse-Tanpuku $h3
  Write-Host ("[3] 単複 {0}頭取得" -f $result.tanpuku.Count)
}

# ---- 4) 三連単(必要時): 単複ページの式別pillから pw158ou cname を辿る ----
function Parse-Sanrentan {
  param([string]$Html)
  # 1着ブロックごと(<div class="tan3_unit">…)。各<li>に1着・2着のnum、表に3着num→オッズ。
  $combos=@()
  $unitRx=[regex]'(?s)<div class="tan3_unit[^"]*">.*?<span class="num">(\d+)</span>.*?(?=<div class="tan3_unit|<div class="caution)'
  foreach($u in $unitRx.Matches($Html)){
    $block=$u.Value
    $liRx=[regex]'(?s)<li>\s*<div class="p_line">.*?<div class="num">(\d+)</div>.*?</div>\s*<div class="p_line">.*?<div class="num">(\d+)</div>.*?</div>\s*<table.*?<tbody>(.*?)</tbody>'
    foreach($li in $liRx.Matches($block)){
      $first=[int]$li.Groups[1].Value; $second=[int]$li.Groups[2].Value
      $cellRx=[regex]'(?s)<th scope="row">(\d+)</th>\s*<td[^>]*>(.*?)</td>'
      foreach($c in $cellRx.Matches($li.Groups[3].Value)){
        $third=[int]$c.Groups[1].Value
        $odds=Strip-Tags $c.Groups[2].Value
        if($odds -eq '' -or $odds -eq '票数なし'){ continue }   # &nbsp;(自身) / 票数なし はスキップ
        $combos += [pscustomobject]@{ p1=$first; p2=$second; p3=$third; odds=$odds }
      }
    }
  }
  return $combos
}

if($Type -in 'sanrentan','all'){
  Write-Host "[4] 三連単 … " -NoNewline
  $sanCn = (Get-Cnames $h3 'pw158ou') | Select-Object -First 1   # 式別pillの三連単(馬番順)
  if(-not $sanCn){ throw "三連単オッズへのリンクが見つかりません。" }
  $h4 = Invoke-Cname $sanCn
  if($h4 -match '(\d{1,2}時\d{1,2}分現在オッズ)' -and -not $result.asOfText){ $result.asOfText=$Matches[1] }
  $result.sanrentan = Parse-Sanrentan $h4
  Write-Host ("{0}組取得" -f $result.sanrentan.Count)
}

# ---- 5) 三連単の組合せ抽出(全オッズ表からローカル合成。方式は式別共通) ----
# JRA公式の「オッズを見る」はpw15Nojへ選択をPOSTして組合せ別オッズを返すが、馬番順の全オッズ表に
# 全組合せが含まれるので、サーバ往復せず手元で合成する(締切間際でも安定・確実)。
if($result.Contains('sanrentan') -and ($Box -or ($F1 -and $F2 -and $F3) -or ($WheelAxis -gt 0 -and $WheelPartners))){
  $dict=@{}
  foreach($c in $result.sanrentan){ $dict["$($c.p1)-$($c.p2)-$($c.p3)"]=$c.odds }
  function Get-Odds($a,$b,$c){ $k="$a-$b-$c"; if($dict.ContainsKey($k)){ return $dict[$k] } else { return $null } }
  function Split-Nums($s){ @($s -split '[,\s\|\-]+' | ForEach-Object { if($_ -match '^\d+$'){ [int]$_ } } | Where-Object { $_ -gt 0 }) }
  $sel=@(); $label=''
  if($Box){
    $label='ボックス'; $ns=Split-Nums $Box
    for($i=0;$i -lt $ns.Count;$i++){ for($j=0;$j -lt $ns.Count;$j++){ for($k=0;$k -lt $ns.Count;$k++){
      if($i -ne $j -and $i -ne $k -and $j -ne $k){ $a=$ns[$i];$b=$ns[$j];$c=$ns[$k]; $sel+=[pscustomobject]@{combo="$a-$b-$c";odds=(Get-Odds $a $b $c)} }
    }}}
  } elseif($F1 -and $F2 -and $F3){
    $label='フォーメーション'; $a1=Split-Nums $F1; $a2=Split-Nums $F2; $a3=Split-Nums $F3
    foreach($a in $a1){ foreach($b in $a2){ foreach($c in $a3){ if($a -ne $b -and $a -ne $c -and $b -ne $c){ $sel+=[pscustomobject]@{combo="$a-$b-$c";odds=(Get-Odds $a $b $c)} } }}}
  } elseif($WheelAxis -gt 0){
    $ps=@(Split-Nums $WheelPartners | Where-Object { $_ -ne $WheelAxis })
    if($WheelMulti){
      $label="マルチ流し(軸$WheelAxis)"
      foreach($x in $ps){ foreach($y in $ps){ if($x -ne $y){
        $sel+=[pscustomobject]@{combo="$WheelAxis-$x-$y";odds=(Get-Odds $WheelAxis $x $y)}
        $sel+=[pscustomobject]@{combo="$x-$WheelAxis-$y";odds=(Get-Odds $x $WheelAxis $y)}
        $sel+=[pscustomobject]@{combo="$x-$y-$WheelAxis";odds=(Get-Odds $x $y $WheelAxis)}
      }}}
    } else {
      $label="$($WheelPos)着流し(軸$WheelAxis)"
      foreach($x in $ps){ foreach($y in $ps){ if($x -ne $y){
        switch($WheelPos){ '1'{$a=$WheelAxis;$b=$x;$c=$y} '2'{$a=$x;$b=$WheelAxis;$c=$y} '3'{$a=$x;$b=$y;$c=$WheelAxis} }
        $sel+=[pscustomobject]@{combo="$a-$b-$c";odds=(Get-Odds $a $b $c)}
      }}}
    }
  }
  $result.selectionType=$label
  $result.selection=$sel
  $hit=@($sel | Where-Object { $_.odds })
  Write-Host ("[5] 三連単{0}: {1}点(オッズ取得{2}点)" -f $label,$sel.Count,$hit.Count)
}

# ---- 出力 ----
if($OutJson){
  ($result | ConvertTo-Json -Depth 6) | Set-Content -Path $OutJson -Encoding UTF8
  Write-Host ("保存: {0}" -f $OutJson)
} else {
  if($result.Contains('tanpuku')){
    Write-Host ("`n=== {0} {1}R 単複オッズ ({2}) ===" -f $result.venue,$Race,$result.asOfText)
    $result.tanpuku | Format-Table umaban,name,tan,@{n='複勝';e={"$($_.fuku_min)-$($_.fuku_max)"}} -AutoSize
  }
  if($result.Contains('selection')){
    Write-Host ("=== 三連単 {0} {1}点 ===" -f $result.selectionType,$result.selection.Count)
    $result.selection | Format-Table @{n='組';e={$_.combo}},@{n='オッズ';e={if($_.odds){$_.odds}else{'-'}}} -AutoSize
  } elseif($result.Contains('sanrentan')){
    Write-Host ("=== 三連単 {0}組(先頭20) ===" -f $result.sanrentan.Count)
    $result.sanrentan | Select-Object -First 20 | Format-Table p1,p2,p3,odds -AutoSize
  }
}
