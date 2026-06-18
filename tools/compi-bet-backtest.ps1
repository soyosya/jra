<#
.SYNOPSIS
  コンピ指数の順位を「軸」にして、券種別(複勝/ワイド/馬連/三連複/三連単)の的中率・回収率を実払戻でバックテストします。

.DESCRIPTION
  各レースで馬をコンピ指数の降順に並べ(=コンピ1位が軸)、順位ベースで買い目を機械的に組み、払戻金テーブルの実配当で集計します。
  オッズもh2hも使わない「コンピ軸の素の実力」。どの券種・どの構成が最も的中/回収に効くかを比較し、買い方の判断材料にします。
  - 配当は払戻金(100円あたり金額)。回収率% = 100 * Σ的中金額 / Σ投資(1点=100円)。
  - 馬の同定は馬番。ばんえい除外。コンピは最新スナップショット・指数NULL除外。

.PARAMETER Venue   '' なら全場(ばんえい除く)。'高知' 等で1場に限定。
.PARAMETER From / To  期間。
.PARAMETER MinField   この頭数未満のレースは除外(既定6)。
#>
[CmdletBinding()]
param(
  [string]$Venue = '',
  [string]$From = '2025-09-01',
  [string]$To = '2026-06-14',
  [int]$MinField = 6,
  # コンピ1位と2位の指数差バケット別に的中率・回収率を分解(大差=本命が抜けている時に妙味があるか)。
  [switch]$ByGap
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
  # 1) 着順(競走結果)
  $cmd = NewCmd "SELECT 開催場所,開催日,レース番号,馬番,着順 FROM 競走結果 WHERE 着順>0 AND 開催日>=@f AND 開催日<=@t $venFilter"
  $r=$cmd.ExecuteReader(); $fin=@{}
  while($r.Read()){ $key='{0}|{1:yyyy-MM-dd}|{2}' -f $r.GetString(0),$r.GetDateTime(1),$r.GetInt32(2)
    if(-not $fin.ContainsKey($key)){ $fin[$key]=@{} }; $fin[$key][[int]$r.GetInt32(3)]=[int]$r.GetInt32(4) }
  $r.Close()

  # 2) コンピ指数(最新スナップショット) 馬番→指数
  $cmd = NewCmd @"
WITH s AS (
  SELECT 開催日,開催場所,レース番号,馬番,指数,
    ROW_NUMBER() OVER(PARTITION BY 開催日,開催場所,レース番号,馬番 ORDER BY 取得日時 DESC) rn
  FROM コンピ指数 WHERE 開催日>=@f AND 開催日<=@t $venFilter
)
SELECT 開催場所,開催日,レース番号,馬番,指数 FROM s WHERE rn=1 AND 指数 IS NOT NULL
"@
  $r=$cmd.ExecuteReader(); $compi=@{}
  while($r.Read()){ $key='{0}|{1:yyyy-MM-dd}|{2}' -f $r.GetString(0),$r.GetDateTime(1),$r.GetInt32(2)
    if(-not $compi.ContainsKey($key)){ $compi[$key]=@{} }; $compi[$key][[int]$r.GetInt32(3)]=[int]$r.GetInt32(4) }
  $r.Close()

  # 3) 払戻金(全券種)
  $cmd = NewCmd "SELECT 開催場所,開催日,レース番号,馬券,組番,金額 FROM 払戻金 WHERE 開催日>=@f AND 開催日<=@t $venFilter"
  $r=$cmd.ExecuteReader(); $pay=@{}
  while($r.Read()){ $key='{0}|{1:yyyy-MM-dd}|{2}' -f $r.GetString(0),$r.GetDateTime(1),$r.GetInt32(2)
    $bk=$r.GetString(3); $kumi=([string]$r.GetValue(4)).Trim(); $amt=[double]$r.GetValue(5)
    if($kumi -eq ''){ continue }
    if(-not $pay.ContainsKey($key)){ $pay[$key]=@{} }; if(-not $pay[$key].ContainsKey($bk)){ $pay[$key][$bk]=@{} }
    $parts=$kumi -split '-'
    # 順序なし券種は組番をソートして正規化(複勝は単一馬番)
    $norm = if($bk -eq '三連単' -or $bk -eq '馬連単' -or $bk -eq '枠連単'){ ($parts -join '-') }
            else { (($parts | ForEach-Object{[int]$_} | Sort-Object) -join '-') }
    $pay[$key][$bk][$norm]=$amt }
  $r.Close()
  $conn.Close()
  Write-Host ("  着順レース {0:N0} / コンピレース {1:N0}" -f $fin.Count,$compi.Count)

  # コンピ順位で並べた馬番配列(指数降順, 同値は馬番昇順)
  function RankedUma($key){ if(-not $compi.ContainsKey($key)){ return @() }
    return @($compi[$key].GetEnumerator() | Sort-Object @{e={$_.Value};Descending=$true},@{e={[int]$_.Key};Descending=$false} | ForEach-Object{ [int]$_.Key }) }
  function KeyOf([int[]]$arr,[bool]$ordered){ if($ordered){ ($arr -join '-') } else { (($arr | Sort-Object) -join '-') } }
  function NewL { ,(New-Object System.Collections.Generic.List[object]) }
  function Pairs($a){ $L=New-Object System.Collections.Generic.List[object]; for($i=0;$i -lt $a.Count;$i++){ for($j=$i+1;$j -lt $a.Count;$j++){ $L.Add(@($a[$i],$a[$j])) } }; return ,$L }
  function Triples($a){ $L=New-Object System.Collections.Generic.List[object]; for($i=0;$i -lt $a.Count;$i++){ for($j=$i+1;$j -lt $a.Count;$j++){ for($k=$j+1;$k -lt $a.Count;$k++){ $L.Add(@($a[$i],$a[$j],$a[$k])) } } }; return ,$L }

  # 戦略定義: 各レースの ranked 馬番配列 R を受け取り、買い目(馬番配列)の List を返す。
  # ※ PowerShellの配列リテラル平坦化を避けるため List に Add する。
  $strats = @(
    @{ name='複勝 本命(コ1)         '; bk='複勝';   ordered=$false; need=1; combos={ param($R) $L=New-Object System.Collections.Generic.List[object]; $L.Add(@($R[0])); ,$L } },
    @{ name='複勝 コ1+コ2           '; bk='複勝';   ordered=$false; need=2; combos={ param($R) $L=New-Object System.Collections.Generic.List[object]; $L.Add(@($R[0])); $L.Add(@($R[1])); ,$L } },
    @{ name='ワイド 軸コ1-相手コ2,3  '; bk='ワイド'; ordered=$false; need=3; combos={ param($R) $L=New-Object System.Collections.Generic.List[object]; $L.Add(@($R[0],$R[1])); $L.Add(@($R[0],$R[2])); ,$L } },
    @{ name='ワイド 軸コ1-相手コ2-4  '; bk='ワイド'; ordered=$false; need=4; combos={ param($R) $L=New-Object System.Collections.Generic.List[object]; $L.Add(@($R[0],$R[1])); $L.Add(@($R[0],$R[2])); $L.Add(@($R[0],$R[3])); ,$L } },
    @{ name='ワイド BOXコ1-3         '; bk='ワイド'; ordered=$false; need=3; combos={ param($R) Pairs($R[0..2]) } },
    @{ name='馬連 軸コ1-相手コ2-4    '; bk='馬連複'; ordered=$false; need=4; combos={ param($R) $L=New-Object System.Collections.Generic.List[object]; $L.Add(@($R[0],$R[1])); $L.Add(@($R[0],$R[2])); $L.Add(@($R[0],$R[3])); ,$L } },
    @{ name='馬連 BOXコ1-3           '; bk='馬連複'; ordered=$false; need=3; combos={ param($R) Pairs($R[0..2]) } },
    @{ name='三連複 軸コ1-相手コ2-5  '; bk='三連複'; ordered=$false; need=5; combos={ param($R) $L=New-Object System.Collections.Generic.List[object]; foreach($p in (Pairs($R[1..4]))){ $L.Add(@($R[0],$p[0],$p[1])) }; ,$L } },
    @{ name='三連複 BOXコ1-4         '; bk='三連複'; ordered=$false; need=4; combos={ param($R) Triples($R[0..3]) } },
    @{ name='三連複 BOXコ1-5         '; bk='三連複'; ordered=$false; need=5; combos={ param($R) Triples($R[0..4]) } },
    @{ name='三連単 1着コ1→2,3着コ2-4 '; bk='三連単'; ordered=$true;  need=4; combos={ param($R) $L=New-Object System.Collections.Generic.List[object]; foreach($p in (Pairs($R[1..3]))){ $L.Add(@($R[0],$p[0],$p[1])); $L.Add(@($R[0],$p[1],$p[0])) }; ,$L } },
    @{ name='三連単 1着コ1→2,3着コ2-5 '; bk='三連単'; ordered=$true;  need=5; combos={ param($R) $L=New-Object System.Collections.Generic.List[object]; foreach($p in (Pairs($R[1..4]))){ $L.Add(@($R[0],$p[0],$p[1])); $L.Add(@($R[0],$p[1],$p[0])) }; ,$L } }
  )

  function GapBucket([int]$g){ if($g -ge 20){'20+'}elseif($g -ge 15){'15-19'}elseif($g -ge 10){'10-14'}elseif($g -ge 5){'5-9'}else{'0-4'} }
  $gapOrder = @('0-4','5-9','10-14','15-19','20+')
  $agg=@{}; foreach($s in $strats){ $agg[$s.name]=@{ races=0; hitRaces=0; stake=0.0; ret=0.0; pts=0 } }
  $aggG=@{}   # name -> bucket -> stats

  foreach($key in $fin.Keys){
    if($fin[$key].Count -lt $MinField){ continue }
    $R = RankedUma $key
    if($R.Count -lt 2){ continue }
    if(-not $pay.ContainsKey($key)){ continue }
    $gb = GapBucket ([int]$compi[$key][$R[0]] - [int]$compi[$key][$R[1]])
    foreach($s in $strats){
      if($R.Count -lt $s.need){ continue }
      $combos = & $s.combos $R
      if($combos.Count -eq 0){ continue }
      $book = if($pay[$key].ContainsKey($s.bk)){ $pay[$key][$s.bk] } else { @{} }
      $hit=$false; $raceRet=0.0
      foreach($cmb in $combos){ $kk=KeyOf $cmb $s.ordered; if($book.ContainsKey($kk)){ $raceRet += $book[$kk]; $hit=$true } }
      $a=$agg[$s.name]; $a.races++; $a.pts += $combos.Count; $a.stake += 100.0*$combos.Count; $a.ret += $raceRet; if($hit){ $a.hitRaces++ }
      if($ByGap){
        if(-not $aggG.ContainsKey($s.name)){ $aggG[$s.name]=@{} }
        if(-not $aggG[$s.name].ContainsKey($gb)){ $aggG[$s.name][$gb]=@{ races=0; hitRaces=0; stake=0.0; ret=0.0 } }
        $ag=$aggG[$s.name][$gb]; $ag.races++; $ag.stake += 100.0*$combos.Count; $ag.ret += $raceRet; if($hit){ $ag.hitRaces++ }
      }
    }
  }

  Write-Host ("`n=== コンピ軸 券種別バックテスト ({0} {1}〜{2}, 最小{3}頭) ===" -f ($(if($Venue){$Venue}else{'全場'})),$From,$To,$MinField)
  $rep = foreach($s in $strats){ $a=$agg[$s.name]; if($a.races -eq 0){ continue }
    [PSCustomObject]@{
      戦略=$s.name; 券種=$s.bk; レース=$a.races
      平均点=[Math]::Round($a.pts/$a.races,1)
      的中率=[Math]::Round(100.0*$a.hitRaces/$a.races,1)
      回収率=[Math]::Round(100.0*$a.ret/$a.stake,1)
      投資円=[int]$a.stake
    } }
  $rep | Format-Table 戦略,券種,レース,平均点,的中率,回収率,投資円 -AutoSize | Out-String -Width 200 | Write-Host

  if($ByGap){
    Write-Host "`n=== 指数差(コンピ1位−2位)バケット別 ── 大差ほど本命が抜けているか ==="
    $pats = @('複勝 本命*','複勝 コ1+コ2*','ワイド 軸*2-4*','馬連 軸*2-4*','三連複 軸*2-5*','三連単*2-5*')
    foreach($p in $pats){
      $nm = @($aggG.Keys | Where-Object { $_ -like $p } | Sort-Object)[0]
      if(-not $nm){ continue }
      Write-Host ("`n[{0}]" -f $nm.Trim())
      $rows = foreach($b in $gapOrder){ if($aggG[$nm].ContainsKey($b)){ $g=$aggG[$nm][$b]
        [PSCustomObject]@{ 指数差=$b; レース=$g.races; 的中率=[Math]::Round(100.0*$g.hitRaces/$g.races,1); 回収率=[Math]::Round(100.0*$g.ret/$g.stake,1) } } }
      $rows | Format-Table 指数差,レース,的中率,回収率 -AutoSize | Out-String -Width 120 | Write-Host
    }
  }
}
finally { if($conn.State -eq 'Open'){ $conn.Close() } }
