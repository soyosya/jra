<#
.SYNOPSIS
  指定日(または期間)の全解析レースを投票履歴に一括記録するバッチ。過去日の埋め戻し用。
  blend(-ExportAll)で全レースを解析し、推奨=結果'計画'/推奨外=結果'推奨外'(いずれもモード'分析')で記録。
  既に記録済み(開催日+場名+レース番号)はスキップ=ライブ投票の記録を壊さない。
.DESCRIPTION
  実投票はしない(would-be買い目の記録のみ)。記録後 -Settle で精算まで一気に実行可能。
.PARAMETER Date    単日(yyyy-MM-dd)。-From/-To 指定時は無視。
.PARAMETER From/To 期間(両端含む)。
.PARAMETER Venue   場で絞る(未指定=全場)。
.PARAMETER FieldMax/EhMin/Partners/BetType  blend/記録の条件(既定は本命運用と同じ)。
.PARAMETER Settle  記録後に vote-settle.ps1 を各日実行(競走結果が出ている過去日向け)。
#>
[CmdletBinding()]
param(
  [string]$Date='', [string]$From='', [string]$To='', [string]$Venue='',
  [int]$FieldMax=8, [double]$EhMin=0.55, [int]$Partners=3,
  [string]$BetType='SanrenpukuNagashi', [switch]$Settle
)
$ErrorActionPreference='Stop'
$root = Split-Path $PSScriptRoot -Parent
$connStr=(Get-Content (Join-Path $root '共通\appsettings.json') -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
$blend = Join-Path $PSScriptRoot 'compi-today-blend.ps1'
$settleScript = Join-Path $PSScriptRoot 'vote-settle.ps1'
$pwsh = (Get-Command powershell.exe).Source
$tmpDir = Join-Path $env:TEMP 'compi-autovote'; New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
function Log($m){ Write-Host ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'),$m) }

# 記録対象の日付リスト
$dates=@()
if($From -and $To){ $d=[datetime]$From; $end=[datetime]$To; while($d -le $end){ $dates+=$d.ToString('yyyy-MM-dd'); $d=$d.AddDays(1) } }
elseif($Date){ $dates=@($Date) }
else { throw "日付を指定してください(-Date か -From/-To)" }

# テーブル保証
$cn=New-Object System.Data.SqlClient.SqlConnection $connStr; $cn.Open()
try{ $cmd=$cn.CreateCommand(); $cmd.CommandText=@'
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'投票履歴')
CREATE TABLE dbo.投票履歴 (
  Id INT IDENTITY(1,1) CONSTRAINT PK_投票履歴 PRIMARY KEY,
  投票日時 DATETIME2 NOT NULL, 開催日 DATE NOT NULL, 場名 NVARCHAR(20) NOT NULL,
  レース番号 INT NOT NULL, 式別 NVARCHAR(10) NOT NULL, 軸馬番 INT NOT NULL,
  相手馬番 NVARCHAR(50) NOT NULL, 点数 INT NOT NULL, 一点金額 INT NOT NULL,
  投票金額 INT NOT NULL, モード NVARCHAR(20) NOT NULL, 結果 NVARCHAR(20) NOT NULL,
  確定済 BIT NOT NULL CONSTRAINT DF_投票履歴_確定済 DEFAULT(0),
  的中 BIT NULL, 払戻金 INT NULL, 確定日時 DATETIME2 NULL);
'@; [void]$cmd.ExecuteNonQuery() } finally { $cn.Close() }

$isFuku = ($BetType -match 'Sanrenpuku|3puku|三連複')
$type = if($isFuku){'三連複'}else{'三連単'}
function Record-Row($r,$result){
  try{
    $rel = @(@($r.p1,$r.p2,$r.p3,$r.p4) | Where-Object { "$_" -ne '' }) | Select-Object -First $Partners
    $relC = @($rel).Count
    $opp = (@($rel) -join ',')
    $pts = if($isFuku){ if($relC -ge 2){[int]($relC*($relC-1)/2)}else{0} } else { [int](3*$relC*($relC-1)) }
    $unit = 100; $amt = $pts*$unit
    $cn=New-Object System.Data.SqlClient.SqlConnection $connStr; $cn.Open()
    try{
      $cmd=$cn.CreateCommand()
      $cmd.CommandText=@'
IF NOT EXISTS (SELECT 1 FROM dbo.投票履歴 WHERE 開催日=@d AND 場名=@v AND レース番号=@r)
INSERT INTO dbo.投票履歴 (投票日時,開催日,場名,レース番号,式別,軸馬番,相手馬番,点数,一点金額,投票金額,モード,結果,確定済)
VALUES (SYSDATETIME(),@d,@v,@r,@type,@ax,@opp,@pts,@unit,@amt,N'分析',@res,0);
'@
      [void]$cmd.Parameters.AddWithValue('@d',[datetime]$r.date)
      [void]$cmd.Parameters.AddWithValue('@v',[string]$r.venue)
      [void]$cmd.Parameters.AddWithValue('@r',[int]$r.race)
      [void]$cmd.Parameters.AddWithValue('@type',$type)
      [void]$cmd.Parameters.AddWithValue('@ax',[int]$r.axis_uma)
      [void]$cmd.Parameters.AddWithValue('@opp',$opp)
      [void]$cmd.Parameters.AddWithValue('@pts',$pts)
      [void]$cmd.Parameters.AddWithValue('@unit',$unit)
      [void]$cmd.Parameters.AddWithValue('@amt',$amt)
      [void]$cmd.Parameters.AddWithValue('@res',$result)
      return [int]$cmd.ExecuteNonQuery()   # 1=挿入 / 0=重複スキップ
    } finally { $cn.Close() }
  } catch { Log "  記録失敗 $($r.venue)$($r.race)R: $($_.Exception.Message)"; return 0 }
}

$grand=0
foreach($d in $dates){
  $allCsv = Join-Path $tmpDir ("rec_{0}.csv" -f ($d -replace '-',''))
  if(Test-Path $allCsv){ Remove-Item $allCsv -Force }
  $args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$blend,'-Date',$d,'-FieldMax',$FieldMax,'-EhMin',$EhMin,'-ExportAll',$allCsv)
  if($Venue){ $args+=@('-Venue',$Venue) }
  try{ & $pwsh @args 2>$null | Out-Null }catch{ Log "  ${d} 分析失敗: $($_.Exception.Message)" }
  if(-not (Test-Path $allCsv)){ Log "${d}: 解析対象なし(データ未取込?)"; continue }
  $rows = Import-Csv $allCsv -Encoding UTF8
  $ins=0; $rec=0; $skip=0
  foreach($r in $rows){
    $result = if("$($r.推奨)" -eq '1'){'計画'}else{'推奨外'}
    if($result -eq '計画'){ $rec++ }
    $n = Record-Row $r $result
    if($n -ge 1){ $ins++ } else { $skip++ }
  }
  Log ("{0}: 解析{1}レース(推奨{2}) → 新規記録{3} / 既存スキップ{4}" -f $d,$rows.Count,$rec,$ins,$skip)
  $grand+=$ins
  if($Settle){ & $pwsh -NoProfile -ExecutionPolicy Bypass -File $settleScript -Date $d | Out-Null; Log "  精算実行: $d" }
}
Log ("=== 完了: 新規記録 合計 {0} 件 / {1}日 ===" -f $grand,$dates.Count)
