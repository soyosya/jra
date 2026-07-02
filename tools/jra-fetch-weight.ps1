<#
.SYNOPSIS
  中央競馬: JRA公式(jra.jp)の出馬表から「発走前の馬体重・増減」を取得し レース情報 を更新する。
.DESCRIPTION
  既存の取込(netkeiba db=結果ページ)は発走後の馬体重しか取れないため、当日カードの相手絞り(遠/休)用に
  JRA公式の出馬表(accessD・サーバ描画 Shift_JIS)からパドック発表後の馬体重を取得する専用スクリプト。
    導線: accessO(session) → accessD pw01dli00/F3(出馬表top) → pw01drl00{場}{年回日}{ymd}(開催別landing)
          → pw01des01{場}{年回日}{ymd}(その場の全レース出馬表=馬体重を1ページに含む) を解析。
  1場=1ページで全レースの 馬番→馬体重(増減) を取得し、レース情報 を UPDATE(発表済の馬のみ)。冪等。
  ※チェックサム(/B4等)は推測せず各ページのリンクから辿る(JRA仕様変更に強い)。Shift_JISはCodePages登録必須。
.PARAMETER Date    既定=当日。yyyy-MM-dd / yyyyMMdd。
.PARAMETER DryRun  DBを更新せず、解析結果(場×R×馬番→体重)の件数/サンプルのみ表示。
.OUTPUTS  更新(または解析)できた (場,R) 件数を最終行 "UPDATED|<件数>" で標準出力。
#>
[CmdletBinding()]
param([string]$Date=(Get-Date).ToString('yyyy-MM-dd'),[switch]$DryRun)
$ErrorActionPreference='Stop'
try { [System.Text.Encoding]::RegisterProvider([System.Text.CodePagesEncodingProvider]::Instance) } catch {}
$SJIS=[Text.Encoding]::GetEncoding(932)
$ymd=($Date -replace '[^0-9]','')
if($ymd.Length -ne 8){ throw "Date は yyyy-MM-dd で指定してください: $Date" }
$BASE='https://jra.jp'; $script:WS=$null
$VenueByCode=@{'01'='札幌';'02'='函館';'03'='福島';'04'='新潟';'05'='東京';'06'='中山';'07'='中京';'08'='京都';'09'='阪神';'10'='小倉'}

function Cn([string]$servlet,[string]$c){
  $a=@{Uri="$BASE/JRADB/$servlet";Method='Post';Body="cname=$c";ContentType='application/x-www-form-urlencoded';UseBasicParsing=$true;TimeoutSec=30}
  if($script:WS){$a.WebSession=$script:WS}else{$a.SessionVariable='nw'}
  $r=Invoke-WebRequest @a; if(-not $script:WS){$script:WS=$nw}
  return $SJIS.GetString($r.RawContentStream.ToArray())
}

# 1場の全レース出馬表ページから (レース番号, 馬番, 馬体重, 増減, 騎手, 斤量) を解析(セルclassベース)。
#   td.num=馬番 / td.h_weight="420<span>kg</span><span class="change">(+4)</span>"=馬体重(増減・任意) /
#   td.weight="52.0<span>kg</span>"=斤量 / td.jockey の<a>テキスト=騎手名(先頭の減量markは除外)。
#   ★馬体重はパドック発表後のみだが騎手/斤量は出馬表で常時取れる→馬番が取れた行は馬体重無しでも返す。
function Parse-Weights([string]$html){
  $rows=@()
  $hm=[regex]::Matches($html,'(\d{1,2})\s*レース')   # "Nレース" 見出しでブロック分割
  if($hm.Count -eq 0){ return ,@() }
  for($i=0;$i -lt $hm.Count;$i++){
    $rno=[int]$hm[$i].Groups[1].Value
    if($rno -lt 1 -or $rno -gt 12){ continue }
    $st=$hm[$i].Index; $en= if($i+1 -lt $hm.Count){$hm[$i+1].Index}else{$html.Length}
    $block=$html.Substring($st,$en-$st)
    foreach($trm in [regex]::Matches($block,'(?s)<tr[ >].*?</tr>')){
      $tr=$trm.Value
      $nm=[regex]::Match($tr,'<td class="num">\s*(\d{1,2})'); if(-not $nm.Success){ continue }
      $uma=[int]$nm.Groups[1].Value; if($uma -lt 1 -or $uma -gt 18){ continue }
      # 馬体重(増減)=任意。計不/発表前は$null。
      $w=$null; $d=0
      $wm=[regex]::Match($tr,'<td class="h_weight">\s*(\d{3})<span class="unit">kg</span>(?:\s*<span class="change">\s*[（(]\s*([+\-±]?\s*\d+)\s*[)）]\s*</span>)?')
      if($wm.Success){ $w=[int]$wm.Groups[1].Value
        if($wm.Groups[2].Success){ $dStr=($wm.Groups[2].Value -replace '\s','' -replace '±','+' -replace '＋','+' -replace '−','-'); [void][int]::TryParse(($dStr -replace '^\+',''),[ref]$d); if($dStr -match '^-'){ $d=-[math]::Abs($d) } } }
      # 斤量(td.weight)
      $kin=$null; $km=[regex]::Match($tr,'<td class="weight">\s*([0-9]+(?:\.[0-9])?)'); if($km.Success){ $kin=$km.Groups[1].Value }
      # 騎手(td.jockey の<a>テキスト・減量markのspanは除外)
      $jk=''; $jm=[regex]::Match($tr,'(?s)<td class="jockey">.*?<a[^>]*>\s*(.*?)\s*</a>'); if($jm.Success){ $jk=(($jm.Groups[1].Value -replace '<[^>]+>','') -replace '\s+',' ').Trim() }
      $rows+=[pscustomobject]@{R=$rno;馬番=$uma;馬体重=$w;増減=$d;騎手=$jk;斤量=$kin}
    }
  }
  return ,@($rows | Group-Object R,馬番 | ForEach-Object { $_.Group[0] })
}

# --- セッション確立 & 出馬表top ---
[void](Cn 'accessO.html' 'pw15oli00/6D')
$top = Cn 'accessD.html' 'pw01dli00/F3'
# 当日(ymd)の開催別landing cname を抽出: pw01drl00{場2}{年回日8}{ymd8}/{ck}
$landings=@{}
foreach($m in [regex]::Matches($top,"pw01drl00(\d{2})\d{8}$ymd/[0-9A-Za-z]{1,4}")){
  $code=$m.Value.Substring(9,2); $landings[$code]=$m.Value
}
if($landings.Count -eq 0){ Write-Output "対象なし($Date): 出馬表topに当日開催のlandingが見つかりません。"; Write-Output 'UPDATED|0'; return }

$cs=(Get-Content 'C:\jra\共通\appsettings.json' -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
$conn= if(-not $DryRun){ $c=New-Object System.Data.SqlClient.SqlConnection $cs; $c.Open(); $c } else { $null }
$updated=0; $parsed=0
try{
  foreach($code in ($landings.Keys | Sort-Object)){
    $venue=$VenueByCode[$code]
    $land = Cn 'accessD.html' $landings[$code]
    $desM=[regex]::Match($land,"pw01des01$code\d{8}$ymd/[0-9A-Za-z]{1,4}")
    if(-not $desM.Success){ $desM=[regex]::Match($land,"pw01des\d{2}$code\d{8}$ymd/[0-9A-Za-z]{1,4}") }
    if(-not $desM.Success){ Write-Output "  ${venue}: 出馬表(des)リンク未検出。スキップ"; continue }
    $uma = Cn 'accessD.html' $desM.Value
    $rows = Parse-Weights $uma
    $wcnt=@($rows | Where-Object { $null -ne $_.馬体重 }).Count; $jcnt=@($rows | Where-Object { $_.騎手 -ne '' }).Count
    $parsed += $wcnt
    Write-Output ("  {0}: 解析 {1}頭(馬体重{2}/騎手斤量{3})" -f $venue,$rows.Count,$wcnt,$jcnt)
    if($rows.Count -gt 0){ Write-Output ("    例: " + (($rows | Select-Object -First 4 | ForEach-Object { "R{0}-{1} {2} 斤{3} 体{4}" -f $_.R,$_.馬番,$_.騎手,$_.斤量,$(if($null -ne $_.馬体重){"{0}({1:+#;-#;±0})" -f $_.馬体重,$_.増減}else{'—'}) }) -join '  ')) }
    if(-not $DryRun){
      foreach($r in $rows){
        # 馬体重/増減: パドック発表済の馬のみ・値変化時のみ更新
        if($null -ne $r.馬体重){
          $cmd=$conn.CreateCommand()
          $cmd.CommandText="UPDATE レース情報 SET 馬体重=@w,馬体重増減=@d WHERE 開催日=@dt AND 開催場所=@v AND レース番号=@r AND 馬番=@u AND (馬体重 IS NULL OR LTRIM(RTRIM(CONVERT(varchar,馬体重)))='' OR TRY_CAST(馬体重 AS int) IS NULL OR TRY_CAST(馬体重 AS int)<>@w OR 馬体重増減 IS NULL OR TRY_CAST(馬体重増減 AS int) IS NULL OR TRY_CAST(馬体重増減 AS int)<>@d)"
          [void]$cmd.Parameters.AddWithValue('@w',$r.馬体重); [void]$cmd.Parameters.AddWithValue('@d',$r.増減)
          [void]$cmd.Parameters.AddWithValue('@dt',$Date); [void]$cmd.Parameters.AddWithValue('@v',$venue)
          [void]$cmd.Parameters.AddWithValue('@r',$r.R); [void]$cmd.Parameters.AddWithValue('@u',$r.馬番)
          $updated += $cmd.ExecuteNonQuery()
        }
        # 騎手/斤量: 出馬表で常時取得→DB側が空のときだけ充填(結果取込が後で正規データを入れるので上書きしない)
        $jk=$(if($r.騎手){$r.騎手}else{''}); $kin=$(if($r.斤量){$r.斤量}else{''})
        if($jk -ne '' -or $kin -ne ''){
          $cj=$conn.CreateCommand()
          $cj.CommandText="UPDATE レース情報 SET 騎手=CASE WHEN @jk<>'' AND (騎手 IS NULL OR LTRIM(RTRIM(騎手))='') THEN @jk ELSE 騎手 END, 斤量=CASE WHEN @kin<>'' AND (斤量 IS NULL OR LTRIM(RTRIM(CONVERT(varchar,斤量)))='' OR TRY_CAST(斤量 AS float) IS NULL OR TRY_CAST(斤量 AS float)=0) THEN @kin ELSE 斤量 END WHERE 開催日=@dt AND 開催場所=@v AND レース番号=@r AND 馬番=@u"
          [void]$cj.Parameters.AddWithValue('@jk',$jk); [void]$cj.Parameters.AddWithValue('@kin',$kin)
          [void]$cj.Parameters.AddWithValue('@dt',$Date); [void]$cj.Parameters.AddWithValue('@v',$venue)
          [void]$cj.Parameters.AddWithValue('@r',$r.R); [void]$cj.Parameters.AddWithValue('@u',$r.馬番)
          [void]$cj.ExecuteNonQuery()
        }
      }
    }
    Start-Sleep -Milliseconds 600
  }
} finally { if($conn){ $conn.Close() } }
Write-Output ("UPDATED|{0}" -f ($(if($DryRun){$parsed}else{$updated})))
