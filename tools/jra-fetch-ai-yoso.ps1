<#
.SYNOPSIS
  中央競馬: 日刊スポーツ極ウマ「AI予想」(単勝馬印予測)を AI予想 テーブルへ取込。
.DESCRIPTION
  API: https://horse.ai-nikkansports.com (クライアントJS埋込キーで /auth/login → Bearer token)。
    - /predict/getPredictHorseWin    (raceDate=yyyymmdd, courseName=場名) … 過去アーカイブ(2022〜)
    - /predict/getPredictHorseWin_w  (同上) … 当週速報(前日/直前予想)。過去日は0件。
  各馬に predict_rank(AI順位) + predict_mark(◎◯▲☆) を付与。rank=1 が AI本命=軸候補。
  対象日 = レース情報(着順>0)の開催日 ∪ コンピ指数の開催日(当週/未来分)。各日その日の開催場へ問い合わせ。
  まず非_w(過去確定)→0件なら_w(当週速報)にフォールバック。冪等=(開催日×場)が既に取込済ならスキップ。
.PARAMETER From    開始日 yyyy-MM-dd。既定 2022-01-01。
.PARAMETER To      終了日 yyyy-MM-dd。既定=明後日(today+2)。
.PARAMETER SleepMs API間待機(既定250)。
#>
[CmdletBinding()]
param([string]$From='2022-01-01',[string]$To=((Get-Date).AddDays(2).ToString('yyyy-MM-dd')),[int]$SleepMs=250)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$log=Join-Path $PSScriptRoot '_ai_yoso.log'
function L($m){ $line=("{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$m); $line; $line|Out-File $log -Append -Encoding utf8 }
$ua="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36"
$curl="C:\Windows\System32\curl.exe"; $api="https://horse.ai-nikkansports.com"

# ---- token(クライアントJS埋込キー) ----
$tok=(& $curl -s -A $ua --max-time 40 -X POST "$api/auth/login" --data-urlencode "userId=zY7J3ptH" --data-urlencode "password=u7LMJFpy"|ConvertFrom-Json).access_token
if(-not $tok){ throw "AI予想API ログイン失敗" }
L "ログインOK。期間 $From 〜 $To"
$tStart=Get-Date
function ApiWin($date,$course,$w){ $ep= if($w){'getPredictHorseWin_w'}else{'getPredictHorseWin'}; $cn=[uri]::EscapeDataString($course); $r=& $curl -s -A $ua --max-time 40 -H "Authorization: Bearer $tok" "$api/predict/$ep`?raceDate=$date&courseName=$cn"; if($Global:LASTEXITCODE -ne 0){ return $null }; try{ @($r|ConvertFrom-Json) }catch{ $null } }

# ---- DB ----
$cs=(Get-Content (Join-Path $root '共通\appsettings.json') -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
$conn=New-Object System.Data.SqlClient.SqlConnection($cs);$conn.Open()
function Rows($sql,$p){ $c=$conn.CreateCommand();$c.CommandText=$sql;$c.CommandTimeout=180;foreach($k in $p.Keys){[void]$c.Parameters.AddWithValue($k,$p[$k])};$r=$c.ExecuteReader();$o=@();while($r.Read()){$row=[ordered]@{};for($i=0;$i -lt $r.FieldCount;$i++){$row[$r.GetName($i)]=$r.GetValue($i)};$o+=[pscustomobject]$row};$r.Close();$o }
function DbVal($v){ if($null -eq $v){[DBNull]::Value} elseif(($v -is [string]) -and ($v.Trim() -eq '')){[DBNull]::Value} else {$v} }

# 対象 開催日→場 (レース情報結果 ∪ コンピ指数=当週/未来)
$dv=@(Rows @"
SELECT DISTINCT 開催日 d,開催場所 v FROM (
  SELECT 開催日,開催場所 FROM レース情報 WHERE 開催日 BETWEEN @f AND @t AND 着順>0
  UNION SELECT 開催日,開催場所 FROM コンピ指数 WHERE 開催日 BETWEEN @f AND @t
) z ORDER BY 開催日,開催場所
"@ @{'@f'=$From;'@t'=$To})
L "対象(開催日×場): $($dv.Count)"

# 取込済(開催日×場)
$done=New-Object 'System.Collections.Generic.HashSet[string]'
foreach($x in (Rows "SELECT DISTINCT 開催日,開催場所 FROM AI予想" @{})){ [void]$done.Add(("{0:yyyy-MM-dd}|{1}" -f $x.開催日,$x.開催場所)) }
L "取込済 開催日×場: $($done.Count)"

$insSql=@"
IF NOT EXISTS(SELECT 1 FROM AI予想 WHERE 開催日=@d AND 開催場所=@v AND レース番号=@r AND 馬番=@no AND run_type=@run)
INSERT INTO AI予想(開催日,開催場所,レース番号,競走名,馬番,枠番,馬名,AI順位,AI印,race_type,run_type,predict_no,速報,取得日時,取得元)
VALUES(@d,@v,@r,@rn,@no,@waku,@nm,@rank,@mark,@rt,@run,@pno,@w,@時,N'gokuuma-ai')
"@
$insCmd=$conn.CreateCommand();$insCmd.CommandText=$insSql
$now=Get-Date;$tot=0;$tn=0
foreach($g in $dv){
  $d=([datetime]$g.d).ToString('yyyy-MM-dd'); $v=[string]$g.v; $key="$d|$v"
  if($done.Contains($key)){ continue }
  $ymd=([datetime]$d).ToString('yyyyMMdd')
  $rows=ApiWin $ymd $v $false; $w=0
  if(-not $rows -or $rows.Count -eq 0){ $rows=ApiWin $ymd $v $true; $w=1 }
  Start-Sleep -Milliseconds $SleepMs
  if(-not $rows -or $rows.Count -eq 0){ continue }
  $n=0
  foreach($p in $rows){
    if($null -eq $p.horse_number){ continue }
    $insCmd.Parameters.Clear()
    [void]$insCmd.Parameters.AddWithValue('@d',[datetime]$d)
    [void]$insCmd.Parameters.AddWithValue('@v',$v)
    [void]$insCmd.Parameters.AddWithValue('@r',[int]$p.race_number)
    [void]$insCmd.Parameters.AddWithValue('@rn',(DbVal $p.race_name))
    [void]$insCmd.Parameters.AddWithValue('@no',[int]$p.horse_number)
    [void]$insCmd.Parameters.AddWithValue('@waku',(DbVal $p.bracket_number))
    [void]$insCmd.Parameters.AddWithValue('@nm',(DbVal $p.horse_name))
    [void]$insCmd.Parameters.AddWithValue('@rank',(DbVal $p.predict_rank))
    [void]$insCmd.Parameters.AddWithValue('@mark',(DbVal $p.predict_mark))
    [void]$insCmd.Parameters.AddWithValue('@rt',(DbVal $p.race_type))
    [void]$insCmd.Parameters.AddWithValue('@run',(DbVal $p.run_type))
    [void]$insCmd.Parameters.AddWithValue('@pno',(DbVal $p.predict_no))
    [void]$insCmd.Parameters.AddWithValue('@w',$w)
    [void]$insCmd.Parameters.AddWithValue('@時',$now)
    [void]$insCmd.ExecuteNonQuery(); $n++
  }
  [void]$done.Add($key); $tot+=$n; $tn++
  if($tn % 30 -eq 0){ L "進捗 $tn/$($dv.Count) (直近 $d $v ${n}頭 / 累計 ${tot}頭)" }
}
$conn.Close()
L "==== AI予想取込 完了: $tn 開催日×場 / ${tot}頭行 / 経過 $([int]((Get-Date)-$tStart).TotalMinutes)分 ===="
