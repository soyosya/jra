<#
.SYNOPSIS
  指定日(既定=当日)の各レースの単複オッズをJRA公式から取得し dbo.リアルタイムオッズ に書き込む(買目ページ /buyme の 単勝(現)/複勝(現)/人気 用)。
.DESCRIPTION
  jra-fetch-odds.ps1(1レース単複→JSON)を各レースに対して呼び、人気=単勝オッズ昇順で導出して リアルタイムオッズ をレース単位で洗替INSERT。
  既定は「発走がまだ先(発走>now-StaleMin)」のレースのみ取得(確定済の過去レースは確定払戻で見るため除外=負荷軽減)。-All で全レース。
  オッズは1分単位で動くので jra-odds-loop.ps1 から定期実行する。
.PARAMETER Date     対象日 yyyy-MM-dd。既定=当日。
.PARAMETER All      全レース取得(既定=未発走のみ)。
.PARAMETER StaleMin 発走からこの分数までは取得対象に含める(発走直後の確定オッズ反映用。既定2)。
.OUTPUTS  ODDS|<書込レース数>|<書込頭数>
#>
[CmdletBinding()]
param([string]$Date=(Get-Date).ToString('yyyy-MM-dd'),[switch]$All,[int]$StaleMin=2)
$ErrorActionPreference='Continue'
try { [Console]::OutputEncoding=[Text.Encoding]::UTF8 } catch {}
$tools=$PSScriptRoot
$fetchOdds=Join-Path $tools 'jra-fetch-odds.ps1'
$cs=(Get-Content 'C:\jra\共通\appsettings.json' -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
function Rows($sql,$p){ $cn=New-Object System.Data.SqlClient.SqlConnection $cs;$cn.Open();$c=$cn.CreateCommand();$c.CommandText=$sql; if($p){foreach($k in $p.Keys){[void]$c.Parameters.AddWithValue($k,$p[$k])}}; $da=New-Object System.Data.SqlClient.SqlDataAdapter $c;$ds=New-Object System.Data.DataSet;$da.Fill($ds)|Out-Null;$cn.Close(); if($ds.Tables.Count){,$ds.Tables[0].Rows}else{,@()} }
function ToNum($s){ $o=0.0; if([double]::TryParse((("$s") -replace '[^0-9.]',''),[ref]$o)){ return $o }; return $null }

# 対象レース(場/R/発走時刻)
$races = Rows "SELECT DISTINCT 開催場所 v,レース番号 r,MIN(発走時刻) post FROM dbo.レース情報 WHERE 開催日=@d GROUP BY 開催場所,レース番号 ORDER BY 開催場所,レース番号" @{'@d'=$Date}
if(@($races).Count -eq 0){ Write-Output "対象なし($Date): レース情報無し。"; Write-Output 'ODDS|0|0'; return }
# 既にオッズがあるレース(場|R)=終了済はオッズ確定後に再取得しない(発走前から取り込めなかった早朝レースは確定オッズを一度だけ取得=自己修復)。
$hasOdds=@{}
foreach($x in (Rows "SELECT DISTINCT 開催場所 v,レース番号 r FROM dbo.リアルタイムオッズ WHERE 開催日=@d" @{'@d'=$Date})){ $hasOdds["$($x.v)|$($x.r)"]=$true }
$now=Get-Date
$conn=New-Object System.Data.SqlClient.SqlConnection $cs; $conn.Open()
$wroteR=0; $wroteN=0
try{
  foreach($row in $races){
    $v=[string]$row.v; $r=[int]$row.r
    if(-not $All -and $row.post -isnot [DBNull]){
      $mins=([datetime]$row.post - $now).TotalMinutes
      # 終了済(発走からStaleMin超過)かつ既にオッズあり→スキップ。終了済でもオッズ未取得なら確定オッズを一度取得(早朝レースの自己修復)。
      if($mins -lt -$StaleMin -and $hasOdds.ContainsKey("$v|$r")){ continue }
    }
    # 単複オッズをJSONで取得
    $tmp="C:\temp\jra_odds_{0}_{1}_{2}R.json" -f ($Date -replace '-',''),$v,$r
    try { & $fetchOdds -Date $Date -Venue $v -Race $r -Type tanpuku -OutJson $tmp *>$null } catch { continue }
    if(-not (Test-Path $tmp)){ continue }
    $j= try { Get-Content $tmp -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $null }
    if(-not $j -or -not $j.tanpuku -or @($j.tanpuku).Count -eq 0){ continue }
    # 人気=単勝オッズ昇順
    $list=@($j.tanpuku | ForEach-Object { [pscustomobject]@{ uma=[int]$_.umaban; name=[string]$_.name; tan=(ToNum $_.tan); fmin=(ToNum $_.fuku_min); fmax=(ToNum $_.fuku_max) } })
    $ranked=@($list | Where-Object { $_.tan -ne $null } | Sort-Object tan)
    $pop=@{}; for($i=0;$i -lt $ranked.Count;$i++){ $pop[$ranked[$i].uma]=$i+1 }
    # レース単位で洗替(最新スナップショット)
    $del=$conn.CreateCommand(); $del.CommandText="DELETE FROM dbo.リアルタイムオッズ WHERE 開催日=@d AND 開催場所=@v AND レース番号=@r"
    [void]$del.Parameters.AddWithValue('@d',$Date);[void]$del.Parameters.AddWithValue('@v',$v);[void]$del.Parameters.AddWithValue('@r',$r); [void]$del.ExecuteNonQuery()
    foreach($x in $list){
      $ins=$conn.CreateCommand()
      $ins.CommandText="INSERT INTO dbo.リアルタイムオッズ(開催場所,開催日,レース番号,馬番,馬名,単勝オッズ,複勝オッズ,複勝オッズ_MIN,複勝オッズ_MAX,人気,日時) VALUES(@v,@d,@r,@u,@nm,@tan,@fk,@fmin,@fmax,@pop,SYSDATETIME())"
      [void]$ins.Parameters.AddWithValue('@v',$v);[void]$ins.Parameters.AddWithValue('@d',$Date);[void]$ins.Parameters.AddWithValue('@r',$r)
      [void]$ins.Parameters.AddWithValue('@u',$x.uma);[void]$ins.Parameters.AddWithValue('@nm',[object]$x.name ?? [DBNull]::Value)
      [void]$ins.Parameters.AddWithValue('@tan',[object]$x.tan ?? [DBNull]::Value)
      [void]$ins.Parameters.AddWithValue('@fk',[object]$x.fmin ?? [DBNull]::Value)
      [void]$ins.Parameters.AddWithValue('@fmin',[object]$x.fmin ?? [DBNull]::Value)
      [void]$ins.Parameters.AddWithValue('@fmax',[object]$x.fmax ?? [DBNull]::Value)
      [void]$ins.Parameters.AddWithValue('@pop',[object]($pop[$x.uma]) ?? [DBNull]::Value)
      [void]$ins.ExecuteNonQuery(); $wroteN++
    }
    $wroteR++
    Write-Output ("  {0} {1}R: 単複{2}頭 書込" -f $v,$r,$list.Count)
  }
} finally { $conn.Close() }
Write-Output ("ODDS|{0}|{1}" -f $wroteR,$wroteN)
