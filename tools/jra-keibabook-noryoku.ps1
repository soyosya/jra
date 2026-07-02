<#
.SYNOPSIS
  競馬ブック「能力表」由来のコンピュータファクターを取得し 競馬ブック能力指数 / 競馬ブックCPU へ蓄積。
.DESCRIPTION
  会員ログイン→/cyuou/nittei/{date}で当日のsyutuba race_id発見→各レースで以下を取得・解析:
    /cyuou/speed/0/{id}  : スピード指数(走破タイム・馬場差補正)。各馬の過去5走の値+過去走メタ。
    /cyuou/rating/{id}   : レイティング(着順・対戦比較)。各馬の過去7走の値+矢印トレンド。
    /cyuou/cpu/{id}      : コンピュータ予想。各馬の4ファクター寄与(speed/facter/rating/book)+単勝予測。
  取得0件のテーブルは入れ替えしない(空取得での消失防止)。-Offline でC:\temp保存HTMLを解析(DB書込なし)。
.PARAMETER Date    対象開催日(yyyy-MM-dd)。
.PARAMETER Offline ローカルHTML(race 202603040501)を解析しDB書込しない(開発確認)。
#>
[CmdletBinding()] param([string]$Date,[switch]$Offline)
$ErrorActionPreference='Stop'
$connStr=(Get-Content 'C:\jra\共通\appsettings.json' -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
$ua="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36"
$curl="C:\Windows\System32\curl.exe"; $jar="$env:TEMP\keibabook_noryoku_cookies.txt"; $base="https://p.keibabook.co.jp"
$venueRe='札幌|函館|福島|新潟|東京|中山|中京|京都|阪神|小倉'

function Login {
  if(Test-Path $jar){Remove-Item $jar -Force}
  $page=& $curl -s -A $ua -b $jar -c $jar "$base/login/login"
  $tok=[regex]::Match(($page -join "`n"),'name="_token"[^>]*value="(?<v>[^"]+)"').Groups['v'].Value
  if(-not $tok){ throw "ログイン_token取得失敗" }
  $sec=Get-Content "C:\jra\secrets.local.json" -Raw | ConvertFrom-Json
  $resp=& $curl -s -L -A $ua -b $jar -c $jar --data-urlencode "_token=$tok" --data-urlencode "login_id=$($sec.KeibabookUser)" --data-urlencode "pswd=$($sec.KeibabookPass)" --data-urlencode "service=keibabook" --data-urlencode "referer=" --data-urlencode "autologin=1" --data-urlencode "submitbutton=ログインする" "$base/login/login"
  if([regex]::IsMatch(($resp -join "`n"),'name="pswd"')){ throw "ログイン失敗(資格情報確認)" }
  Write-Host "競馬ブックにログインしました。"
}
function Fetch($url){ # ページはUTF-8。& curl の出力をPS既定(CP932)で復号すると馬名/過去内容が文字化けするため、-oでファイルに保存しUTF-8で読む
  $tmp=[IO.Path]::GetTempFileName()
  & $curl -s -A $ua -b $jar -c $jar --max-time 60 -o $tmp $url | Out-Null
  $t= if(Test-Path $tmp){ [IO.File]::ReadAllText($tmp,[Text.Encoding]::UTF8) }else{ '' }
  Remove-Item $tmp -Force -ErrorAction SilentlyContinue
  return $t }
# レート制限で頭数欠落の部分ページが返るため、最大3回取得して「出走馬リンク最多」の応答を採用
function FetchBest($url){
  $best='';$bestN=-1
  for($a=1;$a -le 3;$a++){
    $h=Fetch $url
    $n=([regex]::Matches($h,'/db/uma/\d+')).Count
    if($n -gt $bestN){ $bestN=$n; $best=$h }
    if($n -ge 8){ return $best }   # 十分な頭数なら即採用(非スロットル時は1発)
    Start-Sleep -Seconds 8         # 部分ページ→待って再取得
  }
  return $best
}
function Z2H($s){ if($null -eq $s){return $null}; $s.Normalize([Text.NormalizationForm]::FormKC) }   # 全角→半角
function ToD($s){ $d=0.0; if([double]::TryParse(($s -replace '[^\d.]',''),[ref]$d)){ return $d } return $null }
function Venue($html){ [regex]::Match($html,$venueRe).Value }

# 行をtr単位に分割(全trから。馬名行以外は各パーサがumaチェックで除外)
function Rows($html){ [regex]::Matches($html,'<tr[^>]*>.*?</tr>','Singleline') | ForEach-Object { $_.Value } }

# --- スピード指数 ---
function Parse-Speed($html){
  $out=@()
  foreach($tr in (Rows $html)){
    $no=[regex]::Match($tr,'<td class="umaban">(\d+)</td>').Groups[1].Value
    $um=[regex]::Match($tr,'/db/uma/(\d+)"[^>]*>(?<n>[^<]+)</a>')
    if(-not $um.Success){ continue }
    $umacd=$um.Groups[1].Value; $nm=$um.Groups['n'].Value.Trim()
    $tds=[regex]::Matches($tr,'<td class="speed">(?<c>.*?)</td>','Singleline')
    for($i=0;$i -lt $tds.Count;$i++){
      $c=$tds[$i].Groups['c'].Value
      $rid=[regex]::Match($c,'/(?:cyuou|chihou)/seiseki/(\d+)').Groups[1].Value
      if(-not $rid){ continue }
      $ps=[regex]::Matches($c,'<p[^>]*>(?<x>.*?)</p>','Singleline') | ForEach-Object { ([regex]::Replace($_.Groups['x'].Value,'<[^>]+>','')).Trim() }
      $dtxt=$ps[0]; $cont=$ps[1]
      $dm=[regex]::Match($dtxt,'(\d{4})\.(\d{1,2})\.(\d{1,2})')
      $pdate= if($dm.Success){ "{0}-{1:D2}-{2:D2}" -f $dm.Groups[1].Value,[int]$dm.Groups[2].Value,[int]$dm.Groups[3].Value }else{$null}
      $pv=[regex]::Match($dtxt,$venueRe).Value
      $sp=[regex]::Match($c,'<span class="(?<cl>speed\w*)">(?<v>[\d.]+)</span>')
      $val= if($sp.Success){[double]$sp.Groups['v'].Value}else{$null}
      $best= if($sp.Groups['cl'].Value -match 'best'){1}else{0}
      $out+=[PSCustomObject]@{no=$no;umacd=$umacd;nm=$nm;種別='speed';列位置=($i+1);過去id=$rid;過去日付=$pdate;過去場=$pv;過去内容=$cont;値=$val;best=$best;矢印=$null}
    }
  }
  ,$out
}
# --- レイティング ---
function Parse-Rating($html){
  $out=@()
  foreach($tr in (Rows $html)){
    $no=(Z2H ([regex]::Match($tr,'<td class="waku"><p class="waku\d+">(?<n>[^<]+)</p>').Groups['n'].Value)) -replace '[^\d]',''
    $um=[regex]::Match($tr,'/db/uma/(\d+)"[^>]*>(?<n>[^<]+)</a>')
    if(-not $um.Success){ continue }
    $umacd=$um.Groups[1].Value; $nm=$um.Groups['n'].Value.Trim()
    $tds=[regex]::Matches($tr,'<td class="rating">(?<c>.*?)</td>','Singleline')
    for($i=0;$i -lt $tds.Count;$i++){
      $c=$tds[$i].Groups['c'].Value
      $val=[regex]::Match($c,'<p class="rating">(?<v>[\d.]+)</p>').Groups['v'].Value
      if(-not $val){ continue }
      $rid=[regex]::Match($c,'/(?:cyuou|chihou)/seiseki/(\d+)').Groups[1].Value
      $neg=([regex]::Replace([regex]::Match($c,'<p class="negahi">(?<x>[^<]*)</p>').Groups['x'].Value,'<[^>]+>','')).Trim()
      $ya=[regex]::Match($c,'yajirushi[^"]*">(?<a>[↗↘→↑↓])').Groups['a'].Value
      $ym=[regex]::Match($neg,'(\d{2})年(\d{1,2})月')
      $pdate= if($ym.Success){ "20{0}-{1:D2}-01" -f $ym.Groups[1].Value,[int]$ym.Groups[2].Value }else{$null}
      $out+=[PSCustomObject]@{no=$no;umacd=$umacd;nm=$nm;種別='rating';列位置=($i+1);過去id=$rid;過去日付=$pdate;過去場=$null;過去内容=$neg;値=[double]$val;best=$null;矢印=$ya}
    }
  }
  ,$out
}
# --- CPU(4ファクター寄与+単勝予測) ---
function Parse-CPU($html){
  $out=@()
  foreach($blk in ([regex]::Matches($html,'<!-- 1頭始まり -->(?<x>.*?)<!-- 1頭終わり -->','Singleline'))){
    $b=$blk.Groups['x'].Value
    $no=[regex]::Match($b,'<td class="umaban">(\d+)</td>').Groups[1].Value
    $um=[regex]::Match($b,'/db/uma/(\d+)"[^>]*>(?<n>[^<]+)</a>')
    if(-not $um.Success){ continue }
    $umacd=$um.Groups[1].Value; $nm=$um.Groups['n'].Value.Trim()
    $fs=[regex]::Match($b,'gp_speed"\s*style="width:\s*([\d.]+)%').Groups[1].Value
    $ff=[regex]::Match($b,'gp_facter"\s*style="width:\s*([\d.]+)%').Groups[1].Value
    $fr=[regex]::Match($b,'gp_rating"\s*style="width:\s*([\d.]+)%').Groups[1].Value
    $fb=[regex]::Match($b,'gp_book"\s*style="width:\s*([\d.]+)%').Groups[1].Value
    $rt=[regex]::Matches($b,'<td class="right">\s*([\d.]+)</td>','Singleline')
    $tan= if($rt.Count -gt 0){[double]$rt[$rt.Count-1].Groups[1].Value}else{$null}
    $sum=0.0; foreach($x in @($fs,$ff,$fr,$fb)){ if($x){$sum+=[double]$x} }
    $out+=[PSCustomObject]@{no=$no;umacd=$umacd;nm=$nm;f_speed=(ToD $fs);f_facter=(ToD $ff);f_rating=(ToD $fr);f_book=(ToD $fb);合計=[math]::Round($sum,1);単勝予測=$tan}
  }
  ,$out
}

if($Offline){
  $sp=Get-Content "C:\temp\kb_cyuou_speed_0_202603040501.html" -Raw -Encoding UTF8
  $ra=Get-Content "C:\temp\kb_cyuou_rating_202603040501.html" -Raw -Encoding UTF8
  $cp=Get-Content "C:\temp\kb_cpu.html" -Raw -Encoding UTF8
  $s=Parse-Speed $sp; $r=Parse-Rating $ra; $c=Parse-CPU $cp
  "[speed] {0}行  例:" -f $s.Count; $s | Select-Object -First 3 | ForEach-Object { "  馬番{0} {1} 列{2} {3} {4} {5} 値{6}{7}" -f $_.no,$_.nm,$_.列位置,$_.過去日付,$_.過去場,$_.過去内容,$_.値,$(if($_.best){' ★best'}) }
  "[rating] {0}行  例:" -f $r.Count; $r | Select-Object -First 3 | ForEach-Object { "  馬番{0} {1} 列{2} {3} {4} 値{5} 矢{6}" -f $_.no,$_.nm,$_.列位置,$_.過去日付,$_.過去内容,$_.値,$_.矢印 }
  "[cpu] {0}行  例:" -f $c.Count; $c | Select-Object -First 4 | ForEach-Object { "  馬番{0} {1} speed{2}/facter{3}/rating{4}/book{5} 合計{6} 単勝予測{7}" -f $_.no,$_.nm,$_.f_speed,$_.f_facter,$_.f_rating,$_.f_book,$_.合計,$_.単勝予測 }
  return
}

# ===== オンライン =====
if(-not $Date){ throw "-Date yyyy-MM-dd を指定してください(または -Offline)" }
$ymd=([datetime]$Date).ToString('yyyyMMdd'); $dISO=([datetime]$Date).ToString('yyyy-MM-dd')
Login
$nit=Fetch "$base/cyuou/nittei/$ymd"
$rids=@([regex]::Matches($nit,'/cyuou/syutuba/(\d{12})') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
if($rids.Count -eq 0){ Write-Host "race_id発見0件($dISO)。中止。"; return }
if($env:NORYOKU_DEBUG1 -eq '1'){ $rids=@($rids[0]) }
Write-Host ("対象 {0}: {1}レース" -f $dISO,$rids.Count)
$conn=New-Object System.Data.SqlClient.SqlConnection($connStr); $conn.Open(); $now=Get-Date
function AddP($c,$k,$val){ if($val -is [array]){ $val=($val|Select-Object -First 1) }; [void]$c.Parameters.AddWithValue($k,$(if($null -eq $val -or "$val" -eq ''){[DBNull]::Value}else{$val})) }
function InsN($p,$rid,$d,$v,$r){ $c=$conn.CreateCommand()
  $c.CommandText="INSERT INTO 競馬ブック能力指数(取得日時,race_id,開催日,開催場所,レース番号,馬番,umacd,馬名,種別,列位置,過去race_id,過去日付,過去場,過去内容,値,best,矢印) VALUES(@t,@rid,@d,@v,@r,@no,@u,@nm,@k,@col,@pid,@pd,@pv,@pc,@val,@b,@ya)"
  $a=@{'@t'=$now;'@rid'=$rid;'@d'=$d;'@v'=$v;'@r'=$r;'@no'=$p.no;'@u'=$p.umacd;'@nm'=$p.nm;'@k'=$p.種別;'@col'=$p.列位置;'@pid'=$p.過去id;'@pd'=$p.過去日付;'@pv'=$p.過去場;'@pc'=$p.過去内容;'@val'=$p.値;'@b'=$p.best;'@ya'=$p.矢印}
  foreach($k in $a.Keys){ AddP $c $k $a[$k] }; [void]$c.ExecuteNonQuery() }
function InsC($p,$rid,$d,$v,$r){ $c=$conn.CreateCommand()
  $c.CommandText="INSERT INTO 競馬ブックCPU(取得日時,race_id,開催日,開催場所,レース番号,馬番,umacd,馬名,f_speed,f_facter,f_rating,f_book,ブック合計,単勝予測) VALUES(@t,@rid,@d,@v,@r,@no,@u,@nm,@fs,@ff,@fr,@fb,@sum,@tan)"
  $a=@{'@t'=$now;'@rid'=$rid;'@d'=$d;'@v'=$v;'@r'=$r;'@no'=$p.no;'@u'=$p.umacd;'@nm'=$p.nm;'@fs'=$p.f_speed;'@ff'=$p.f_facter;'@fr'=$p.f_rating;'@fb'=$p.f_book;'@sum'=$p.合計;'@tan'=$p.単勝予測}
  foreach($k in $a.Keys){ AddP $c $k $a[$k] }; [void]$c.ExecuteNonQuery() }
function DelRace($rid){ foreach($t in '競馬ブック能力指数','競馬ブックCPU'){ $c=$conn.CreateCommand(); $c.CommandText="DELETE FROM $t WHERE race_id=@r"; [void]$c.Parameters.AddWithValue('@r',$rid); [void]$c.ExecuteNonQuery() } }

$tN=0;$tC=0;$done=0
foreach($rid in $rids){
  $rno=[int]$rid.Substring(10,2)
  $spH=FetchBest "$base/cyuou/speed/0/$rid"; Start-Sleep -Milliseconds 3000
  $raH=FetchBest "$base/cyuou/rating/$rid";  Start-Sleep -Milliseconds 3000
  $cpH=FetchBest "$base/cyuou/cpu/$rid";     Start-Sleep -Milliseconds 3000
  if($done % 6 -eq 5){ Start-Sleep -Seconds 15 }
  $v=Venue $spH; if(-not $v){ $v=Venue $cpH }
  $sRows=New-Object System.Collections.Generic.List[object]
  $tmpS=Parse-Speed $spH;  foreach($x in $tmpS){ if($x -and $x.種別){ $sRows.Add($x) } }
  $tmpR=Parse-Rating $raH; foreach($x in $tmpR){ if($x -and $x.種別){ $sRows.Add($x) } }
  $cRows=New-Object System.Collections.Generic.List[object]
  $tmpC=Parse-CPU $cpH;    foreach($x in $tmpC){ if($x -and $x.umacd){ $cRows.Add($x) } }
  if($env:NORYOKU_DEBUG1 -eq '1'){ Write-Host ("  DBG ${rid}: speed_uma={0} rating_uma={1} cpu_uma={2} / sRows={3} cRows={4}" -f ([regex]::Matches($spH,'/db/uma/\d+')).Count,([regex]::Matches($raH,'/db/uma/\d+')).Count,([regex]::Matches($cpH,'/db/uma/\d+')).Count,$sRows.Count,$cRows.Count) }
  if($sRows.Count -eq 0 -and $cRows.Count -eq 0){ Write-Host "  ${rid}: 取得0件—スキップ(既存維持)"; continue }
  DelRace $rid
  foreach($x in $sRows){ InsN $x $rid $dISO $v $rno; $tN++ }
  foreach($x in $cRows){ InsC $x $rid $dISO $v $rno; $tC++ }
  $done++; if($done % 12 -eq 0){ Write-Host ("  ...{0}/{1}レース" -f $done,$rids.Count) }
}
Write-Host ("✓ 完了: 能力指数 {0}行 / CPU {1}行 ({2}レース)" -f $tN,$tC,$rids.Count)
$conn.Close()
