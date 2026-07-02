<#
.SYNOPSIS
  中央競馬: 未来レース(前日)の出馬表メタ + 出走馬を レース情報 に取り込む。
.DESCRIPTION
  競走結果(netkeiba)が無い前日でも jra-card / notify-jra-picks を動かせるよう、レース情報 を埋める。
    - レースメタ(発走時刻/コース種別/距離/条件/競走名)= 競馬ブック nittei(日程)ページ。
      例「1R My馬 3歳未勝利 (牝) ダ・1600m 調教 10:05」を解析。nitteiは本年分は非会員でも閲覧可。
    - 出走馬(馬番/馬名)= コンピ指数テーブル(事前に fetch-compi 済であること)。
  既定の personal 列(騎手/斤量/馬体重/着順 等)は未確定のためプレースホルダ(''/0)。
  jra-card が必要とする最小列(馬番/馬名/距離/コース種別/条件)は確実に埋まる。
  冪等: 対象日×開催場所に 着順>0(実結果) が1件でもあれば、その場はスキップ(実データを保護)。
        着順=0 の既存プレースホルダのみ DELETE→再INSERT。
.PARAMETER Date    既定=翌日(明日)。yyyy-MM-dd。
.PARAMETER DryRun  DB を変更せず、解析結果の件数/サンプルのみ表示。
#>
[CmdletBinding()]
param([string]$Date=((Get-Date).AddDays(1).ToString('yyyy-MM-dd')),[switch]$DryRun)
$ErrorActionPreference='Stop'
$ymd=([datetime]$Date).ToString('yyyyMMdd')

# ---- 1) nittei(日程)取得 ----
$ua="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36"
$jar="$env:TEMP\keibabook_noryoku_cookies.txt"; $curl="C:\Windows\System32\curl.exe"
# curl出力をファイル経由でUTF-8として読む(PS5.1のコンソール文字コード(CP932)誤読を回避)
$tmpf=Join-Path $env:TEMP ("kb_nittei_{0}.html" -f $ymd)
& $curl -s -A $ua -b $jar -c $jar --max-time 60 -o $tmpf "https://p.keibabook.co.jp/cyuou/nittei/$ymd"
$html= if(Test-Path $tmpf){ [IO.File]::ReadAllText($tmpf,[Text.Encoding]::UTF8) } else { '' }
if([string]::IsNullOrWhiteSpace($html) -or $html.Length -lt 2000){ throw "nittei取得失敗($Date)。length=$($html.Length)" }
$txt = $html -replace '<script[\s\S]*?</script>','' -replace '<style[\s\S]*?</style>','' `
             -replace '<[^>]+>',' ' -replace '&nbsp;',' ' -replace '\s+',' '

# ---- 2) 開催場所ブロックに分割 ----
$venueNames='東京|中山|阪神|京都|中京|新潟|福島|小倉|札幌|函館'
$vmatches=[regex]::Matches($txt,"\d+回($venueNames)\d+日目")
if($vmatches.Count -eq 0){ throw "nitteiに開催ブロックが見つからない($Date)。" }
$races=@()
for($i=0;$i -lt $vmatches.Count;$i++){
  $venue=$vmatches[$i].Groups[1].Value
  $start=$vmatches[$i].Index + $vmatches[$i].Length
  $end= if($i+1 -lt $vmatches.Count){ $vmatches[$i+1].Index } else { $txt.Length }
  $chunk=$txt.Substring($start,$end-$start)
  # 各レース: 「nR My馬 <名称> (芝|ダ)(内|外)?・距離m … 調教 HH:MM」
  $rm=[regex]::Matches($chunk,'(\d+)R\s+My馬\s+(.+?)\s+(芝|ダ)(?:内|外)?・(\d+)m(.*?)(\d{1,2}):(\d{2})')
  foreach($m in $rm){
    $rno=[int]$m.Groups[1].Value
    $rawname=$m.Groups[2].Value.Trim()
    $surf=$m.Groups[3].Value
    $dist=[int]$m.Groups[4].Value
    $hh=[int]$m.Groups[6].Value; $mi=[int]$m.Groups[7].Value
    $isFilly = $rawname -match '\(牝\)'
    $isJump  = ($rawname -match '障害') -or ($rawname -match '\(障\)')
    # 名称クリーン: (牝)(障)(指) 等の括弧タグ除去
    $name = ($rawname -replace '\([^)]*\)','').Trim()
    if($isJump){ $surf2='障' } else { $surf2=$surf }
    # 条件: クラス語を含めば条件、特別/Sは名称をそのまま条件にも流用
    $cond = $name
    if($isFilly -and ($cond -match '未勝利|新馬|勝クラス|オープン')){ $cond = "$cond 牝" }
    $races += [pscustomobject]@{ Venue=$venue; R=$rno; Surf=$surf2; Dist=$dist; Cond=$cond; Name=$name; HH=$hh; MI=$mi }
  }
}
"解析: 開催 $($vmatches.Count)場 / レース $($races.Count)件 ($Date)"
$races | Group-Object Venue | %{ "  {0}: {1}R" -f $_.Name,$_.Count }

# ---- 3) DB接続 / 出走馬(コンピ指数) ----
$cs=(Get-Content (Join-Path $PSScriptRoot '..\共通\appsettings.json') -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
$conn=New-Object System.Data.SqlClient.SqlConnection($cs);$conn.Open()
function Exec($sql,$p){ $c=$conn.CreateCommand();$c.CommandText=$sql;foreach($k in $p.Keys){[void]$c.Parameters.AddWithValue($k,$p[$k])};$c.ExecuteNonQuery() }
function Scalar($sql,$p){ $c=$conn.CreateCommand();$c.CommandText=$sql;foreach($k in $p.Keys){[void]$c.Parameters.AddWithValue($k,$p[$k])};$c.ExecuteScalar() }
function Rows($sql,$p){ $c=$conn.CreateCommand();$c.CommandText=$sql;foreach($k in $p.Keys){[void]$c.Parameters.AddWithValue($k,$p[$k])};$r=$c.ExecuteReader();$o=@();while($r.Read()){$row=[ordered]@{};for($i=0;$i -lt $r.FieldCount;$i++){$row[$r.GetName($i)]=$r.GetValue($i)};$o+=[pscustomobject]$row};$r.Close();,$o }

# 出走馬: コンピ指数の最新取得分(馬番/馬名)
$entrants=Rows @"
SELECT 開催場所 v,レース番号 r,馬番 no,馬名 nm FROM (
  SELECT *,ROW_NUMBER() OVER(PARTITION BY 開催場所,レース番号,馬番 ORDER BY 取得日時 DESC) rn
  FROM コンピ指数 WHERE 開催日=@d) t WHERE rn=1
"@ @{'@d'=$Date}
if($entrants.Count -eq 0){ $conn.Close(); throw "コンピ指数($Date)が未取得。fetch-compi を先に実行してください。" }
$entIdx=@{}
foreach($e in $entrants){ $k="$($e.v)|$([int]$e.r)"; if(-not $entIdx.ContainsKey($k)){$entIdx[$k]=@()}; $entIdx[$k]+=$e }

# ---- 4) 投入(冪等) ----
$allCols=@('開催場所','開催日','レース番号','発走時刻','コース種別','周回方向','距離','天候','馬場','条件','競走名',
  '一着賞金','二着賞金','三着賞金','四着賞金','五着賞金','着順','枠番','馬番','馬名','馬齢','性別','毛色',
  '騎手','騎手所属','斤量','斤量増減','減量記号','馬体重','馬体重増減','調教師','調教師所属','馬主',
  '変更情報','馬情報URL','騎手情報URL','調教師情報URL')
$colList=($allCols | %{ "[$_]" }) -join ','
$parList=($allCols | %{ "@$_" }) -join ','

$insVenues=@{}; $skipVenues=@{}; $totalIns=0; $noEnt=@()
foreach($v in ($races | Group-Object Venue)){
  $venue=$v.Name
  $hasResult=[int](Scalar "SELECT COUNT(*) FROM レース情報 WHERE 開催日=@d AND 開催場所=@v AND 着順>0" @{'@d'=$Date;'@v'=$venue})
  if($hasResult -gt 0){ $skipVenues[$venue]=$hasResult; continue }
  if(-not $DryRun){ [void](Exec "DELETE FROM レース情報 WHERE 開催日=@d AND 開催場所=@v AND 着順=0" @{'@d'=$Date;'@v'=$venue}) }
  foreach($rc in ($v.Group | Sort-Object R)){
    $key="$venue|$($rc.R)"
    $es = $entIdx[$key]
    if(-not $es){ $noEnt += $key; continue }
    $sou=[datetime]::ParseExact(("{0} {1:00}:{2:00}" -f $Date,$rc.HH,$rc.MI),'yyyy-MM-dd HH:mm',$null)
    foreach($e in ($es | Sort-Object {[int]$_.no})){
      if($DryRun){ $totalIns++; continue }
      # コンピ馬名の接頭辞(地=地方転入/外=外国産 等)+空白を除去し過去結果の馬名と一致させる。9字ガード。
      $nm=([string]$e.nm).Trim() -replace '^(地|外|父|抽|市|社|降)\s+',''
      if($nm.Length -gt 9){ $nm=$nm.Substring(0,9) }
      $p=@{
        '@開催場所'=$venue;'@開催日'=$Date;'@レース番号'=$rc.R;'@発走時刻'=$sou;'@コース種別'=$rc.Surf;'@周回方向'='';
        '@距離'=$rc.Dist;'@天候'='';'@馬場'='';'@条件'=$rc.Cond;'@競走名'=$rc.Name;
        '@一着賞金'=0;'@二着賞金'=0;'@三着賞金'=0;'@四着賞金'=0;'@五着賞金'=0;'@着順'=0;'@枠番'=0;
        '@馬番'=[int]$e.no;'@馬名'=$nm;'@馬齢'=0;'@性別'='';'@毛色'='';
        '@騎手'='';'@騎手所属'='';'@斤量'=0;'@斤量増減'=0;'@減量記号'='';'@馬体重'=0;'@馬体重増減'=0;
        '@調教師'='';'@調教師所属'='';'@馬主'='';'@変更情報'='';'@馬情報URL'='';'@騎手情報URL'='';'@調教師情報URL'=''
      }
      [void](Exec "INSERT INTO レース情報 ($colList) VALUES ($parList)" $p)
      $totalIns++
    }
    $insVenues[$venue]=([int]($insVenues[$venue]) + 1)
  }
}
$conn.Close()

"---- 結果($Date) ----"
if($DryRun){ "*** DryRun: DB未変更 ***" }
"投入行(出走馬): $totalIns"
foreach($k in $insVenues.Keys){ "  {0}: {1}R 投入" -f $k,$insVenues[$k] }
if($skipVenues.Count){ "実結果ありスキップ: " + (($skipVenues.GetEnumerator()|%{ "{0}({1}行)" -f $_.Key,$_.Value }) -join ', ') }
if($noEnt.Count){ "出走馬(コンピ)欠落: " + (($noEnt|Sort-Object -Unique) -join ', ') }
