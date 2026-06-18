<#
.SYNOPSIS
  コンピ指数の並びから各馬の「馬券になる確率(3着内率)」を較正し、軸1頭-相手4頭の3連単マルチ(36点)の成績を実払戻でバックテストします。

.DESCRIPTION
  - 確率: 全データでコンピ順位→3着内率/勝率を集計(=馬券確率の較正)。レース内では指数降順=確率降順。
  - 選定: 軸=最高確率(コンピ1位)、相手=次の4頭(コンピ2-5位)。
  - 馬券: 3連単 軸1頭マルチ流し相手4頭 = C(4,2)×3! = 36点。
          的中 = 軸が3着内 かつ 残り2頭(1-3着)が相手4頭に含まれる。配当=実際の着順の三連単払戻。
  - 較正: Harvilleモデル(コンピ順位別勝率をレース内正規化)で期待的中率を算出し、実的中率と比較。
  回収率% = 100 * Σ的中払戻 / Σ投資(1点100円, 1レース36点=3600円)。ばんえい除外。馬の同定は馬番。

.PARAMETER Venue '' なら全場。 From/To 期間。 MinField 最小頭数(既定7)。 Partners 相手頭数(既定4)。
#>
[CmdletBinding()]
param(
  [string]$Venue = '',
  [string]$From = '2025-09-01',
  [string]$To = '2026-06-14',
  [int]$MinField = 7,
  [int]$Partners = 4
)
$ErrorActionPreference = 'Stop'
$appsettings = Join-Path $PSScriptRoot '..\共通\appsettings.json'
$connStr = (Get-Content $appsettings -Raw -Encoding UTF8 | ConvertFrom-Json).ConnectionStrings.DefaultConnection
$conn = New-Object System.Data.SqlClient.SqlConnection($connStr); $conn.Open()
$venFilter = if($Venue -ne ''){ "AND 開催場所=@v" } else { "AND 開催場所 NOT LIKE '%ば'" }
function NewCmd($sql){ $c=$conn.CreateCommand(); $c.CommandTimeout=600; $c.CommandText=$sql;
  [void]$c.Parameters.AddWithValue('@f',$From); [void]$c.Parameters.AddWithValue('@t',$To);
  if($Venue -ne ''){ [void]$c.Parameters.AddWithValue('@v',$Venue) }; return $c }

try {
  Write-Host "ロード中..."
  # 着順
  $cmd=NewCmd "SELECT 開催場所,開催日,レース番号,馬番,着順 FROM 競走結果 WHERE 着順>0 AND 開催日>=@f AND 開催日<=@t $venFilter"
  $r=$cmd.ExecuteReader(); $fin=@{}
  while($r.Read()){ $key='{0}|{1:yyyy-MM-dd}|{2}' -f $r.GetString(0),$r.GetDateTime(1),$r.GetInt32(2)
    if(-not $fin.ContainsKey($key)){ $fin[$key]=@{} }; $fin[$key][[int]$r.GetInt32(3)]=[int]$r.GetInt32(4) }
  $r.Close()
  # コンピ(最新スナップ)
  $cmd=NewCmd @"
WITH s AS (SELECT 開催日,開催場所,レース番号,馬番,指数,ROW_NUMBER() OVER(PARTITION BY 開催日,開催場所,レース番号,馬番 ORDER BY 取得日時 DESC) rn
  FROM コンピ指数 WHERE 開催日>=@f AND 開催日<=@t $venFilter)
SELECT 開催場所,開催日,レース番号,馬番,指数 FROM s WHERE rn=1 AND 指数 IS NOT NULL
"@
  $r=$cmd.ExecuteReader(); $compi=@{}
  while($r.Read()){ $key='{0}|{1:yyyy-MM-dd}|{2}' -f $r.GetString(0),$r.GetDateTime(1),$r.GetInt32(2)
    if(-not $compi.ContainsKey($key)){ $compi[$key]=@{} }; $compi[$key][[int]$r.GetInt32(3)]=[int]$r.GetInt32(4) }
  $r.Close()
  # 三連単払戻(順序あり)
  $cmd=NewCmd "SELECT 開催場所,開催日,レース番号,組番,金額 FROM 払戻金 WHERE 馬券=N'三連単' AND 開催日>=@f AND 開催日<=@t $venFilter"
  $r=$cmd.ExecuteReader(); $pay3=@{}
  while($r.Read()){ $key='{0}|{1:yyyy-MM-dd}|{2}' -f $r.GetString(0),$r.GetDateTime(1),$r.GetInt32(2)
    $k=([string]$r.GetValue(3)).Trim(); if($k -eq ''){continue}; if(-not $pay3.ContainsKey($key)){$pay3[$key]=@{}}; $pay3[$key][$k]=[double]$r.GetValue(4) }
  $r.Close(); $conn.Close()
  Write-Host ("  着順{0:N0} / コンピ{1:N0} / 三連単払戻{2:N0}" -f $fin.Count,$compi.Count,$pay3.Count)

  function RankedUma($key){ @($compi[$key].GetEnumerator() | Sort-Object @{e={$_.Value};Descending=$true},@{e={[int]$_.Key};Descending=$false} | ForEach-Object{ [int]$_.Key }) }

  # ===== 確率較正: コンピ順位 → 勝率/3着内率 =====
  $MR=20; $cnt=@(0)*($MR+1); $w=@(0)*($MR+1); $p3=@(0)*($MR+1)
  foreach($key in $compi.Keys){ if(-not $fin.ContainsKey($key)){ continue }
    $R=RankedUma $key
    for($i=0;$i -lt $R.Count -and ($i+1) -le $MR;$i++){ $u=$R[$i]; if(-not $fin[$key].ContainsKey($u)){ continue }
      $c=$fin[$key][$u]; $cnt[$i+1]++; if($c -eq 1){$w[$i+1]++}; if($c -le 3){$p3[$i+1]++} } }
  $winRate=@(0.0)*($MR+1); $p3Rate=@(0.0)*($MR+1)
  for($r=1;$r -le $MR;$r++){ if($cnt[$r] -gt 0){ $winRate[$r]=[double]$w[$r]/$cnt[$r]; $p3Rate[$r]=[double]$p3[$r]/$cnt[$r] } }

  Write-Host ("`n=== コンピ順位→馬券確率(較正, {0}) ===" -f ($(if($Venue){$Venue}else{'全場'})))
  $calRep=for($r=1;$r -le 8;$r++){ if($cnt[$r] -gt 0){ [PSCustomObject]@{ コンピ順位=$r; 標本=$cnt[$r]; 勝率=[Math]::Round(100*$winRate[$r],1); '3着内率(馬券確率)'=[Math]::Round(100*$p3Rate[$r],1) } } }
  $calRep | Format-Table -AutoSize | Out-String -Width 120 | Write-Host

  # Harville: レース内でコンピ順位別勝率を正規化した勝率を使い、トリオ集合の的中確率を出す
  function TrioProb3([double]$pa,[double]$pb,[double]$pc){
    # 3頭が(順不同で)1-2-3着を占める確率 = 6順列のHarville総和。p は全頭正規化済み勝率。
    $perm=@(@($pa,$pb,$pc),@($pa,$pc,$pb),@($pb,$pa,$pc),@($pb,$pc,$pa),@($pc,$pa,$pb),@($pc,$pb,$pa))
    $tot=0.0
    foreach($q in $perm){ $d1=1.0-$q[0]; if($d1 -le 0){continue}; $d2=1.0-$q[0]-$q[1]; if($d2 -le 0){continue}; $tot += $q[0]*($q[1]/$d1)*($q[2]/$d2) }
    return $tot }

  function OppPairs([int]$n){ $o=New-Object System.Collections.Generic.List[object]; for($i=0;$i -lt $n;$i++){ for($j=$i+1;$j -lt $n;$j++){ $o.Add(@($i,$j)) } }; return ,$o }

  # ===== バックテスト: 軸1頭マルチ-相手N頭 (点数=6×C(N,2), 既定36点) =====
  $nPairs = [int]($Partners*($Partners-1)/2)
  $points = 6 * $nPairs
  $stakePer = 100.0 * $points
  $gapOrder=@('0-4','5-9','10-14','15-19','20+')
  function GapBucket([int]$g){ if($g -ge 20){'20+'}elseif($g -ge 15){'15-19'}elseif($g -ge 10){'10-14'}elseif($g -ge 5){'5-9'}else{'0-4'} }

  $ov=@{races=0;hit=0;stake=0.0;ret=0.0;expHit=0.0}
  $byGap=@{}; $byVen=@{}
  foreach($g in $gapOrder){ $byGap[$g]=@{races=0;hit=0;stake=0.0;ret=0.0} }
  foreach($key in $fin.Keys){
    if($fin[$key].Count -lt $MinField){ continue }
    if(-not $compi.ContainsKey($key)){ continue }
    $R=RankedUma $key
    if($R.Count -lt (1+$Partners)){ continue }
    if(-not $pay3.ContainsKey($key)){ continue }
    $axis=$R[0]; $opp=@($R[1..$Partners]); $oppSet=@{}; $opp|ForEach-Object{$oppSet[$_]=$true}

    # 着順1-3の馬番
    $top=@{}; foreach($u in $fin[$key].Keys){ $c=$fin[$key][$u]; if($c -ge 1 -and $c -le 3){ $top[$c]=$u } }
    if(-not($top.ContainsKey(1) -and $top.ContainsKey(2) -and $top.ContainsKey(3))){ continue }
    $f1=$top[1];$f2=$top[2];$f3=$top[3]; $set=@($f1,$f2,$f3)

    # 的中判定: 軸が3着内 かつ 上位3頭のうち相手集合に含まれる数=2(=残り2枠が相手)
    $axisIn = ($set -contains $axis)
    $inOpp = @($set | Where-Object{ $oppSet.ContainsKey($_) }).Count
    $hit = ($axisIn -and $inOpp -eq 2)
    $rr = 0.0
    if($hit){ $okey="$f1-$f2-$f3"; if($pay3[$key].ContainsKey($okey)){ $rr=$pay3[$key][$okey] } }

    # Harville期待的中: 全頭の勝率(コンピ順位別)をレース内で正規化し、軸+相手2頭が上位3を占める確率の総和
    $praw=@{}; $sf=0.0
    foreach($u in $fin[$key].Keys){ $rk=([array]::IndexOf($R,$u))+1; $pr= if($rk -ge 1 -and $rk -le $MR){$winRate[$rk]}else{0.005}; if($pr -le 0){$pr=0.005}; $praw[$u]=$pr; $sf+=$pr }
    if($sf -le 0){$sf=1}
    $pax=[double]$praw[$axis]/$sf
    $eh=0.0; foreach($pr in (OppPairs $Partners)){ $pi=[double]$praw[$opp[$pr[0]]]/$sf; $pj=[double]$praw[$opp[$pr[1]]]/$sf; $eh += TrioProb3 $pax $pi $pj }

    $gp = GapBucket ([int]$compi[$key][$R[0]]-[int]$compi[$key][$R[1]])
    $ven = $key.Split('|')[0]
    if(-not $byVen.ContainsKey($ven)){ $byVen[$ven]=@{races=0;hit=0;stake=0.0;ret=0.0} }

    $ov.races++; $ov.stake+=$stakePer; $ov.ret+=$rr; $ov.expHit+=$eh; if($hit){$ov.hit++}
    $byGap[$gp].races++; $byGap[$gp].stake+=$stakePer; $byGap[$gp].ret+=$rr; if($hit){$byGap[$gp].hit++}
    $byVen[$ven].races++; $byVen[$ven].stake+=$stakePer; $byVen[$ven].ret+=$rr; if($hit){$byVen[$ven].hit++}
  }

  Write-Host ("`n=== 3連単 軸1頭マルチ-相手{0}頭({1}点) バックテスト ({2} {3}〜{4}, 最小{5}頭) ===" -f $Partners,[int]($stakePer/100),($(if($Venue){$Venue}else{'全場'})),$From,$To,$MinField)
  if($ov.races -gt 0){
    Write-Host ("レース {0:N0} / 投資 {1:N0}円 / 平均点 {2}" -f $ov.races,[int]$ov.stake,[int]($stakePer/100))
    Write-Host ("実的中率 {0}%  (Harville期待的中 {1}%)  回収率 {2}%" -f ([Math]::Round(100.0*$ov.hit/$ov.races,1)),([Math]::Round(100.0*$ov.expHit/$ov.races,1)),([Math]::Round(100.0*$ov.ret/$ov.stake,1)))
  }

  Write-Host "`n--- 指数差(コ1-コ2)別 ---"
  $gRep=foreach($g in $gapOrder){ $h=$byGap[$g]; if($h.races -eq 0){continue}
    [PSCustomObject]@{ 指数差=$g; レース=$h.races; 的中率=[Math]::Round(100.0*$h.hit/$h.races,1); 回収率=[Math]::Round(100.0*$h.ret/$h.stake,1) } }
  $gRep | Format-Table -AutoSize | Out-String -Width 120 | Write-Host

  if($Venue -eq ''){
    Write-Host "--- 場別 ---"
    $vRep=foreach($v in ($byVen.Keys|Sort-Object)){ $h=$byVen[$v]; if($h.races -lt 50){continue}
      [PSCustomObject]@{ 場=$v; レース=$h.races; 的中率=[Math]::Round(100.0*$h.hit/$h.races,1); 回収率=[Math]::Round(100.0*$h.ret/$h.stake,1) } }
    $vRep | Sort-Object 回収率 -Descending | Format-Table -AutoSize | Out-String -Width 120 | Write-Host
  }
}
finally { if($conn.State -eq 'Open'){ $conn.Close() } }
