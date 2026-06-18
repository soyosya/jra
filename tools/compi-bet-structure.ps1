<#
.SYNOPSIS
  コンピ軸(=コンピ1位)・相手=コンピ上位の3連単/3連複を、相手頭数(点数)を変えて比較し、
  さらに「買うレース選別フィルタ(頭数≤FieldMax & Harville期待的中≥EhMin)」の有無で IS/OOS の回収率を検証します。

.DESCRIPTION
  - 軸=コンピ1位。相手=コンピ2..(N+1)位。N=2,3,4。
  - 3連単 軸1頭マルチ-相手N頭: 点数 6*C(N,2) (N2=6/N3=18/N4=36)。的中=軸が3着内 かつ 残り2頭が相手N内。配当=実着順の三連単。
  - 3連複 軸1頭-相手N頭: 点数 C(N,2) (N2=1/N3=3/N4=6)。的中条件は同じ(順不同)。配当=三連複。
  - フィルタ(頭数≤FieldMax & 期待的中≥EhMin)の有無=群 ALL / FILT で集計。期間 IS(〜Split)/OOS(以降)。
  期待的中=Harville(コンピ順位別勝率を全頭正規化, in-sample較正)。回収率%=100*Σ的中払戻/Σ投資。ばんえい除外。馬同定=馬番。

.PARAMETER Venue/From/To/MinField/Split/FieldMax/EhMin
#>
[CmdletBinding()]
param(
  [string]$Venue = '',
  [string]$From = '2025-09-01',
  [string]$To = '2026-06-14',
  [int]$MinField = 7,
  [string]$Split = '2026-02-28',
  [int]$FieldMax = 8,
  [double]$EhMin = 0.55
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
  # 三連単 + 三連複 払戻
  $cmd=NewCmd "SELECT 開催場所,開催日,レース番号,馬券,組番,金額 FROM 払戻金 WHERE 馬券 IN (N'三連単',N'三連複') AND 開催日>=@f AND 開催日<=@t $venFilter"
  $r=$cmd.ExecuteReader(); $pay=@{}
  while($r.Read()){ $key='{0}|{1:yyyy-MM-dd}|{2}' -f $r.GetString(0),$r.GetDateTime(1),$r.GetInt32(2)
    $bk=$r.GetString(3); $k=([string]$r.GetValue(4)).Trim(); if($k -eq ''){continue}; $amt=[double]$r.GetValue(5)
    if(-not $pay.ContainsKey($key)){$pay[$key]=@{}}; if(-not $pay[$key].ContainsKey($bk)){$pay[$key][$bk]=@{}}
    $norm= if($bk -eq '三連単'){$k}else{ (($k -split '-' | ForEach-Object{[int]$_} | Sort-Object) -join '-') }
    $pay[$key][$bk][$norm]=$amt }
  $r.Close(); $conn.Close()
  Write-Host ("  着順{0:N0} / コンピ{1:N0} / 払戻{2:N0}  (Split {3:yyyy-MM-dd}, フィルタ 頭数≤{4} & 期待≥{5})" -f $fin.Count,$compi.Count,$pay.Count,$splitDt,$FieldMax,$EhMin)

  function RankedUma($key){ @($compi[$key].GetEnumerator() | Sort-Object @{e={$_.Value};Descending=$true},@{e={[int]$_.Key};Descending=$false} | ForEach-Object{ [int]$_.Key }) }
  function KeyDate($k){ [datetime]($k.Split('|')[1]) }

  $MR=20; $cnt=@(0)*($MR+1); $w=@(0)*($MR+1)
  foreach($key in $compi.Keys){ if(-not $fin.ContainsKey($key)){ continue }; if((KeyDate $key) -gt $splitDt){ continue }
    $R=RankedUma $key; for($i=0;$i -lt $R.Count -and ($i+1) -le $MR;$i++){ $u=$R[$i]; if($fin[$key].ContainsKey($u)){ $cnt[$i+1]++; if($fin[$key][$u] -eq 1){$w[$i+1]++} } } }
  $winRate=@(0.0)*($MR+1); for($i=1;$i -le $MR;$i++){ if($cnt[$i] -gt 0){ $winRate[$i]=[double]$w[$i]/$cnt[$i] } }

  function TrioProb3([double]$pa,[double]$pb,[double]$pc){
    $perm=@(@($pa,$pb,$pc),@($pa,$pc,$pb),@($pb,$pa,$pc),@($pb,$pc,$pa),@($pc,$pa,$pb),@($pc,$pb,$pa)); $tot=0.0
    foreach($q in $perm){ $d1=1.0-$q[0]; if($d1 -le 0){continue}; $d2=1.0-$q[0]-$q[1]; if($d2 -le 0){continue}; $tot += $q[0]*($q[1]/$d1)*($q[2]/$d2) }; return $tot }
  function OppPairs4 { @(@(0,1),@(0,2),@(0,3),@(1,2),@(1,3),@(2,3)) }
  function Cnk2([int]$n){ [int]($n*($n-1)/2) }

  # 構造定義: 券種 × 相手N. 点数: 三連単=6*C(N,2), 三連複=C(N,2)
  $structs=@(
    @{name='3連単 相手2頭( 6点)';bk='三連単';N=2}, @{name='3連単 相手3頭(18点)';bk='三連単';N=3}, @{name='3連単 相手4頭(36点)';bk='三連単';N=4},
    @{name='3連複 相手2頭( 1点)';bk='三連複';N=2}, @{name='3連複 相手3頭( 3点)';bk='三連複';N=3}, @{name='3連複 相手4頭( 6点)';bk='三連複';N=4}
  )
  $agg=@{}  # group -> struct -> period -> stats
  function Add($g,$s,$p,$hit,$ret,$pts){ if(-not $agg.ContainsKey($g)){$agg[$g]=@{}}; if(-not $agg[$g].ContainsKey($s)){$agg[$g][$s]=@{}}
    if(-not $agg[$g][$s].ContainsKey($p)){$agg[$g][$s][$p]=@{r=0;h=0;s=0.0;ret=0.0;pts=0}}
    $a=$agg[$g][$s][$p]; $a.r++; $a.s+=100.0*$pts; $a.ret+=$ret; $a.pts+=$pts; if($hit){$a.h++} }

  foreach($key in $fin.Keys){
    if($fin[$key].Count -lt $MinField){ continue }; if(-not $compi.ContainsKey($key)){ continue }; if(-not $pay.ContainsKey($key)){ continue }
    $R=RankedUma $key; if($R.Count -lt 5){ continue }
    $axis=$R[0]
    $top=@{}; foreach($u in $fin[$key].Keys){ $c=$fin[$key][$u]; if($c -ge 1 -and $c -le 3){ $top[$c]=$u } }
    if(-not($top.ContainsKey(1) -and $top.ContainsKey(2) -and $top.ContainsKey(3))){ continue }
    $f1=$top[1];$f2=$top[2];$f3=$top[3]; $set=@($f1,$f2,$f3)

    # Harville期待的中(相手4頭ベース, フィルタ判定用)
    $opp4=@($R[1..4])
    $praw=@{}; $sf=0.0
    foreach($u in $fin[$key].Keys){ $rk=([array]::IndexOf($R,$u))+1; $pr= if($rk -ge 1 -and $rk -le $MR){$winRate[$rk]}else{0.005}; if($pr -le 0){$pr=0.005}; $praw[$u]=$pr; $sf+=$pr }
    if($sf -le 0){$sf=1}; $pax=[double]$praw[$axis]/$sf
    $eh=0.0; foreach($pr in (OppPairs4)){ $pi=[double]$praw[$opp4[$pr[0]]]/$sf; $pj=[double]$praw[$opp4[$pr[1]]]/$sf; $eh += TrioProb3 $pax $pi $pj }

    $period= if((KeyDate $key) -le $splitDt){'IS'}else{'OOS'}
    $pass = ($fin[$key].Count -le $FieldMax -and $eh -ge $EhMin)
    $tanOrd="$f1-$f2-$f3"; $fukSort=(($set|ForEach-Object{[int]$_}|Sort-Object) -join '-')

    foreach($st in $structs){
      $N=$st.N; if($R.Count -lt (1+$N)){ continue }
      $oppN=@($R[1..$N]); $oppSet=@{}; $oppN|ForEach-Object{$oppSet[$_]=$true}
      $hit = (($set -contains $axis) -and (@($set|Where-Object{$oppSet.ContainsKey($_)}).Count -eq 2))
      $pts= if($st.bk -eq '三連単'){6*(Cnk2 $N)}else{(Cnk2 $N)}
      $ret=0.0
      if($hit){ $pk= if($st.bk -eq '三連単'){$tanOrd}else{$fukSort}; if($pay[$key][$st.bk] -and $pay[$key][$st.bk].ContainsKey($pk)){ $ret=$pay[$key][$st.bk][$pk] } }
      Add 'ALL' $st.name $period $hit $ret $pts
      if($pass){ Add 'FILT' $st.name $period $hit $ret $pts }
    }
  }

  function Pct($a){ if($null -eq $a -or $a.r -eq 0){return $null}; [Math]::Round(100.0*$a.ret/$a.s,1) }
  function HitP($a){ if($null -eq $a -or $a.r -eq 0){return $null}; [Math]::Round(100.0*$a.h/$a.r,1) }
  function ShowGroup($g,$title){
    Write-Host ("`n=== {0} (IS=〜{1:yyyy-MM-dd} / OOS=以降) ===" -f $title,$splitDt)
    $rows=foreach($st in $structs){ if(-not $agg[$g].ContainsKey($st.name)){ continue }
      $is=$agg[$g][$st.name]['IS']; $oos=$agg[$g][$st.name]['OOS']
      [PSCustomObject]@{ 構造=$st.name
        IS_R= if($is){$is.r}else{0}; IS_的中= HitP $is; IS_回収= Pct $is
        OOS_R= if($oos){$oos.r}else{0}; OOS_的中= HitP $oos; OOS_回収= Pct $oos } }
    $rows | Format-Table -AutoSize | Out-String -Width 150 | Write-Host }

  Write-Host ("`n##### コンピ軸 券種×相手頭数(点数圧縮) IS/OOS検証 ({0} {1}〜{2}) #####" -f ($(if($Venue){$Venue}else{'全場'})),$From,$To)
  ShowGroup 'ALL'  '全レース(フィルタ無し)'
  ShowGroup 'FILT' ("選別レース(頭数≤{0} & 期待的中≥{1})" -f $FieldMax,$EhMin)
}
finally { if($conn.State -eq 'Open'){ $conn.Close() } }
