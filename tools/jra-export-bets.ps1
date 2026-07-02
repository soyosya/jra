<#
.SYNOPSIS
  jra-card の軸/相手を IpatVote 買目CSV(date,venue,race,bettype,method,axis,partners,stake)へ書き出す。
.DESCRIPTION
  対象日の各開催場で jra-card -Notify を実行→「軸:◎… N馬名 相手:○… M馬名 …」を解析し買目化。
  既定は 三連複・軸1頭流し(軸=◎/注の馬番, 相手=○の馬番上位N)。危険(注危/△危)や▼降の軸は -SkipRisk で除外可。
  ※買目を作るだけ(投票はしない)。IpatVote <csv> --mode DryRun で確認、ConfirmStopで人が最終操作。
.PARAMETER Date 対象日。 .PARAMETER BetType 三連複等。 .PARAMETER Method 流し等。 .PARAMETER Stake 一点金額。 .PARAMETER SkipRisk 危/▼降の軸レースを除外。 .PARAMETER Out 出力CSV。
#>
[CmdletBinding()]
param([string]$Date=((Get-Date).ToString('yyyy-MM-dd')),[string]$BetType='三連複',[string]$Method='流し',[int]$Stake=100,[int]$Partners=5,[int]$FrontFlat=0,[switch]$SkipRisk,[string]$Out="C:\temp\ipat_bets_$((Get-Date).ToString('yyyyMMdd')).csv")
# FrontFlat: ≤このR(レース番号)を1点100円固定(前半フラット)・0=無効
$ErrorActionPreference='Stop'
$card=Join-Path $PSScriptRoot 'jra-card.ps1'
$appsettings=Join-Path $PSScriptRoot '..\共通\appsettings.json'
$cs=(Get-Content $appsettings -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
$conn=New-Object System.Data.SqlClient.SqlConnection($cs);$conn.Open()
$cmd=$conn.CreateCommand();$cmd.CommandText="SELECT DISTINCT 開催場所 FROM レース情報 WHERE 開催日=@d ORDER BY 開催場所";[void]$cmd.Parameters.AddWithValue('@d',$Date)
$r=$cmd.ExecuteReader();$venues=@();while($r.Read()){$venues+=[string]$r['開催場所']};$r.Close();$conn.Close()
if($venues.Count -eq 0){ "レース情報が未取得($Date)。fetch-compi/jra-fetch-shutuba を先に。"; return }

$rows=New-Object System.Collections.Generic.List[string]
$rows.Add('date,venue,race,bettype,method,axis,partners,stake')
$n=0
foreach($v in $venues){
  # ExportBets: 機械可読「EXPORT|R|距離|軸馬番|軸評価|相手馬番カンマ」。相手=総合上位N(消除く)。
  $lines=& $card -Date $Date -Venue $v -ExportBets -ExportN $Partners 2>$null
  foreach($ln in $lines){
    if("$ln" -notlike 'EXPORT|*'){ continue }
    $f=("$ln" -split '\|')
    $rno=[int]$f[1]; $ax=$f[3]; $axlab=$f[4]; $plist=@(($f[5] -split ',') | Where-Object { $_ -ne '' })  # ※$Partners(param)と大小同一で衝突するため別名
    if($SkipRisk -and ($axlab -match '危|▼降')){ continue }     # 危険/指数下降の軸は除外
    # 式別ごとの最低相手数(三連系=2/連単複=1/単複=0)。不足は買目化しない(0点回避)。
    $minP= if($BetType -match '三連|3連'){2} elseif($BetType -match '単勝|複勝'){0} else {1}
    if($plist.Count -lt $minP){ continue }
    $rowStake = if($FrontFlat -gt 0 -and $rno -le $FrontFlat){100}else{$Stake}   # 前半フラット: ≤FrontFlat Rは100円固定
    $rows.Add(('{0},{1},{2},{3},{4},{5},{6},{7}' -f $Date,$v,$rno,$BetType,$Method,$ax,($plist -join '|'),$rowStake))
    $n++
  }
}
[IO.File]::WriteAllLines($Out,$rows,[Text.UTF8Encoding]::new($false))
"買目CSV出力: $Out  ($n レース / $($venues -join '/'))"
"→ プレビュー: & '..\IpatVote\bin\Release\net10.0\IpatVote.exe' '$Out' --mode DryRun --date $Date"
