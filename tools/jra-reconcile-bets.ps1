<#
.SYNOPSIS
  jra-export-bets が出した買目CSVを、競走結果(着順)+払戻金と突合し、的中/回収を集計する。
.DESCRIPTION
  対応式別: 三連複(軸1頭流し)。CSV列= date,venue,race,bettype,method,axis,partners(|区切り),stake。
  各レースで 競走結果の上位3頭(着順1-3の馬番)を取り、軸の複勝/単勝・三連複的中・払戻・回収を算出。
  結果未取込のレースは「未取込」として集計から除外(=netkeiba結果DBの掲載待ち時に明示)。
  払戻は 払戻金テーブル(馬券=三連複)の金額(100円あたり)× stake/100 を的中時に加算。
.PARAMETER BetsCsv 買目CSV。 .PARAMETER Date 対象日(未指定はCSVの値を使用)。
#>
[CmdletBinding()]param([Parameter(Mandatory)][string]$BetsCsv,[string]$Date='')
$ErrorActionPreference='Stop'
$cs=(Get-Content (Join-Path $PSScriptRoot '..\共通\appsettings.json') -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
$conn=New-Object System.Data.SqlClient.SqlConnection($cs);$conn.Open()
function Q($s,$p){$c=$conn.CreateCommand();$c.CommandText=$s;foreach($k in $p.Keys){[void]$c.Parameters.AddWithValue($k,$p[$k])};$r=$c.ExecuteReader();$o=@();while($r.Read()){$row=[ordered]@{};for($i=0;$i -lt $r.FieldCount;$i++){$row[$r.GetName($i)]=$r.GetValue($i)};$o+=[pscustomobject]$row};$r.Close();$o}
function Comb2($a){ $o=@(); for($i=0;$i -lt $a.Count;$i++){ for($j=$i+1;$j -lt $a.Count;$j++){ $o+=,@($a[$i],$a[$j]) } }; $o }

$bets=Import-Csv $BetsCsv
$res=New-Object System.Collections.Generic.List[object]
$nBet=0;$nResolved=0;$nFukuHit=0;$nTanHit=0;$nTrioHit=0;[int]$totCost=0;[int]$totPay=0;$nUnresolved=0
foreach($b in $bets){
  $d= if($Date){$Date}else{[string]$b.date}; $v=[string]$b.venue; $rno=[int]$b.race
  $ax=[int]$b.axis; $pl=@(($b.partners -split '\|')|Where-Object{$_ -ne ''}|ForEach-Object{[int]$_}); $stake=[int]$b.stake
  $pts=@(Comb2 $pl); $cost=$pts.Count*$stake; $nBet++
  # 上位3頭(着順1-3の馬番)
  $top=Q "SELECT 着順,馬番 FROM 競走結果 WHERE 開催日=@d AND 開催場所=@v AND レース番号=@r AND 着順 IN (1,2,3) AND 馬番>0 ORDER BY 着順" @{'@d'=$d;'@v'=$v;'@r'=$rno}
  if($top.Count -lt 3){
    $nUnresolved++
    $res.Add([pscustomobject]@{場=$v;R=$rno;軸=$ax;結果='未取込';軸着=$null;複=$null;単=$null;三連複=$null;点数=$pts.Count;投資=$cost;払戻=$null;回収='-'})
    continue
  }
  $nResolved++; $totCost+=$cost
  $t1=[int]($top|Where-Object{[int]$_.着順 -eq 1}|Select-Object -First 1).馬番
  $t2=[int]($top|Where-Object{[int]$_.着順 -eq 2}|Select-Object -First 1).馬番
  $t3=[int]($top|Where-Object{[int]$_.着順 -eq 3}|Select-Object -First 1).馬番
  $set=@($t1,$t2,$t3)
  $fuku= $set -contains $ax; if($fuku){$nFukuHit++}
  $tan= ($t1 -eq $ax); if($tan){$nTanHit++}
  # 三連複(軸1頭流し)的中: 軸が上位3 かつ 残り2頭が相手に含まれる
  $others=@($set|Where-Object{$_ -ne $ax})
  $trio= $fuku -and ($others.Count -eq 2) -and ($pl -contains $others[0]) -and ($pl -contains $others[1])
  $pay=0
  if($trio){
    $nTrioHit++
    $pr=Q "SELECT TOP 1 TRY_CONVERT(int,REPLACE(金額,',','')) 金額 FROM 払戻金 WHERE 開催日=@d AND 開催場所=@v AND レース番号=@r AND (馬券=N'三連複' OR 馬券 LIKE N'%３連複%' OR 馬券 LIKE N'%3連複%') ORDER BY 金額 DESC" @{'@d'=$d;'@v'=$v;'@r'=$rno}
    if($pr.Count -ge 1 -and $pr[0].金額 -isnot [DBNull]){ $pay=[int]$pr[0].金額*($stake/100) }
    $totPay+=$pay
  }
  $res.Add([pscustomobject]@{場=$v;R=$rno;軸=$ax;結果='確定';軸着=if($fuku){[string]($set.IndexOf($ax)+1)+'着'}else{'圏外'};複=if($fuku){'○'}else{'×'};単=if($tan){'○'}else{''};三連複=if($trio){'★的中'}else{'×'};点数=$pts.Count;投資=$cost;払戻=$pay;回収=if($cost){('{0:N0}%' -f (100.0*$pay/$cost))}else{'-'}})
}
$conn.Close()
$res | Format-Table 場,R,軸,結果,軸着,複,単,三連複,点数,投資,払戻,回収 -AutoSize | Out-String -Width 200 | Write-Host
"";"===== 集計 ($($bets[0].date)) ====="
"  買目: {0}レース / 確定 {1} / 未取込 {2}" -f $nBet,$nResolved,$nUnresolved
if($nResolved -gt 0){
  "  軸 複勝的中: {0}/{1} ({2:N1}%)  軸 単勝的中: {3}/{1} ({4:N1}%)" -f $nFukuHit,$nResolved,(100.0*$nFukuHit/$nResolved),$nTanHit,(100.0*$nTanHit/$nResolved)
  "  三連複的中: {0}/{1} ({2:N1}%)" -f $nTrioHit,$nResolved,(100.0*$nTrioHit/$nResolved)
  "  投資 {0:N0}円 / 払戻 {1:N0}円 / 回収率 {2:N1}%" -f $totCost,$totPay,$(if($totCost){100.0*$totPay/$totCost}else{0})
} else { "  確定レースなし(netkeiba結果DB未掲載)。掲載後に fetch-jra-range で取込→本ツール再実行。" }
