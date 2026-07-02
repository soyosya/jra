<#
.SYNOPSIS
  中央競馬: 期間内に出走した全馬の成績を seiseki(全頭)から 競走成績 へ一括取込(per-race)。
.DESCRIPTION
  「完全データ」相当の履歴を、馬ごとkanzenより軽い per-race seiseki で蓄積する(約3倍軽い)。
    - 対象日 = レース情報(着順>0)の開催日(From..To)。実開催日のみ巡回(非開催日のnittei取得を回避)。
    - 各日: nittei から race_id(/cyuou/syutuba/{rid})を列挙。rid内の場コード(7-8字)+R(11-12字)で場名/Rを特定。
    - 各rid: /cyuou/seiseki/{rid} を取得し default seiseki テーブルの全出走馬行を解析(着順/本紙印/枠/騎手/
      重量/走破タイム/着差/通過1-4角/四角内外/寸評/前半3F/上り3F/人気/単勝オッズ/馬体重)→ 競走成績 へ。
    - レース条件(コース種別/距離/馬場/天候/レース名/頭数)は最後に netkeiba レース情報 を結合してUPDATE。
  冪等/再開: rid単位で取得元='keibabook-seiseki'が既にあればスキップ。行は umacd×競走key が無い時だけ挿入
            (6/20等のkanzen既存行と重複せず共存)。要ログイン(secrets.local.json)。
.PARAMETER From   開始日 yyyy-MM-dd。既定 2022-01-01。
.PARAMETER To     終了日 yyyy-MM-dd。既定=明後日(today+2)。
.PARAMETER SleepMs  seiseki取得間の待機(既定1000)。
.PARAMETER MaxRaces 動作確認用に処理レース数を制限(0=無制限)。
#>
[CmdletBinding()]
param(
  [string]$From='2022-01-01',
  [string]$To=((Get-Date).AddDays(2).ToString('yyyy-MM-dd')),
  [int]$SleepMs=1000,
  [int]$MaxRaces=0
)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$log=Join-Path $PSScriptRoot '_seiseki_range.log'
function L($m){ $line=("{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$m); $line; $line|Out-File $log -Append -Encoding utf8 }

# 場コード(競走key 7-8字)→場名。競走成績(中央)から実証済の対応。
$venueByCode=@{ '00'='京都';'01'='阪神';'02'='中京';'03'='小倉';'04'='東京';'05'='中山';'06'='福島';'07'='新潟';'08'='札幌';'09'='函館' }

# ---- ログイン ----
$ua="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36"
$curl="C:\Windows\System32\curl.exe"; $jar="$env:TEMP\kb_seiseki_range_cookies.txt"; $base="https://p.keibabook.co.jp"
if(Test-Path $jar){Remove-Item $jar -Force}
$page=& $curl -s -A $ua -b $jar -c $jar "$base/login/login"
$tok=[regex]::Match(($page -join "`n"),'name="_token"\s+value="([^"]+)"').Groups[1].Value
$sec=Get-Content (Join-Path $root 'secrets.local.json') -Raw|ConvertFrom-Json
$resp=& $curl -s -L -A $ua -b $jar -c $jar --data-urlencode "_token=$tok" --data-urlencode "login_id=$($sec.KeibabookUser)" --data-urlencode "pswd=$($sec.KeibabookPass)" --data-urlencode "service=keibabook" --data-urlencode "referer=" --data-urlencode "autologin=1" --data-urlencode "submitbutton=ログインする" "$base/login/login"
if([regex]::IsMatch(($resp -join "`n"),'name="pswd"')){ throw "競馬ブックログイン失敗(secrets確認)" }
L "ログインOK。期間 $From 〜 $To / sleep ${SleepMs}ms"
function Get-Html($url){
  $tmp=Join-Path $env:TEMP ("kb_sr_{0}.html" -f ([Guid]::NewGuid().ToString('N')))
  & $curl -s -A $ua -b $jar -c $jar -L --max-time 60 -o $tmp $url
  $h= if(Test-Path $tmp){ [IO.File]::ReadAllText($tmp,[Text.Encoding]::UTF8) } else { '' }
  if($h.Length -lt 2000){ Start-Sleep -Milliseconds 200; & $curl -s -A $ua -b $jar -c $jar -L --max-time 60 -o $tmp $url; $h= if(Test-Path $tmp){[IO.File]::ReadAllText($tmp,[Text.Encoding]::UTF8)}else{''} }
  if(Test-Path $tmp){ Remove-Item $tmp -Force }
  $h
}

# ---- DB ----
$cs=(Get-Content (Join-Path $root '共通\appsettings.json') -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
$conn=New-Object System.Data.SqlClient.SqlConnection($cs);$conn.Open()
function Rows($sql,$p){ $c=$conn.CreateCommand();$c.CommandText=$sql;$c.CommandTimeout=180;foreach($k in $p.Keys){[void]$c.Parameters.AddWithValue($k,$p[$k])};$r=$c.ExecuteReader();$o=@();while($r.Read()){$row=[ordered]@{};for($i=0;$i -lt $r.FieldCount;$i++){$row[$r.GetName($i)]=$r.GetValue($i)};$o+=[pscustomobject]$row};$r.Close();$o }

# 対象開催日(実結果ありの中央レース日)
$dr=@(Rows "SELECT DISTINCT 開催日 FROM レース情報 WHERE 開催日 BETWEEN @f AND @t AND 着順>0 ORDER BY 開催日" @{'@f'=$From;'@t'=$To})
$dates=@($dr | ForEach-Object { ([datetime]$_.開催日).ToString('yyyy-MM-dd') })
L "対象開催日: $($dates.Count)日"

# 既に seiseki 取得済の rid(再開時スキップ)
$done=New-Object 'System.Collections.Generic.HashSet[string]'
foreach($x in (Rows "SELECT DISTINCT 競走key FROM 競走成績 WHERE 取得元=N'keibabook-seiseki' AND 競走key IS NOT NULL" @{})){ [void]$done.Add([string]$x.競走key) }
L "取得済seiseki rid: $($done.Count)"

# 行挿入(umacd×競走keyが無ければ)。Clear+AddWithValueで型を値から推論(堅牢)。
$insSql=@"
IF NOT EXISTS(SELECT 1 FROM 競走成績 WHERE umacd=@uc AND 競走key=@key)
INSERT INTO 競走成績(umacd,馬名,開催日,競走key,中央地方,場名,レース番号,頭数,ゲート番,本紙印,単勝オッズ,人気,前半3F,後半3F,通過1角,通過2角,通過3角,通過4角,不利,四角内外,着順,走破タイム,着差,寸評,騎手,負担重量,馬体重,取得日時,取得元)
VALUES(@uc,@nm,@日,@key,N'中央',@場,@R,@tou,@gate,@mark,@odds,@nin,@f3,@b3,@c1,@c2,@c3,@c4,@huri,@io,@cyaku,@time,@sa,@sun,@kis,@kin,@bw,@時,N'keibabook-seiseki')
"@
$insCmd=$conn.CreateCommand(); $insCmd.CommandText=$insSql
function DbVal($v){ if($null -eq $v){[DBNull]::Value} elseif(($v -is [string]) -and ($v.Trim() -eq '')){[DBNull]::Value} else {$v} }
function Trunc2($s,$n){ if($null -eq $s){return $null}; $t="$s"; if($t.Length -gt $n){$t.Substring(0,$n)}else{$t} }

function ParseChaku($s){ if($s -match '^\d+'){[int]$Matches[0]}else{$null} }
function ToInt($s){ if("$s".Trim() -match '^-?\d+$'){[int]$s}else{$null} }
function ToDec($s){ $d=0.0; if([double]::TryParse("$s".Trim(),[ref]$d)){[decimal]$d}else{$null} }
function Strip($s){ ($s -replace '<[^>]+>',' ' -replace '&nbsp;',' ' -replace '\s+',' ').Trim() }

$totRaces=0;$totRows=0;$now=Get-Date;$dnum=0
foreach($d in $dates){
  $dnum++
  $nittei=Get-Html "$base/cyuou/nittei/$(([datetime]$d).ToString('yyyyMMdd'))"
  $rids=@([regex]::Matches($nittei,'/cyuou/syutuba/(\d{12})') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
  if($rids.Count -eq 0){ L "[$d] nittei rid 0 (会員アーカイブ外?スキップ)"; continue }
  $dayRaces=0;$dayRows=0
  foreach($rid in $rids){
    if($done.Contains($rid)){ continue }
    if($MaxRaces -gt 0 -and $totRaces -ge $MaxRaces){ break }
    $code=$rid.Substring(6,2); $ven=$venueByCode[$code]; if(-not $ven){ continue }
    $rno=[int]$rid.Substring(10,2)
    $html=Get-Html "$base/cyuou/seiseki/$rid"
    $i=$html.IndexOf('class="default seiseki"'); if($i -lt 0){ Start-Sleep -Milliseconds $SleepMs; continue }
    $bs=$html.IndexOf('<tbody',$i); if($bs -lt 0){ Start-Sleep -Milliseconds $SleepMs; continue }
    $be=$html.IndexOf('</tbody>',$bs); if($be -lt 0){ $be=$html.Length }
    $tbody=$html.Substring($bs,$be-$bs)
    $parsed=@()
    foreach($row in [regex]::Matches($tbody,'(?s)<tr[^>]*>(.*?)</tr>')){
      $rh=$row.Groups[1].Value
      $um=[regex]::Match($rh,'umacd="(\d+)"[^>]*>([^<]+)</a>'); if(-not $um.Success){ continue }
      $tds=@([regex]::Matches($rh,'(?s)<td[^>]*>(.*?)</td>') | ForEach-Object { Strip $_.Groups[1].Value })
      if($tds.Count -lt 20){ continue }
      $c1=$null;$c2=$null;$c3=$null;$c4=$null;$huri=$false
      foreach($t in [regex]::Matches($tds[12],'[①-⑳]|\d+')){
        $tv="$($t.Value)"; if($tv.Length -eq 0){ continue }
        $code2=[int]$tv[0]
        if($code2 -ge 0x2460 -and $code2 -le 0x2473){ $val=$code2-0x245F; $huri=$true }
        else { $val=$null; $tmp=0; if([int]::TryParse($tv,[ref]$tmp)){ $val=$tmp } }
        if($null -ne $val){ if($null -eq $c1){$c1=$val}elseif($null -eq $c2){$c2=$val}elseif($null -eq $c3){$c3=$val}else{$c4=$val} }
      }
      $parsed+=[pscustomobject]@{
        uc=$um.Groups[1].Value; nm=[System.Net.WebUtility]::HtmlDecode($um.Groups[2].Value).Trim()
        mark=$tds[2]; gate=(ToInt $tds[3]); kin=(ToDec $tds[7]); kis=$tds[9]; time=$tds[10]; sa=$tds[11]
        c1=$c1;c2=$c2;c3=$c3;c4=$c4;huri=$huri; io=$tds[13]; sun=(Strip $tds[14]); f3=(ToDec $tds[15]); b3=(ToDec $tds[16])
        nin=(ToInt $tds[17]); odds=(ToDec $tds[18]); bw=(ToInt $tds[19]); cyaku=(ParseChaku $tds[0])
      }
    }
    if($parsed.Count -eq 0){ Start-Sleep -Milliseconds $SleepMs; continue }
    $tou=$parsed.Count
    foreach($p in $parsed){
      $pv=[ordered]@{
        '@uc'=$p.uc; '@nm'=$p.nm; '@日'=[datetime]$d; '@key'=$rid; '@場'=$ven; '@R'=$rno; '@tou'=$tou;
        '@gate'=$p.gate; '@mark'=$p.mark; '@odds'=$p.odds; '@nin'=$p.nin; '@f3'=$p.f3; '@b3'=$p.b3;
        '@c1'=$p.c1; '@c2'=$p.c2; '@c3'=$p.c3; '@c4'=$p.c4; '@huri'=[int]([bool]$p.huri); '@io'=$p.io;
        '@cyaku'=$p.cyaku; '@time'=$p.time; '@sa'=$p.sa; '@sun'=(Trunc2 $p.sun 80); '@kis'=$p.kis; '@kin'=$p.kin; '@bw'=$p.bw; '@時'=$now
      }
      $insCmd.Parameters.Clear()
      foreach($k in $pv.Keys){ [void]$insCmd.Parameters.AddWithValue($k,(DbVal $pv[$k])) }
      [void]$insCmd.ExecuteNonQuery()
    }
    [void]$done.Add($rid)
    $dayRaces++;$dayRows+=$parsed.Count;$totRaces++;$totRows+=$parsed.Count
    Start-Sleep -Milliseconds $SleepMs
  }
  L "[$d] ($dnum/$($dates.Count)) 取込 ${dayRaces}R/${dayRows}頭  累計 ${totRaces}R/${totRows}頭"
  if($MaxRaces -gt 0 -and $totRaces -ge $MaxRaces){ L "MaxRaces到達"; break }
}
L "==== seiseki取込 完了: ${totRaces}レース / ${totRows}頭 ===="
# レース条件(コース種別/距離/馬場/天候/レース名)を netkeiba レース情報 から補完。
$enr=$conn.CreateCommand(); $enr.CommandTimeout=900
$enr.CommandText=@"
UPDATE s SET s.コース種別=m.k, s.距離=m.d, s.馬場=m.b, s.天候=m.t, s.レース名=m.rn
FROM 競走成績 s
JOIN (SELECT 開催日,開催場所,レース番号,MAX(コース種別)k,MAX(距離)d,MAX(NULLIF(馬場,N''))b,MAX(NULLIF(天候,N''))t,MAX(競走名)rn
      FROM レース情報 WHERE 着順>0 GROUP BY 開催日,開催場所,レース番号) m
  ON s.開催日=m.開催日 AND s.場名=m.開催場所 AND s.レース番号=m.レース番号
WHERE s.取得元=N'keibabook-seiseki' AND s.コース種別 IS NULL
"@
$upd=$enr.ExecuteNonQuery()
L "レース条件補完(レース情報結合 UPDATE): $upd 行"
$conn.Close()
