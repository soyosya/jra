<#
.SYNOPSIS
  当日の変更情報(発走時刻変更/取消/除外/天候/馬場)を「1R発走のChangeLeadMin分前」から「最終R発走+EndBufferMin」まで
  ChangeIntervalMin分間隔で取得し dbo.変更情報/レース情報/race-cancel.json に反映する常駐ループ。jra-fetch-changes.ps1を回す。
.PARAMETER Date              既定=当日。
.PARAMETER ChangeLeadMin     初R発走の何分前から開始(既定30・パラメータ化)。
.PARAMETER ChangeIntervalMin 取得間隔(分)(既定3・パラメータ化)。
.PARAMETER EndBufferMin      最終R発走+この分まで継続して終了(既定30)。
.PARAMETER Once              1回だけ取得して終了(検証用)。
.PARAMETER SkipResults       レース結果(競走結果+払戻金)取込+精算を行わない(変更情報のみ)。既定=結果も取込む。
#>
[CmdletBinding()]
param([string]$Date=(Get-Date).ToString('yyyy-MM-dd'),[int]$ChangeLeadMin=30,[int]$ChangeIntervalMin=3,[int]$EndBufferMin=30,[switch]$Once,[switch]$SkipResults)
$ErrorActionPreference='Continue'
try { [Console]::OutputEncoding=[Text.Encoding]::UTF8 } catch {}
$tools=$PSScriptRoot; $fetch=Join-Path $tools 'jra-fetch-changes.ps1'; $settle=Join-Path $tools 'jra-ipat-settle.ps1'
$root=Split-Path $tools -Parent
# ConsoleApp.exe(fetch-jra-official=競走結果+払戻金)探索(Release優先→新しいもの)。見つからなければ結果取込はスキップ。
$exe=$null
try{ $exe=(Get-ChildItem -Path (Join-Path $root 'ConsoleApp\bin') -Recurse -Filter 'ConsoleApp.exe' -ErrorAction SilentlyContinue | Sort-Object @{e={$_.FullName -match 'Release'}},LastWriteTime -Descending | Select-Object -First 1).FullName }catch{}
$cs=(Get-Content 'C:\jra\共通\appsettings.json' -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
function Rows($sql,$p){ $cn=New-Object System.Data.SqlClient.SqlConnection $cs;$cn.Open();$c=$cn.CreateCommand();$c.CommandText=$sql; if($p){foreach($k in $p.Keys){[void]$c.Parameters.AddWithValue($k,$p[$k])}}; $da=New-Object System.Data.SqlClient.SqlDataAdapter $c;$ds=New-Object System.Data.DataSet;$da.Fill($ds)|Out-Null;$cn.Close(); if($ds.Tables.Count){,$ds.Tables[0].Rows}else{,@()} }
function Log($m){ Write-Output ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'),$m) }

$meta=Rows "SELECT MIN(発走時刻) first,MAX(発走時刻) last FROM レース情報 WHERE 開催日=@d AND 発走時刻 IS NOT NULL" @{'@d'=$Date}
if(@($meta).Count -eq 0 -or $meta[0].first -is [DBNull]){ Log "対象なし($Date): 当日開催なし。終了。"; return }
$first=[datetime]$meta[0].first; $last=[datetime]$meta[0].last
$startAt=$first.AddMinutes(-$ChangeLeadMin); $endAt=$last.AddMinutes($EndBufferMin)
Log ("変更情報ループ: 初R{0} 最終R{1} / 取得 {2}〜{3} を {4}分間隔" -f $first.ToString('HH:mm'),$last.ToString('HH:mm'),$startAt.ToString('HH:mm'),$endAt.ToString('HH:mm'),$ChangeIntervalMin)

if(-not $Once){
  while((Get-Date) -lt $startAt){ $w=[Math]::Min(60,([math]::Ceiling((($startAt)-(Get-Date)).TotalSeconds))); if($w -le 0){break}; Start-Sleep -Seconds $w }
}
$cycle=0
while($true){
  $cycle++
  Log ("=== 変更情報取得 サイクル{0} ===" -f $cycle)
  try { & pwsh -NoProfile -File $fetch -Date $Date 2>&1 | ForEach-Object { Log "  $_" } } catch { Log ("  取得エラー: {0}" -f $_.Exception.Message) }
  # レース結果(競走結果+払戻金)も最新化→精算: 終了レースの着順/払戻/的中/収支を当日中に反映(ベストエフォート)。
  if(-not $SkipResults){
    if($exe){ try { & $exe fetch-jra-official $Date $Date 800 2>&1 | Select-Object -Last 1 | ForEach-Object { Log "  [結果取込] $_" } } catch { Log ("  結果取込エラー: {0}" -f $_.Exception.Message) } }
    else { Log "  [結果取込] ConsoleApp.exe未検出=スキップ" }
    try { & pwsh -NoProfile -File $settle -Date $Date 2>&1 | Where-Object{ "$_" -match 'SETTLED\||精算' } | ForEach-Object { Log "  [精算] $_" } } catch { Log ("  精算エラー: {0}" -f $_.Exception.Message) }
  }
  if($Once){ break }
  if((Get-Date) -ge $endAt){ Log "最終R+バッファを経過。終了。"; break }
  Start-Sleep -Seconds ($ChangeIntervalMin*60)
}
