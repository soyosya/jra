<#
.SYNOPSIS
  中央競馬: JRA公式「今週の開催お知らせ」(accessI=変更情報)から 発走時刻変更/出走取消/競走除外/レース取消 と 天候/馬場 を取得し
  dbo.変更情報 + レース情報(発走時刻/天候/馬場) を更新。レース取消は race-cancel.json にも反映(自動投票スキップ)。
.DESCRIPTION
  accessI.html は直GET不可(POST/cname・非開催日error013)。jra-fetch-weight同方式: accessO session → メニュー/ページから
  accessI.html の cname(=pw01ide01/4F系)を追従 → 取得(Shift_JIS)。指定日(=月日)のセクションのみ解析。
  実HTML構造:
    ・天候/馬場: div.weather_block table(競馬場列th=場名・天候行・馬場行[芝/ダート])。
    ・変更: 開催別 table.basic(caption="N回{場}M日") tbody の tr.change → th(R番号) + td 内 dl(dt=種別/dd=詳細)。
  反映: 発走時刻変更→レース情報.発走時刻 / 天候馬場→レース情報.天候,馬場 / 出走取消・除外→dbo.変更情報(馬番) / レース取消→race-cancel.json。
.PARAMETER Date   既定=当日。 .PARAMETER DryRun DB更新せず解析のみ。 .PARAMETER Dump 取得HTMLをC:\temp\jra_changes_<ymd>.htmlへ保存。
.OUTPUTS  CHANGES|<変更件数>
#>
[CmdletBinding()]
param([string]$Date=(Get-Date).ToString('yyyy-MM-dd'),[switch]$DryRun,[switch]$Dump)
$ErrorActionPreference='Stop'
try { [System.Text.Encoding]::RegisterProvider([System.Text.CodePagesEncodingProvider]::Instance) } catch {}
$SJIS=[Text.Encoding]::GetEncoding(932)
$ymd=($Date -replace '[^0-9]','')
if($ymd.Length -ne 8){ throw "Date は yyyy-MM-dd で指定してください: $Date" }
$mon=[int]$ymd.Substring(4,2); $day=[int]$ymd.Substring(6,2)
$BASE='https://www.jra.go.jp'; $script:WS=$null
$VENUES=@('札幌','函館','福島','新潟','東京','中山','中京','京都','阪神','小倉')

function Cn([string]$servlet,[string]$c){
  $a=@{Uri="$BASE/JRADB/$servlet";Method='Post';Body="cname=$c";ContentType='application/x-www-form-urlencoded';UseBasicParsing=$true;TimeoutSec=30}
  if($script:WS){$a.WebSession=$script:WS}else{$a.SessionVariable='nw'}
  $r=Invoke-WebRequest @a; if(-not $script:WS){$script:WS=$nw}
  return $SJIS.GetString($r.RawContentStream.ToArray())
}
function VenueOf([string]$s){ foreach($v in $VENUES){ if($s -match [regex]::Escape($v)){ return $v } }; return '' }
function Strip([string]$h){ (($h -replace '<[^>]+>',' ' -replace '&nbsp;',' ' -replace '\s+',' ')).Trim() }

# --- セッション & accessI(開催お知らせ)取得 ---
[void](Cn 'accessO.html' 'pw15oli00/6D')
$menu = Cn 'accessD.html' 'pw01dli00/F3'   # 出馬表top(メニューにaccessIリンクあり)
$icn=''
$im=[regex]::Match($menu,"accessI\.html['"",\s]+([0-9A-Za-z]{6,}/[0-9A-Za-z]{1,4})"); if($im.Success){ $icn=$im.Groups[1].Value }
if($icn -eq ''){ $icn='pw01ide01/4F' }   # フォールバック(メニュー既知cname)
$html = Cn 'accessI.html' $icn
if($Dump){ $dp="C:\temp\jra_changes_$ymd.html"; [IO.File]::WriteAllText($dp,$html,$SJIS); Write-Output "  HTML保存: $dp ($($html.Length)文字)" }

# --- 指定日(月日)のセクションを切り出し ---
$secStart=[regex]::Match($html,("(?s)<h2>\s*{0}月\s*{1}日" -f $mon,$day))
$work= if($secStart.Success){
  $rest=$html.Substring($secStart.Index)
  $nextH2=[regex]::Match($rest.Substring(5),'<h2>'); if($nextH2.Success){ $rest.Substring(0,$nextH2.Index+5) }else{ $rest }
}else{ $html }   # 見つからなければ全体(初回/単一開催日)

# --- 天候/馬場(weather_block) ---
$weather=@{}  # 場 -> @{天候; 芝; ダート}
$wb=[regex]::Match($work,'(?s)weather_block.*?</table>')
if($wb.Success){
  $wt=$wb.Value
  # 競馬場列(thead th rcA/rcB/rcC)
  $cols=@(); foreach($th in [regex]::Matches($wt,'(?s)<th scope="col"[^>]*>(.*?)</th>')){ $vn=VenueOf (Strip $th.Groups[1].Value); if($vn){$cols+=$vn} }
  # 天候行
  $tenkiRow=[regex]::Match($wt,'(?s)<tr class="weather">(.*?)</tr>')
  $babaRow =[regex]::Match($wt,'(?s)<tr class="baba">(.*?)</tr>')
  if($cols.Count -gt 0){
    $tds=@([regex]::Matches($tenkiRow.Groups[1].Value,'(?s)<td>(.*?)</td>'))
    $bds=@([regex]::Matches($babaRow.Groups[1].Value,'(?s)<td>(.*?)</td>'))
    for($i=0;$i -lt $cols.Count;$i++){
      $v=$cols[$i]; if(-not $weather.ContainsKey($v)){$weather[$v]=@{天候='';芝='';ダート=''}}
      if($i -lt $tds.Count){ $tc=Strip $tds[$i].Groups[1].Value; foreach($w in '晴','曇','小雨','雨','小雪','雪'){ if($tc -match $w){ $weather[$v].天候=$w; break } } }
      if($i -lt $bds.Count){ $bc=Strip $bds[$i].Groups[1].Value
        $sm=[regex]::Match($bc,'芝\s*(良|稍重|重|不良)'); if($sm.Success){ $weather[$v].芝=$sm.Groups[1].Value }
        $dm=[regex]::Match($bc,'ダート\s*(良|稍重|重|不良)'); if($dm.Success){ $weather[$v].ダート=$dm.Groups[1].Value } }
    }
  }
}

# --- 変更テーブル(開催別 table.basic caption付き) ---
$changes=@()   # {場;R;種別;内容;馬番;新時刻}
foreach($tb in [regex]::Matches($work,'(?s)<table class="basic">\s*<caption>(.*?)</caption>(.*?)</table>')){
  $venue=VenueOf (Strip $tb.Groups[1].Value); if($venue -eq ''){ continue }
  foreach($tr in [regex]::Matches($tb.Groups[2].Value,'(?s)<tr class="change">(.*?)</tr>')){
    $rno=[regex]::Match($tr.Groups[1].Value,'<th[^>]*>\s*(\d{1,2})\s*</th>'); if(-not $rno.Success){ continue }
    $R=[int]$rno.Groups[1].Value
    foreach($dl in [regex]::Matches($tr.Groups[1].Value,'(?s)<dt>(.*?)</dt>\s*<dd>(.*?)</dd>')){
      $kind=Strip $dl.Groups[1].Value; $detail=Strip $dl.Groups[2].Value
      $uma=0; $um=[regex]::Match($detail,'(\d{1,2})\s*番'); if($um.Success){ $uma=[int]$um.Groups[1].Value }
      $newt=''; $tm=[regex]::Match($detail,'(\d{1,2})\s*時\s*(\d{1,2})\s*分\s*に変更'); if($tm.Success){ $newt='{0:D2}:{1:D2}' -f [int]$tm.Groups[1].Value,[int]$tm.Groups[2].Value }
      $changes+=[pscustomobject]@{ 場=$venue; R=$R; 種別=$kind; 内容=$detail; 馬番=$uma; 新時刻=$newt }
    }
  }
}
Write-Output ("解析: 変更{0}件 / 天候馬場{1}場 (日付={2})" -f $changes.Count,$weather.Count,$Date)
$changes | Select-Object -First 12 | ForEach-Object { Write-Output ("  {0} {1}R [{2}] {3}" -f $_.場,$_.R,$_.種別,$_.内容) }
foreach($v in $weather.Keys){ Write-Output ("  {0}: 天候{1} 芝{2}/ダート{3}" -f $v,$weather[$v].天候,$weather[$v].芝,$weather[$v].ダート) }

if($DryRun){ Write-Output ("CHANGES|{0}" -f $changes.Count); return }

# --- DB反映 ---
$cs=(Get-Content 'C:\jra\共通\appsettings.json' -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
$conn=New-Object System.Data.SqlClient.SqlConnection $cs; $conn.Open()
$cancelRaces=@()
try{
  # 変更情報: 当日洗替INSERT
  $del=$conn.CreateCommand(); $del.CommandText="DELETE FROM dbo.変更情報 WHERE 開催日=@d"; [void]$del.Parameters.AddWithValue('@d',$Date); [void]$del.ExecuteNonQuery()
  foreach($c in $changes){
    # 区分正規化
    $kubun= if($c.種別 -match '発走時刻'){'発走時刻変更'}elseif($c.種別 -match 'レース取消|競走中止|開催中止'){'レース取消'}elseif($c.種別 -match '出走取消|発走取消'){'出走取消'}elseif($c.種別 -match '除外'){'除外'}elseif($c.種別 -match '騎手'){'騎手変更'}elseif($c.種別 -match '馬体重'){'馬体重'}else{$c.種別}
    $ins=$conn.CreateCommand()
    $ins.CommandText="INSERT INTO dbo.変更情報(開催日,開催場所,レース番号,馬番,馬名,変更区分,変更理由,変更内容) VALUES(@d,@v,@r,@u,'',@k,'',@c)"
    [void]$ins.Parameters.AddWithValue('@d',$Date);[void]$ins.Parameters.AddWithValue('@v',$c.場);[void]$ins.Parameters.AddWithValue('@r',$c.R)
    [void]$ins.Parameters.AddWithValue('@u',$c.馬番);[void]$ins.Parameters.AddWithValue('@k',$kubun);[void]$ins.Parameters.AddWithValue('@c',$c.内容)
    [void]$ins.ExecuteNonQuery()
    # 発走時刻変更 → レース情報.発走時刻 更新(時刻のみ・当日日付で)
    if($kubun -eq '発走時刻変更' -and $c.新時刻 -ne ''){
      $up=$conn.CreateCommand(); $up.CommandText="UPDATE レース情報 SET 発走時刻=CONVERT(datetime,@dt+' '+@t) WHERE 開催日=@d AND 開催場所=@v AND レース番号=@r"
      [void]$up.Parameters.AddWithValue('@dt',$Date);[void]$up.Parameters.AddWithValue('@t',$c.新時刻);[void]$up.Parameters.AddWithValue('@d',$Date);[void]$up.Parameters.AddWithValue('@v',$c.場);[void]$up.Parameters.AddWithValue('@r',$c.R); try{[void]$up.ExecuteNonQuery()}catch{}
    }
    # レース取消 → race-cancel.json 対象に
    if($kubun -eq 'レース取消'){ $cancelRaces += ("{0}|{1}" -f $c.場,$c.R) }
  }
  # 天候/馬場 → レース情報 更新(その場の全レース)。芝/ダートは種別に応じ、無ければ芝優先で馬場へ。
  foreach($v in $weather.Keys){
    $w=$weather[$v]; $baba= if($w.芝 -ne ''){$w.芝}elseif($w.ダート -ne ''){$w.ダート}else{''}
    if($w.天候 -ne '' -or $baba -ne ''){
      $up=$conn.CreateCommand(); $up.CommandText="UPDATE レース情報 SET 天候=CASE WHEN @t<>'' THEN @t ELSE 天候 END, 馬場=CASE WHEN @b<>'' THEN @b ELSE 馬場 END WHERE 開催日=@d AND 開催場所=@v"
      [void]$up.Parameters.AddWithValue('@t',$w.天候);[void]$up.Parameters.AddWithValue('@b',$baba);[void]$up.Parameters.AddWithValue('@d',$Date);[void]$up.Parameters.AddWithValue('@v',$v); try{[void]$up.ExecuteNonQuery()}catch{}
    }
  }
} finally { $conn.Close() }

# レース取消 → race-cancel.json(/buyme取りやめ表示 + jra-weight-loopスキップ)。当日分とマージ。
if($cancelRaces.Count -gt 0){
  $cf='C:\jra\RunnerControl\race-cancel.json'; $set=@{}
  try{ if(Test-Path $cf){ $j=Get-Content $cf -Raw -Encoding UTF8|ConvertFrom-Json; if($j -and "$($j.date)" -eq $Date){ foreach($k in @($j.cancelled)){ if($k){$set["$k"]=$true} } } } }catch{}
  foreach($k in $cancelRaces){ $set[$k]=$true }
  $obj=[ordered]@{ date=$Date; cancelled=@($set.Keys) }
  try{ [IO.File]::WriteAllText($cf, ($obj|ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding($false))); Write-Output ("  レース取消 {0}件 → race-cancel.json" -f $cancelRaces.Count) }catch{}
}
Write-Output ("CHANGES|{0}" -f $changes.Count)
