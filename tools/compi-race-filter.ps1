<#
.SYNOPSIS
  3連単 軸1頭マルチ-相手4頭(軸=コンピ1位/相手=コンピ2-5位, 36点)について、
  「どのレースを買うか」のフィルタ候補(頭数/軸指数/指数差/Harville期待的中)を、
  in-sample期間とアウトオブサンプル期間で回収率を並べて検証します(過学習に強いフィルタを探す)。

.DESCRIPTION
  - コンピ順位別勝率は -Split 以前(in-sample)のみで較正し、Harville期待的中の算出に使用。
  - 各レースを各フィルタのバケットに割り当て、期間(IS=Split以前 / OOS=Splitより後)ごとに的中率・回収率を集計。
  - 期待値(EV)の代理として「Harville期待的中(全頭正規化)」を用いる。馬ごとオッズが無いため厳密EVは不可。
  回収率% = 100*Σ的中払戻/Σ投資(36点=3600円/レース)。ばんえい除外。馬の同定は馬番。

.PARAMETER Venue/From/To/MinField/Split
#>
[CmdletBinding()]
param(
  [string]$Venue = '',
  [string]$From = '2025-09-01',
  [string]$To = '2026-06-14',
  [int]$MinField = 7,
  [string]$Split = '2026-02-28'
)
$ErrorActionPreference = 'Stop'
$appsettings = Join-Path $PSScriptRoot '..\共通\appsettings.json'
$connStr = (Get-Content $appsettings -Raw -Encoding UTF8 | ConvertFrom-Json).ConnectionStrings.DefaultConnection
$conn = New-Object System.Data.SqlClient.SqlConnection($connStr); $conn.Open()
$venFilter = if($Venue -ne ''){ "AND 開催場所=@v" } else { "AND 開催場所 NOT LIKE '%ば'" }
function NewCmd($sql){ $c=$conn.CreateCommand(); $c.CommandTimeout=600; $c.CommandText=$sql;
  [void]$c.Parameters.AddWithValue('@f',$From); [void]$c.Parameters.AddWithValue('@t',$To);
  if($Venue -ne ''){ [void]$c.Parameters.AddWithValue('@v',$Venue) }; return $c }
$splitDt=[datetime]$Split

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
  Write-Host ("  着順{0:N0} / コンピ{1:N0} / 三連単{2:N0}  (Split {3:yyyy-MM-dd})" -f $fin.Count,$compi.Count,$pay3.Count,$splitDt)

  function RankedUma($key){ @($compi[$key].GetEnumerator() | Sort-Object @{e={$_.Value};Descending=$true},@{e={[int]$_.Key};Descending=$false} | ForEach-Object{ [int]$_.Key }) }
  function KeyDate($k){ [datetime]($k.Split('|')[1]) }

  # コンピ順位別勝率(in-sample較正)
  $MR=20; $cnt=@(0)*($MR+1); $w=@(0)*($MR+1)
  foreach($key in $compi.Keys){ if(-not $fin.ContainsKey($key)){ continue }; if((KeyDate $key) -gt $splitDt){ continue }
    $R=RankedUma $key
    for($i=0;$i -lt $R.Count -and ($i+1) -le $MR;$i++){ $u=$R[$i]; if(-not $fin[$key].ContainsKey($u)){ continue }
      $cnt[$i+1]++; if($fin[$key][$u] -eq 1){$w[$i+1]++} } }
  $winRate=@(0.0)*($MR+1); for($i=1;$i -le $MR;$i++){ if($cnt[$i] -gt 0){ $winRate[$i]=[double]$w[$i]/$cnt[$i] } }

  function TrioProb3([double]$pa,[double]$pb,[double]$pc){
    $perm=@(@($pa,$pb,$pc),@($pa,$pc,$pb),@($pb,$pa,$pc),@($pb,$pc,$pa),@($pc,$pa,$pb),@($pc,$pb,$pa)); $tot=0.0
    foreach($q in $perm){ $d1=1.0-$q[0]; if($d1 -le 0){continue}; $d2=1.0-$q[0]-$q[1]; if($d2 -le 0){continue}; $tot += $q[0]*($q[1]/$d1)*($q[2]/$d2) }; return $tot }
  function OppPairs4 { @(@(0,1),@(0,2),@(0,3),@(1,2),@(1,3),@(2,3)) }

  function FieldBucket([int]$n){ if($n -ge 13){'13+'}elseif($n -ge 11){'11-12'}elseif($n -ge 9){'9-10'}else{'7-8'} }
  function AxisBucket([int]$x){ if($x -ge 85){'85+'}elseif($x -ge 75){'75-84'}elseif($x -ge 65){'65-74'}else{'<65'} }
  function GapBucket([int]$g){ if($g -ge 20){'20+'}elseif($g -ge 15){'15-19'}elseif($g -ge 10){'10-14'}elseif($g -ge 5){'5-9'}else{'0-4'} }
  function EhBucket([double]$e){ if($e -ge 0.70){'.70+'}elseif($e -ge 0.60){'.60-.69'}elseif($e -ge 0.50){'.50-.59'}elseif($e -ge 0.40){'.40-.49'}else{'<.40'} }

  # 集計: feature -> bucket -> period -> stats
  $stakePer=3600.0
  $agg=@{}
  function Add($feature,$bucket,$period,$hit,$ret){
    if(-not $agg.ContainsKey($feature)){ $agg[$feature]=@{} }
    if(-not $agg[$feature].ContainsKey($bucket)){ $agg[$feature][$bucket]=@{} }
    if(-not $agg[$feature][$bucket].ContainsKey($period)){ $agg[$feature][$bucket][$period]=@{r=0;h=0;s=0.0;ret=0.0} }
    $a=$agg[$feature][$bucket][$period]; $a.r++; $a.s+=$stakePer; $a.ret+=$ret; if($hit){$a.h++} }

  foreach($key in $fin.Keys){
    if($fin[$key].Count -lt $MinField){ continue }; if(-not $compi.ContainsKey($key)){ continue }; if(-not $pay3.ContainsKey($key)){ continue }
    $R=RankedUma $key; if($R.Count -lt 5){ continue }
    $axis=$R[0]; $opp=@($R[1..4]); $oppSet=@{}; $opp|ForEach-Object{$oppSet[$_]=$true}
    $top=@{}; foreach($u in $fin[$key].Keys){ $c=$fin[$key][$u]; if($c -ge 1 -and $c -le 3){ $top[$c]=$u } }
    if(-not($top.ContainsKey(1) -and $top.ContainsKey(2) -and $top.ContainsKey(3))){ continue }
    $set=@($top[1],$top[2],$top[3])
    $hit = (($set -contains $axis) -and (@($set|Where-Object{$oppSet.ContainsKey($_)}).Count -eq 2))
    $ret=0.0; if($hit){ $ok="$($top[1])-$($top[2])-$($top[3])"; if($pay3[$key].ContainsKey($ok)){ $ret=$pay3[$key][$ok] } }

    # Harville期待的中(全頭正規化, in-sample勝率)
    $praw=@{}; $sf=0.0
    foreach($u in $fin[$key].Keys){ $rk=([array]::IndexOf($R,$u))+1; $pr= if($rk -ge 1 -and $rk -le $MR){$winRate[$rk]}else{0.005}; if($pr -le 0){$pr=0.005}; $praw[$u]=$pr; $sf+=$pr }
    if($sf -le 0){$sf=1}; $pax=[double]$praw[$axis]/$sf
    $eh=0.0; foreach($pr in (OppPairs4)){ $pi=[double]$praw[$opp[$pr[0]]]/$sf; $pj=[double]$praw[$opp[$pr[1]]]/$sf; $eh += TrioProb3 $pax $pi $pj }

    $period = if((KeyDate $key) -le $splitDt){'IS'}else{'OOS'}
    $fieldN = $fin[$key].Count
    Add 'ALL' 'all' $period $hit $ret
    Add '頭数' (FieldBucket $fieldN) $period $hit $ret
    Add '軸指数' (AxisBucket ([int]$compi[$key][$axis])) $period $hit $ret
    Add '指数差' (GapBucket ([int]$compi[$key][$R[0]]-[int]$compi[$key][$R[1]])) $period $hit $ret
    Add '期待的中' (EhBucket $eh) $period $hit $ret
    # 複合フィルタ(OOSで残ったもの=頭数/期待的中を単独・組合せで)
    if($fieldN -le 8){ Add '複合' '頭数7-8' $period $hit $ret }
    if($eh -ge 0.55){ Add '複合' '期待的中≥.55' $period $hit $ret }
    if($eh -ge 0.60){ Add '複合' '期待的中≥.60' $period $hit $ret }
    if($fieldN -le 10 -and $eh -ge 0.55){ Add '複合' '頭数≤10&期待≥.55' $period $hit $ret }
    if($fieldN -le 8  -and $eh -ge 0.55){ Add '複合' '頭数7-8&期待≥.55' $period $hit $ret }
  }

  function Pct($a){ if($a.r -eq 0){return $null}; [Math]::Round(100.0*$a.ret/$a.s,1) }
  function HitP($a){ if($a.r -eq 0){return $null}; [Math]::Round(100.0*$a.h/$a.r,1) }
  function Show($feature,$order){
    Write-Host ("`n--- {0}別 (IS=〜{1:yyyy-MM-dd} / OOS=以降) ---" -f $feature,$splitDt)
    $rows=foreach($b in $order){ if(-not $agg[$feature].ContainsKey($b)){ continue }
      $is=$agg[$feature][$b]['IS']; $oos=$agg[$feature][$b]['OOS']
      [PSCustomObject]@{ バケット=$b
        IS_R= if($is){$is.r}else{0}; IS_的中= if($is){HitP $is}else{$null}; IS_回収= if($is){Pct $is}else{$null}
        OOS_R= if($oos){$oos.r}else{0}; OOS_的中= if($oos){HitP $oos}else{$null}; OOS_回収= if($oos){Pct $oos}else{$null} } }
    $rows | Format-Table -AutoSize | Out-String -Width 140 | Write-Host }

  Write-Host ("`n=== 3連単 軸1頭マルチ-相手4頭(36点) レース選別フィルタ検証 ({0} {1}〜{2}) ===" -f ($(if($Venue){$Venue}else{'全場'})),$From,$To)
  Show 'ALL' @('all')
  Show '期待的中' @('.70+','.60-.69','.50-.59','.40-.49','<.40')
  Show '頭数' @('7-8','9-10','11-12','13+')
  Show '軸指数' @('85+','75-84','65-74','<65')
  Show '指数差' @('20+','15-19','10-14','5-9','0-4')
  Show '複合' @('頭数7-8','期待的中≥.55','期待的中≥.60','頭数≤10&期待≥.55','頭数7-8&期待≥.55')
}
finally { if($conn.State -eq 'Open'){ $conn.Close() } }
