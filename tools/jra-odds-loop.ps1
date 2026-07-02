<#
.SYNOPSIS
  当日の単複オッズ(+人気)を「1R発走のLeadMin分前」から「最終R発走+EndBufferMin」まで OddsIntervalMin分間隔で取得し
  dbo.リアルタイムオッズ に反映する常駐ループ(買目ページ /buyme の 単勝(現)/複勝(現)/人気 を最新化)。jra-odds-to-db.ps1を回す。
.PARAMETER Date            既定=当日。
.PARAMETER OddsIntervalMin 取得間隔(分)(既定5・パラメータ化)。
.PARAMETER LeadMin         初R発走の何分前から開始(既定30)。
.PARAMETER EndBufferMin    最終R発走+この分まで継続(既定5)。
.PARAMETER Once            1回だけ取得して終了(検証用)。
#>
[CmdletBinding()]
param([string]$Date=(Get-Date).ToString('yyyy-MM-dd'),[int]$OddsIntervalMin=5,[int]$LeadMin=30,[int]$EndBufferMin=5,[switch]$Once)
$ErrorActionPreference='Continue'
try { [Console]::OutputEncoding=[Text.Encoding]::UTF8 } catch {}
$tools=$PSScriptRoot; $oddsDb=Join-Path $tools 'jra-odds-to-db.ps1'
$cs=(Get-Content 'C:\jra\共通\appsettings.json' -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
function Rows($sql,$p){ $cn=New-Object System.Data.SqlClient.SqlConnection $cs;$cn.Open();$c=$cn.CreateCommand();$c.CommandText=$sql; if($p){foreach($k in $p.Keys){[void]$c.Parameters.AddWithValue($k,$p[$k])}}; $da=New-Object System.Data.SqlClient.SqlDataAdapter $c;$ds=New-Object System.Data.DataSet;$da.Fill($ds)|Out-Null;$cn.Close(); if($ds.Tables.Count){,$ds.Tables[0].Rows}else{,@()} }
function Log($m){ Write-Output ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'),$m) }

$meta=Rows "SELECT MIN(発走時刻) first,MAX(発走時刻) last FROM レース情報 WHERE 開催日=@d AND 発走時刻 IS NOT NULL" @{'@d'=$Date}
if(@($meta).Count -eq 0 -or $meta[0].first -is [DBNull]){ Log "対象なし($Date): 当日開催なし。終了。"; return }
$first=[datetime]$meta[0].first; $last=[datetime]$meta[0].last
$startAt=$first.AddMinutes(-$LeadMin); $endAt=$last.AddMinutes($EndBufferMin)
Log ("オッズループ: 初R{0} 最終R{1} / 取得 {2}〜{3} を {4}分間隔" -f $first.ToString('HH:mm'),$last.ToString('HH:mm'),$startAt.ToString('HH:mm'),$endAt.ToString('HH:mm'),$OddsIntervalMin)

if(-not $Once){
  while((Get-Date) -lt $startAt){ $w=[Math]::Min(60,([math]::Ceiling((($startAt)-(Get-Date)).TotalSeconds))); if($w -le 0){break}; Start-Sleep -Seconds $w }
}
$cycle=0
while($true){
  $cycle++
  Log ("=== オッズ取得 サイクル{0} ===" -f $cycle)
  try { & pwsh -NoProfile -File $oddsDb -Date $Date 2>&1 | ForEach-Object { Log "  $_" } } catch { Log ("  取得エラー: {0}" -f $_.Exception.Message) }
  if($Once){ break }
  if((Get-Date) -ge $endAt){ Log "最終R+バッファを経過。終了。"; break }
  Start-Sleep -Seconds ($OddsIntervalMin*60)
}
