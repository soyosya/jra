<#
.SYNOPSIS
  競馬ブック「推奨・ピックアップ」系ページを取得し ピックアップ / 自己ベスト調教 へ蓄積。
.DESCRIPTION
  対象カテゴリ(既定 best,hanasi,cyokyo)。各カテゴリの基底ページからナビ(日付×場)の
  詳細URLを発見し、各 (日付,場) を取得して race ブロックを解析。
    - 全カテゴリ: race_id/レース番号/馬番/umacd/馬名 を ピックアップ へ(カテゴリ別membership)。
    - best のみ: 旧(従来ベスト)/新(今回)の坂路・W時計2行を 自己ベスト調教 へ。
  会員ログイン(curl.exe)。開催毎更新なので 取得日時 スナップショットで蓄積(再取得は追記)。
  -Offline 指定時は C:\temp\kb_pickup_*.html / kb_best/hanasi/cyokyo を解析(解析開発用、DB書込なし)。
.PARAMETER Categories  既定 best,hanasi,cyokyo。
.PARAMETER Offline     ローカルHTMLを解析しDB書込しない(開発確認)。
#>
[CmdletBinding()] param(
  [string[]]$Categories=@('best','hanasi','cyokyo','cpubest'),
  [switch]$Offline
)
$ErrorActionPreference='Stop'
# ★2026-06-27: keibabook詳細ページがUTF-8化→PowerShellがcurl出力をCP932復号すると全角「：」が壊れ race：9,… が不一致=0行になる。
#   curl出力をUTF-8で復号するためConsole出力エンコーディングをUTF-8に固定(これが無いと解析が全滅)。
try { [Console]::OutputEncoding=[Text.Encoding]::UTF8; $OutputEncoding=[Text.Encoding]::UTF8 } catch {}
$connStr=(Get-Content 'C:\jra\共通\appsettings.json' -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
$ua="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36"
$curl="C:\Windows\System32\curl.exe"; $jar="$env:TEMP\keibabook_cookies.txt"
$base="https://p.keibabook.co.jp"
$catName=@{best='自己ベスト';hanasi='厩舎の話◎';cyokyo='矢印上向き';aisisuu='AI指数S';cpubest='コンピベスト5'}

function Login {
  if(Test-Path $jar){Remove-Item $jar -Force}
  $page=& $curl -s -A $ua -b $jar -c $jar "$base/login/login"
  $tok=[regex]::Match(($page -join "`n"),'name="_token"[^>]*value="(?<v>[^"]+)"').Groups['v'].Value
  if(-not $tok){ throw "ログイン_token取得失敗" }
  # 資格情報は secrets から取得
  $sec=Get-Content "C:\jra\secrets.local.json" -Raw | ConvertFrom-Json
  $resp=& $curl -s -L -A $ua -b $jar -c $jar `
    --data-urlencode "_token=$tok" `
    --data-urlencode "login_id=$($sec.KeibabookUser)" `
    --data-urlencode "pswd=$($sec.KeibabookPass)" `
    --data-urlencode "service=keibabook" --data-urlencode "referer=" `
    --data-urlencode "autologin=1" --data-urlencode "submitbutton=ログインする" "$base/login/login"
  if([regex]::IsMatch(($resp -join "`n"),'name="pswd"')){ throw "ログイン失敗(資格情報確認)" }
  Write-Host "競馬ブックにログインしました。"
}
function Fetch($url){ (& $curl -s -A $ua -b $jar -c $jar --max-time 60 $url) -join "`n" }

# --- 解析: race ブロック分割 ---
function Split-RaceBlocks($html){
  $blocks=@()
  $ms=[regex]::Matches($html,'race：9,(?<d>\d{8}),(?<vv>\d{2}),(?<rr>\d{2})')
  for($i=0;$i -lt $ms.Count;$i++){
    $start=$ms[$i].Index
    $end=if($i+1 -lt $ms.Count){$ms[$i+1].Index}else{$html.Length}
    $seg=$html.Substring($start,$end-$start)
    $rid=[regex]::Match($seg,'syutuba/(?<id>\d{12})').Groups['id'].Value
    $rname=[regex]::Match($seg,'syutuba/\d{12}>?"?>(?<n>[^<]+)</a>').Groups['n'].Value.Trim()
    $blocks+=[PSCustomObject]@{date=$ms[$i].Groups['d'].Value;vv=$ms[$i].Groups['vv'].Value;rr=[int]$ms[$i].Groups['rr'].Value;rid=$rid;rname=$rname;html=$seg}
  }
  ,$blocks
}
# --- 解析: 馬(membership) ---
function Parse-Horses($blockHtml){
  $list=@()
  foreach($m in [regex]::Matches($blockHtml,'<td class="waku"><p class="waku\d+">(?<no>\d+)</p></td>\s*<td class="left"><a href="?/db/uma/(?<u>\d+)"?[^>]*>(?<n>[^<]+)</a>')){
    $list+=[PSCustomObject]@{no=[int]$m.Groups['no'].Value;umacd=$m.Groups['u'].Value;name=$m.Groups['n'].Value.Trim()}
  }
  ,$list
}
# --- 解析: best 旧/新 明細(馬単位) ---
function Parse-BestDetail($blockHtml){
  # 馬の主行で分割
  $rows=@()
  $umaMs=[regex]::Matches($blockHtml,'<td class="waku"><p class="waku\d+">(?<no>\d+)</p></td>\s*<td class="left"><a href="?/db/uma/(?<u>\d+)"?[^>]*>(?<n>[^<]+)</a>')
  for($i=0;$i -lt $umaMs.Count;$i++){
    $no=[int]$umaMs[$i].Groups['no'].Value; $u=$umaMs[$i].Groups['u'].Value; $nm=$umaMs[$i].Groups['n'].Value.Trim()
    $s=$umaMs[$i].Index; $e=if($i+1 -lt $umaMs.Count){$umaMs[$i+1].Index}else{$blockHtml.Length}
    $seg=$blockHtml.Substring($s,$e-$s)
    foreach($tr in [regex]::Matches($seg,'<td class="mark">(?<k>旧|新)</td>(?<body>.*?)</tr>','Singleline')){
      $kubun=$tr.Groups['k'].Value; $b=$tr.Groups['body'].Value
      # td を順に抽出(タグ除去・trim)
      $tds=@(); foreach($t in [regex]::Matches($b,'<td[^>]*>(?<x>.*?)</td>','Singleline')){
        $tx=[regex]::Replace($t.Groups['x'].Value,'<[^>]+>',' '); $tx=[System.Net.WebUtility]::HtmlDecode($tx); $tds+=($tx -replace '\s+',' ').Trim()
      }
      # 期待順: 騎乗者,日付,コース,馬場,5F,半哩,3F,1F,回り位置,脚色,短評 (markは別途消費済)
      if($tds.Count -lt 11){ continue }
      $d=$tds[1]  # 26/3/22 (日)
      $dm=[regex]::Match($d,'(?<y>\d{2})/(?<mo>\d{1,2})/(?<da>\d{1,2})')
      $cyd=if($dm.Success){ ("20{0}-{1:D2}-{2:D2}" -f $dm.Groups['y'].Value,[int]$dm.Groups['mo'].Value,[int]$dm.Groups['da'].Value) }else{$null}
      $rows+=[PSCustomObject]@{no=$no;umacd=$u;name=$nm;区分=$kubun;騎乗者=$tds[0];調教日=$cyd;コース=$tds[2];馬場=$tds[3];
        F5=$tds[4];F半哩=$tds[5];F3=$tds[6];F1=$tds[7];回り位置=$tds[8];脚色=$tds[9];短評=$tds[10]}
    }
  }
  ,$rows
}
function Parse-Cpubest($html){
  # コンピ予想ベスト: 場内ランキング表。各行=順位/race_id/馬番/umacd/馬名/予想3%。
  $rows=@()
  foreach($m in [regex]::Matches($html,'<td>(?<rank>\d+)位</td>\s*<td><a href="/cyuou/syutuba/(?<rid>\d{12})">[^<]*</a></td>\s*<td class="center">(?<no>\d+)</td>\s*<td class="left"><a href="?/db/uma/(?<u>\d+)"?[^>]*>(?<n>[^<]+)</a>(?<rest>.*?)</tr>','Singleline')){
    $rid=$m.Groups['rid'].Value
    $pcts=@([regex]::Matches($m.Groups['rest'].Value,'(?<p>[\d.]+)%') | ForEach-Object { $_.Groups['p'].Value })
    $rows+=[PSCustomObject]@{rank=[int]$m.Groups['rank'].Value;rid=$rid;rr=[int]$rid.Substring(10,2);no=[int]$m.Groups['no'].Value;umacd=$m.Groups['u'].Value;name=$m.Groups['n'].Value.Trim();
      勝率=$(if($pcts.Count -ge 1){$pcts[0]}else{$null})}
  }
  ,$rows
}
function Cpubest-VenueMap($html){
  $map=@{}
  foreach($m in [regex]::Matches($html,'/cyuou/cpubest/\d{8}(?<c>\d{2})"[^>]*>\s*(?<n>[^<]+?)\s*</a>')){ $map[$m.Groups['c'].Value]=$m.Groups['n'].Value.Trim() }
  $map
}
function Parse-VenueMap($html){
  # keibajyo の各 li から 場コード→場名 を構築(コメント除去後)
  $map=@{}
  $kj=[regex]::Match($html,'class="keibajyo".*?</ul>','Singleline').Value
  $kj=[regex]::Replace($kj,'<!--.*?-->','','Singleline')
  foreach($m in [regex]::Matches($kj,'/(?:best|hanasi|cyokyo|aisisuu|cpubest)/\d{8}/(?<c>\d{2})[^"]*"[^>]*>\s*(?<n>[^<]+?)\s*</a>')){
    $map[$m.Groups['c'].Value]=$m.Groups['n'].Value.Trim()
  }
  $map
}
function ToNum($s){ $d=0.0; if([double]::TryParse(($s -replace '[^\d.]',''),[ref]$d)){ if($d -gt 0){return $d} }; return $null }

# ============ 実行 ============
if($Offline){
  foreach($cat in $Categories){
    if($cat -eq 'cpubest'){
      $f="C:\temp\kb_cpubest.html"; if(-not (Test-Path $f)){ Write-Host "skip(無): $f"; continue }
      $html=Get-Content $f -Raw -Encoding UTF8
      $rows=Parse-Cpubest $html
      Write-Host ("[コンピベスト5] membership{0}" -f $rows.Count)
      $rows | Select-Object -First 4 | ForEach-Object { "     {0}位 {1}R 馬番{2} {3} ({4}) 勝率{5}" -f $_.rank,$_.rr,$_.no,$_.name,$_.umacd,$_.勝率 }
      continue
    }
    $f="C:\temp\kb_pickup_$cat.html"; if($cat -eq 'best'){$f="C:\temp\kb_pickup_best.html"}
    if(-not (Test-Path $f)){ Write-Host "skip(無): $f"; continue }
    $html=Get-Content $f -Raw -Encoding UTF8
    $blocks=Split-RaceBlocks $html
    $venue=VenueName $html
    $totH=0; $totD=0
    foreach($bk in $blocks){
      $hs=Parse-Horses $bk.html; $totH+=$hs.Count
      if($cat -eq 'best'){ $totD+=(Parse-BestDetail $bk.html).Count }
    }
    Write-Host ("[{0}] 場={1} レース{2} / 馬(membership){3}{4}" -f $catName[$cat],$venue,$blocks.Count,$totH,$(if($cat -eq 'best'){" / 明細行$totD"}else{''}))
    if($blocks.Count -gt 0){
      $b=$blocks[0]; $hs=Parse-Horses $b.html
      Write-Host ("  例) {0}R {1} race_id={2}: " -f $b.rr,$b.rname,$b.rid)
      $hs | Select-Object -First 3 | ForEach-Object { "     馬番$($_.no) $($_.name) ($($_.umacd))" }
      if($cat -eq 'best'){ Parse-BestDetail $b.html | Select-Object -First 2 | ForEach-Object { "     [$($_.区分)] $($_.調教日) $($_.コース) 5F=$($_.F5) 1F=$($_.F1) 脚色=$($_.脚色) 短評=$($_.短評)" } }
    }
  }
  return
}

# --- オンライン: ログイン→発見→取得→DB ---
Login
$conn=New-Object System.Data.SqlClient.SqlConnection($connStr); $conn.Open()
$now=Get-Date
function Ins-Pickup($p){ $c=$conn.CreateCommand()
  $c.CommandText="INSERT INTO ピックアップ(取得日時,開催日,場コード,開催場所,race_id,レース番号,レース名,馬番,umacd,馬名,カテゴリ,順位,単勝,結果) VALUES(@t,@d,@vv,@vn,@rid,@rn,@rname,@no,@u,@nm,@cat,@rank,@tan,@res)"
  $a=@{'@t'=$now;'@d'=$p.date;'@vv'=$p.vv;'@vn'=$p.vn;'@rid'=$p.rid;'@rn'=$p.rn;'@rname'=$p.rname;'@no'=$p.no;'@u'=$p.u;'@nm'=$p.nm;'@cat'=$p.cat;'@rank'=$p.rank;'@tan'=$p.tan;'@res'=$p.res}
  foreach($k in $a.Keys){ [void]$c.Parameters.AddWithValue($k,$(if($null -eq $a[$k]){[DBNull]::Value}else{$a[$k]})) }; [void]$c.ExecuteNonQuery() }
function Ins-Best($p){ $c=$conn.CreateCommand()
  $c.CommandText="INSERT INTO 自己ベスト調教(取得日時,開催日,場コード,race_id,レース番号,馬番,umacd,馬名,区分,騎乗者,調教日,コース,馬場,F5,F半哩,F3,F1,回り位置,脚色,短評) VALUES(@t,@d,@vv,@rid,@rn,@no,@u,@nm,@kb,@nr,@cd,@co,@ba,@f5,@fh,@f3,@f1,@mi,@as,@tp)"
  $a=@{'@t'=$now;'@d'=$p.date;'@vv'=$p.vv;'@rid'=$p.rid;'@rn'=$p.rn;'@no'=$p.no;'@u'=$p.u;'@nm'=$p.nm;'@kb'=$p.区分;'@nr'=$p.騎乗者;'@cd'=$p.調教日;'@co'=$p.コース;'@ba'=$p.馬場;'@f5'=(ToNum $p.F5);'@fh'=(ToNum $p.F半哩);'@f3'=(ToNum $p.F3);'@f1'=(ToNum $p.F1);'@mi'=$p.回り位置;'@as'=$p.脚色;'@tp'=$p.短評}
  foreach($k in $a.Keys){ [void]$c.Parameters.AddWithValue($k,$(if($null -eq $a[$k] -or $a[$k] -eq ''){[DBNull]::Value}else{$a[$k]})) }; [void]$c.ExecuteNonQuery() }

function Norm($yyyymmdd){ "{0}-{1}-{2}" -f $yyyymmdd.Substring(0,4),$yyyymmdd.Substring(4,2),$yyyymmdd.Substring(6,2) }
# 取得結果(メモリ)が非空のときだけ 削除+挿入。空取得では既存を消さない(レート制限/失敗での消失防止)。
function Replace-Category($catLabel,$memberRows,$bestRows,$dates){
  if($memberRows.Count -eq 0){ Write-Host "[$catLabel] 取得0件 — 既存データ維持(削除しません)"; return }
  $dl=(@($dates | Select-Object -Unique) | ForEach-Object { "'$_'" }) -join ','
  $c=$conn.CreateCommand(); $c.CommandText="DELETE FROM ピックアップ WHERE カテゴリ=N'$catLabel' AND 開催日 IN ($dl)"; [void]$c.ExecuteNonQuery()
  if($catLabel -eq '自己ベスト'){ $c.CommandText="DELETE FROM 自己ベスト調教 WHERE 開催日 IN ($dl)"; [void]$c.ExecuteNonQuery() }
  foreach($m in $memberRows){ Ins-Pickup $m }
  foreach($b in $bestRows){ Ins-Best $b }
}

$totalP=0;$totalB=0
foreach($cat in $Categories){
  $memberRows=New-Object System.Collections.Generic.List[object]
  $bestRows=New-Object System.Collections.Generic.List[object]
  $dateset=@{}
  if($cat -eq 'cpubest'){
    $bhtml=Fetch "$base/cyuou/cpubest"
    $pairs=@([regex]::Matches($bhtml,'/cyuou/cpubest/(?<d>\d{8})(?<v>\d{2})') | ForEach-Object { "$($_.Groups['d'].Value)/$($_.Groups['v'].Value)" } | Select-Object -Unique)
    if($pairs.Count -eq 0){ Write-Host "[コンピベスト5] 詳細URL無し(未掲載?)"; continue }
    foreach($pv in $pairs){
      $d=$pv.Split('/')[0]; $vv=$pv.Split('/')[1]; $dd=Norm $d; $dateset[$dd]=1
      $html=Fetch "$base/cyuou/cpubest/$d$vv"
      $vmap=Cpubest-VenueMap $html; $vn=$vmap[$vv]
      foreach($row in (Parse-Cpubest $html)){
        $memberRows.Add(@{date=$dd;vv=$vv;vn=$vn;rid=$row.rid;rn=$row.rr;rname=$null;no=$row.no;u=$row.umacd;nm=$row.name;cat='コンピベスト5';rank=$row.rank;tan=$null;res=$null})
      }
      Start-Sleep -Milliseconds 800
    }
    Replace-Category 'コンピベスト5' $memberRows $bestRows @($dateset.Keys)
  } else {
    $bhtml=Fetch "$base/cyuou/pickup/$cat"
    $pairs=@([regex]::Matches($bhtml,"/cyuou/pickup/$cat/(?<d>\d{8})/(?<v>\d{2})") | ForEach-Object { "$($_.Groups['d'].Value)/$($_.Groups['v'].Value)" } | Select-Object -Unique)
    if($pairs.Count -eq 0){ Write-Host "[$($catName[$cat])] 詳細URL無し(未掲載?)"; continue }
    $urls=@($pairs | ForEach-Object { if($cat -eq 'best'){ "/cyuou/pickup/$cat/$_/9999" } else { "/cyuou/pickup/$cat/$_" } })
    foreach($rel in $urls){
      $html=Fetch "$base$rel"
      $vmap=Parse-VenueMap $html
      foreach($bk in (Split-RaceBlocks $html)){
        $dd=Norm $bk.date; $dateset[$dd]=1; $vn=$vmap[$bk.vv]
        foreach($h in (Parse-Horses $bk.html)){
          $memberRows.Add(@{date=$dd;vv=$bk.vv;vn=$vn;rid=$bk.rid;rn=$bk.rr;rname=$bk.rname;no=$h.no;u=$h.umacd;nm=$h.name;cat=$catName[$cat];rank=$null;tan=$null;res=$null})
        }
        if($cat -eq 'best'){
          foreach($d in (Parse-BestDetail $bk.html)){
            $bestRows.Add(@{date=$dd;vv=$bk.vv;rid=$bk.rid;rn=$bk.rr;no=$d.no;u=$d.umacd;nm=$d.name;区分=$d.区分;騎乗者=$d.騎乗者;調教日=$d.調教日;コース=$d.コース;馬場=$d.馬場;F5=$d.F5;F半哩=$d.F半哩;F3=$d.F3;F1=$d.F1;回り位置=$d.回り位置;脚色=$d.脚色;短評=$d.短評})
          }
        }
      }
      Start-Sleep -Milliseconds 800
    }
    Replace-Category $catName[$cat] $memberRows $bestRows @($dateset.Keys)
  }
  $totalP+=$memberRows.Count; $totalB+=$bestRows.Count
  Write-Host ("[{0}] membership{1}{2}" -f $catName[$cat],$memberRows.Count,$(if($cat -eq 'best'){" / 明細$($bestRows.Count)"}else{''}))
}
Write-Host ("✓ 完了: ピックアップ {0}行 / 自己ベスト調教 {1}行" -f $totalP,$totalB)
$conn.Close()
