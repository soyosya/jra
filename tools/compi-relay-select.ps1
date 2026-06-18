<#
.SYNOPSIS
  軸の指数を基準に「相手の指数ごとの複勝率(3着内率)」を実データで集計し、その複勝率で相手4頭を選ぶ方式を
  従来(コンピ2-5位)と3連単 軸1頭マルチ-相手4頭(36点)で比較バックテストします。

.DESCRIPTION
  - 軸 = コンピ1位(指数最大)。各レースの軸以外の馬について「軸指数バンド × 相手指数バンド → 3着内率」を集計(=相手指数の複勝率)。
  - 相手選定(条件付き) = その複勝率が高い順に4頭。従来 = コンピ2-5位(指数順位順)。
  - 馬券 = 3連単 軸1頭マルチ-相手4頭=36点。的中 = 軸が3着内 かつ 残り2頭(1-3着)が相手4頭に含まれる。
  回収率% = 100*Σ的中払戻/Σ投資(1点100円, 36点=3600円/レース)。ばんえい除外。馬の同定は馬番。指数バンドは幅5。
  ※較正は同一データ(in-sample)。傾向把握用。

.PARAMETER Venue/From/To/MinField/MinCell
#>
[CmdletBinding()]
param(
  [string]$Venue = '',
  [string]$From = '2025-09-01',
  [string]$To = '2026-06-14',
  [int]$MinField = 7,
  [int]$MinCell = 30,  # 条件付きセルをこの標本数以上で採用、未満は相手指数バンドの全体率にフォールバック
  [string]$CalTo = ''  # 指定時: この日以前で較正し、この日より後でバックテスト(アウトオブサンプル検証)
)
$ErrorActionPreference = 'Stop'
$appsettings = Join-Path $PSScriptRoot '..\共通\appsettings.json'
$connStr = (Get-Content $appsettings -Raw -Encoding UTF8 | ConvertFrom-Json).ConnectionStrings.DefaultConnection
$conn = New-Object System.Data.SqlClient.SqlConnection($connStr); $conn.Open()
$venFilter = if($Venue -ne ''){ "AND 開催場所=@v" } else { "AND 開催場所 NOT LIKE '%ば'" }
function NewCmd($sql){ $c=$conn.CreateCommand(); $c.CommandTimeout=600; $c.CommandText=$sql;
  [void]$c.Parameters.AddWithValue('@f',$From); [void]$c.Parameters.AddWithValue('@t',$To);
  if($Venue -ne ''){ [void]$c.Parameters.AddWithValue('@v',$Venue) }; return $c }
function Band5([int]$x){ if($x -lt 40){'<40'} else { $lo=[int]([Math]::Floor($x/5)*5); '{0:D2}-{1:D2}' -f $lo,($lo+4) } }

try {
  Write-Host "ロード中..."
  $cmd=NewCmd "SELECT 開催場所,開催日,レース番号,馬番,着順 FROM 競走結果 WHERE 着順>0 AND 開催日>=@f AND 開催日<=@t $venFilter"
  $r=$cmd.ExecuteReader(); $fin=@{}
  while($r.Read()){ $key='{0}|{1:yyyy-MM-dd}|{2}' -f $r.GetString(0),$r.GetDateTime(1),$r.GetInt32(2)
    if(-not $fin.ContainsKey($key)){ $fin[$key]=@{} }; $fin[$key][[int]$r.GetInt32(3)]=[int]$r.GetInt32(4) }
  $r.Close()
  $cmd=NewCmd @"
WITH s AS (SELECT 開催日,開催場所,レース番号,馬番,指数,ROW_NUMBER() OVER(PARTITION BY 開催日,開催場所,レース番号,馬番 ORDER BY 取得日時 DESC) rn
  FROM コンピ指数 WHERE 開催日>=@f AND 開催日<=@t $venFilter)
SELECT 開催場所,開催日,レース番号,馬番,指数 FROM s WHERE rn=1 AND 指数 IS NOT NULL
"@
  $r=$cmd.ExecuteReader(); $compi=@{}
  while($r.Read()){ $key='{0}|{1:yyyy-MM-dd}|{2}' -f $r.GetString(0),$r.GetDateTime(1),$r.GetInt32(2)
    if(-not $compi.ContainsKey($key)){ $compi[$key]=@{} }; $compi[$key][[int]$r.GetInt32(3)]=[int]$r.GetInt32(4) }
  $r.Close()
  $cmd=NewCmd "SELECT 開催場所,開催日,レース番号,組番,金額 FROM 払戻金 WHERE 馬券=N'三連単' AND 開催日>=@f AND 開催日<=@t $venFilter"
  $r=$cmd.ExecuteReader(); $pay3=@{}
  while($r.Read()){ $key='{0}|{1:yyyy-MM-dd}|{2}' -f $r.GetString(0),$r.GetDateTime(1),$r.GetInt32(2)
    $k=([string]$r.GetValue(3)).Trim(); if($k -eq ''){continue}; if(-not $pay3.ContainsKey($key)){$pay3[$key]=@{}}; $pay3[$key][$k]=[double]$r.GetValue(4) }
  $r.Close(); $conn.Close()
  Write-Host ("  着順{0:N0} / コンピ{1:N0} / 三連単{2:N0}" -f $fin.Count,$compi.Count,$pay3.Count)

  function RankedUma($key){ @($compi[$key].GetEnumerator() | Sort-Object @{e={$_.Value};Descending=$true},@{e={[int]$_.Key};Descending=$false} | ForEach-Object{ [int]$_.Key }) }
  function AxisOf($key){ (RankedUma $key)[0] }
  function KeyDate($k){ [datetime]($k.Split('|')[1]) }
  $calDt = if($CalTo -ne ''){ [datetime]$CalTo } else { $null }
  if($calDt){ Write-Host ("  アウトオブサンプル: 較正 〜{0:yyyy-MM-dd} / 検証 {0:yyyy-MM-dd}より後" -f $calDt) }

  # ===== Pass1: 条件付き複勝率(軸指数バンド × 相手指数バンド/exact整数 → 3着内率) =====
  $cond=@{}; $condE=@{}; $gB=@{}    # cond=軸band|相手band, condE=軸band|相手exact指数, gB=相手band全体
  foreach($key in $compi.Keys){ if(-not $fin.ContainsKey($key)){ continue }
    if($calDt -and (KeyDate $key) -gt $calDt){ continue }   # 較正は CalTo 以前のみ
    $ax=AxisOf $key; if(-not $compi[$key].ContainsKey($ax)){ continue }
    $Aband=Band5 ([int]$compi[$key][$ax])
    foreach($u in $compi[$key].Keys){ if($u -eq $ax){ continue }; if(-not $fin[$key].ContainsKey($u)){ continue }
      $bx=[int]$compi[$key][$u]; $Bband=Band5 $bx; $ck="$Aband|$Bband"; $ek="$Aband|$bx"; $in3= if($fin[$key][$u] -le 3){1}else{0}
      if(-not $cond.ContainsKey($ck)){ $cond[$ck]=@{n=0;p3=0} }; $cond[$ck].n++; $cond[$ck].p3+=$in3
      if(-not $condE.ContainsKey($ek)){ $condE[$ek]=@{n=0;p3=0} }; $condE[$ek].n++; $condE[$ek].p3+=$in3
      if(-not $gB.ContainsKey($Bband)){ $gB[$Bband]=@{n=0;p3=0} }; $gB[$Bband].n++; $gB[$Bband].p3+=$in3 } }

  Write-Host ("`n=== 相手指数の複勝率(3着内率) 軸指数バンド別 ({0}) ===" -f ($(if($Venue){$Venue}else{'全場'})))
  $allB = $gB.Keys | Sort-Object
  foreach($Ab in @('85-89','80-84','75-79','70-74','65-69')){
    $cells = foreach($Bb in $allB){ $ck="$Ab|$Bb"; if($cond.ContainsKey($ck) -and $cond[$ck].n -ge $MinCell){
      [PSCustomObject]@{ 相手指数=$Bb; 標本=$cond[$ck].n; 複勝率=[Math]::Round(100.0*$cond[$ck].p3/$cond[$ck].n,1) } } }
    if($cells){ Write-Host ("`n[軸指数 {0}]" -f $Ab); $cells | Sort-Object 相手指数 -Descending | Format-Table -AutoSize | Out-String -Width 100 | Write-Host }
  }

  Write-Host "`n--- 参考: exact指数別 複勝率(軸指数 80-84) ── レンジ内の高低を確認 ---"
  $exRows = for($x=84;$x -ge 45;$x--){ $ek="80-84|$x"; if($condE.ContainsKey($ek) -and $condE[$ek].n -ge $MinCell){
    [PSCustomObject]@{ 相手指数=$x; レンジ=(Band5 $x); 標本=$condE[$ek].n; 複勝率=[Math]::Round(100.0*$condE[$ek].p3/$condE[$ek].n,1) } } }
  $exRows | Format-Table -AutoSize | Out-String -Width 100 | Write-Host

  # 相手の複勝率推定(条件付き→フォールバック全体)
  function RelayRate($Aband,[int]$bIdx){ $Bband=Band5 $bIdx; $ck="$Aband|$Bband"
    if($cond.ContainsKey($ck) -and $cond[$ck].n -ge $MinCell){ return [double]$cond[$ck].p3/$cond[$ck].n }
    if($gB.ContainsKey($Bband) -and $gB[$Bband].n -ge 50){ return [double]$gB[$Bband].p3/$gB[$Bband].n }
    return 0.0 }
  function RelayRateExact($Aband,[int]$x){ $ek="$Aband|$x"
    if($condE.ContainsKey($ek) -and $condE[$ek].n -ge $MinCell){ return [double]$condE[$ek].p3/$condE[$ek].n }
    return (RelayRate $Aband $x) }

  # ===== Pass2: 3連単36点バックテスト(従来=コンピ2-5位 / 条件付き=複勝率上位4頭) =====
  function OppPairs([int]$n){ $o=New-Object System.Collections.Generic.List[object]; for($i=0;$i -lt $n;$i++){ for($j=$i+1;$j -lt $n;$j++){ $o.Add(@($i,$j)) } }; return ,$o }
  function EvalBet($key,$axis,$opp){ # 返り値 @{hit;ret}
    $oppSet=@{}; $opp|ForEach-Object{$oppSet[$_]=$true}
    $top=@{}; foreach($u in $fin[$key].Keys){ $c=$fin[$key][$u]; if($c -ge 1 -and $c -le 3){ $top[$c]=$u } }
    if(-not($top.ContainsKey(1) -and $top.ContainsKey(2) -and $top.ContainsKey(3))){ return @{hit=$false;ret=0.0;valid=$false} }
    $set=@($top[1],$top[2],$top[3])
    $hit = (($set -contains $axis) -and (@($set|Where-Object{$oppSet.ContainsKey($_)}).Count -eq 2))
    $ret=0.0; if($hit){ $ok="$($top[1])-$($top[2])-$($top[3])"; if($pay3[$key].ContainsKey($ok)){ $ret=$pay3[$key][$ok] } }
    return @{hit=$hit;ret=$ret;valid=$true} }

  $stakePer=3600.0
  # exact複勝率の単純上位4頭
  function SelectExact($key,$axis,$Aband){
    @($compi[$key].Keys | Where-Object{ $_ -ne $axis } |
      Sort-Object @{e={ RelayRateExact $Aband ([int]$compi[$key][$_]) };Descending=$true},@{e={[int]$compi[$key][$_]};Descending=$true} | Select-Object -First 4) }
  # 指数を5ptレンジに分割し、各レンジで exact複勝率が最良の馬(レンジ代表)を採り、複勝率上位4レンジから4頭
  function SelectRange($key,$axis,$Aband){
    $byR=@{}
    foreach($u in $compi[$key].Keys){ if($u -eq $axis){ continue }
      $x=[int]$compi[$key][$u]; $rb=Band5 $x; $rate=RelayRateExact $Aband $x
      if(-not $byR.ContainsKey($rb)){ $byR[$rb]=@{u=$u;rate=$rate;x=$x} }
      elseif($rate -gt $byR[$rb].rate -or ($rate -eq $byR[$rb].rate -and $x -gt $byR[$rb].x)){ $byR[$rb]=@{u=$u;rate=$rate;x=$x} } }
    @($byR.Values | Sort-Object @{e={$_.rate};Descending=$true},@{e={$_.x};Descending=$true} | Select-Object -First 4 | ForEach-Object{ $_.u }) }

  $M=@{ base=@{r=0;h=0;s=0.0;ret=0.0;ov=0.0;ovn=0}; ext=@{r=0;h=0;s=0.0;ret=0.0;ov=0.0;ovn=0}; rng=@{r=0;h=0;s=0.0;ret=0.0;ov=0.0;ovn=0} }
  $byVenR=@{}
  foreach($key in $fin.Keys){
    if($calDt -and (KeyDate $key) -le $calDt){ continue }   # 検証は CalTo より後のみ
    if($fin[$key].Count -lt $MinField){ continue }; if(-not $compi.ContainsKey($key)){ continue }; if(-not $pay3.ContainsKey($key)){ continue }
    $R=RankedUma $key; if($R.Count -lt 5){ continue }
    $axis=$R[0]; $Aband=Band5 ([int]$compi[$key][$axis])
    $oppBase=@($R[1..4]); $bset=@{}; $oppBase|ForEach-Object{$bset[$_]=$true}
    $oppExt=SelectExact $key $axis $Aband
    $oppRng=SelectRange $key $axis $Aband
    if($oppExt.Count -lt 4 -or $oppRng.Count -lt 4){ continue }

    $rb=EvalBet $key $axis $oppBase; if($rb.valid){ $M.base.r++;$M.base.s+=$stakePer;$M.base.ret+=$rb.ret;if($rb.hit){$M.base.h++} }
    $re=EvalBet $key $axis $oppExt;  if($re.valid){ $M.ext.r++;$M.ext.s+=$stakePer;$M.ext.ret+=$re.ret;if($re.hit){$M.ext.h++}
      $M.ext.ov += @($oppExt|Where-Object{$bset.ContainsKey($_)}).Count; $M.ext.ovn++ }
    $rr=EvalBet $key $axis $oppRng;  if($rr.valid){ $M.rng.r++;$M.rng.s+=$stakePer;$M.rng.ret+=$rr.ret;if($rr.hit){$M.rng.h++}
      $M.rng.ov += @($oppRng|Where-Object{$bset.ContainsKey($_)}).Count; $M.rng.ovn++
      $ven=$key.Split('|')[0]; if(-not $byVenR.ContainsKey($ven)){$byVenR[$ven]=@{r=0;h=0;s=0.0;ret=0.0}}
      $byVenR[$ven].r++;$byVenR[$ven].s+=$stakePer;$byVenR[$ven].ret+=$rr.ret;if($rr.hit){$byVenR[$ven].h++} }
  }

  Write-Host ("`n=== 3連単 軸1頭マルチ-相手4頭(36点) 相手選定の比較 ({0} {1}〜{2}) ===" -f ($(if($Venue){$Venue}else{'全場'})),$From,$To)
  function Row($name,$m,$showOv){ $o= if($showOv -and $m.ovn -gt 0){[Math]::Round($m.ov/$m.ovn,2)}else{'-'}
    [PSCustomObject]@{ 相手選定=$name; レース=$m.r; 的中率=[Math]::Round(100.0*$m.h/$m.r,1); 回収率=[Math]::Round(100.0*$m.ret/$m.s,1); 従来との重なり=$o } }
  @( (Row '従来(コンピ2-5位)        ' $M.base $false), (Row 'exact複勝率 上位4         ' $M.ext $true), (Row '指数レンジ分割(各レンジ最良)' $M.rng $true) ) |
    Format-Table 相手選定,レース,的中率,回収率,従来との重なり -AutoSize | Out-String -Width 140 | Write-Host

  if($Venue -eq ''){
    Write-Host "`n--- 指数レンジ分割の場別 回収率 ---"
    $vRep=foreach($v in ($byVenR.Keys|Sort-Object)){ $h=$byVenR[$v]; if($h.r -lt 50){continue}
      [PSCustomObject]@{ 場=$v; レース=$h.r; 的中率=[Math]::Round(100.0*$h.h/$h.r,1); 回収率=[Math]::Round(100.0*$h.ret/$h.s,1) } }
    $vRep | Sort-Object 回収率 -Descending | Format-Table -AutoSize | Out-String -Width 120 | Write-Host
  }
}
finally { if($conn.State -eq 'Open'){ $conn.Close() } }
