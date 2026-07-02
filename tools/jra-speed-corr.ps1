<#
.SYNOPSIS
  競馬ブック「スピード指数」と着順の相関を調べる。
.DESCRIPTION
  競馬ブック能力指数(種別='speed')は各馬の過去走ごとの値+過去内容("ダ良1600m 6着")を持つ。
  過去内容から コース/馬場/距離/着順 を抽出し、スピード指数値(値)と着順の関係を評価する:
    (1) 全体相関  : Pearson r / Spearman ρ(値 vs 着順)。値↑=速い=着順↓を期待(負相関)。
    (2) 値5分位   : 各バケットの 平均着順 / 勝率(1着) / 複勝率(3着内) で単調性を確認。
    (3) コース別  : 芝/ダ で Pearson r。
    (4) レース内順位: 同一過去race_idに N頭以上そろう場合のみ、レース内でスピード値を順位化し
                      順位 vs 着順 の Spearman をレース平均(真の「順位vs着順」だが現状サンプル小)。
  注意: (1)(2)は同一レースの値と着順=走破タイム由来で機械的に連動する面がある。
        「出馬表時点のスピード指数順位→次走着順」の予測力検証は、前向き蓄積(能力指数×将来の結果)が必要。
.PARAMETER MinFieldForRank  レース内順位相関に必要な最小頭数(既定5)。
#>
[CmdletBinding()]
param([int]$MinFieldForRank=5)
$ErrorActionPreference='Stop'
$cs=(Get-Content (Join-Path $PSScriptRoot '..\共通\appsettings.json') -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
$conn=New-Object System.Data.SqlClient.SqlConnection($cs);$conn.Open()
$cmd=$conn.CreateCommand();$cmd.CommandTimeout=120
$cmd.CommandText="SELECT 過去race_id rid,値 v,過去内容 c FROM 競馬ブック能力指数 WHERE 種別='speed' AND 値 IS NOT NULL AND 過去内容 LIKE '%着%'"
$r=$cmd.ExecuteReader()
$rows=New-Object System.Collections.Generic.List[object]
while($r.Read()){
  $c=[string]$r['c']
  $m=[regex]::Match($c,'(芝|ダ|障)(.?)(\d{3,4})m\D*(\d+)着')
  if(-not $m.Success){ continue }
  $rows.Add([pscustomobject]@{ rid=[string]$r['rid']; v=[double]$r['v']; surf=$m.Groups[1].Value; dist=[int]$m.Groups[3].Value; chaku=[int]$m.Groups[4].Value })
}
$r.Close();$conn.Close()
$n=$rows.Count
"スピード指数×着順 相関  (解析対象 {0}行 / 競馬ブック能力指数 種別=speed)" -f $n
""

function Pearson($xs,$ys){
  $n=$xs.Count; if($n -lt 3){ return [double]::NaN }
  $mx=($xs|Measure-Object -Average).Average; $my=($ys|Measure-Object -Average).Average
  $sxy=0.0;$sxx=0.0;$syy=0.0
  for($i=0;$i -lt $n;$i++){ $dx=$xs[$i]-$mx; $dy=$ys[$i]-$my; $sxy+=$dx*$dy; $sxx+=$dx*$dx; $syy+=$dy*$dy }
  if($sxx -eq 0 -or $syy -eq 0){ return [double]::NaN }
  return $sxy/[Math]::Sqrt($sxx*$syy)
}
# 平均順位(同順位は平均ランク)
function RankAvg($vals){
  $idx=0..($vals.Count-1) | Sort-Object { $vals[$_] }
  $ranks=New-Object 'double[]' $vals.Count
  $i=0
  while($i -lt $idx.Count){
    $j=$i
    while($j+1 -lt $idx.Count -and $vals[$idx[$j+1]] -eq $vals[$idx[$i]]){ $j++ }
    $avg=(($i+1)+($j+1))/2.0
    for($k=$i;$k -le $j;$k++){ $ranks[$idx[$k]]=$avg }
    $i=$j+1
  }
  return $ranks
}
function Spearman($xs,$ys){ Pearson (RankAvg $xs) (RankAvg $ys) }

$V=$rows.v; $C=[double[]]($rows.chaku)
"=== (1) 全体相関 (値 vs 着順) ==="
"  Pearson r  = {0:N3}" -f (Pearson $V $C)
"  Spearman ρ = {0:N3}   (負=スピード指数が高いほど着順が良い)" -f (Spearman $V $C)
""

"=== (2) スピード指数 5分位 → 着成績 ==="
$sorted=$rows | Sort-Object v
$per=[int][Math]::Floor($n/5)
"  分位        件数   値域         平均着順  勝率%   複勝率%"
for($q=0;$q -lt 5;$q++){
  $st=$q*$per; $en= if($q -eq 4){$n-1}else{(($q+1)*$per-1)}
  $seg=$sorted[$st..$en]
  $avgc=($seg.chaku|Measure-Object -Average).Average
  $win=100.0*(@($seg|?{$_.chaku -eq 1}).Count)/$seg.Count
  $plc=100.0*(@($seg|?{$_.chaku -le 3}).Count)/$seg.Count
  "  Q{0}(下位=遅)  {1,4}  {2,5:N1}-{3,5:N1}  {4,7:N2}  {5,5:N1}  {6,6:N1}" -f ($q+1),$seg.Count,$seg[0].v,$seg[-1].v,$avgc,$win,$plc
}
"  ※Q5=スピード指数が最も高い群"
""

"=== (3) コース種別別 Pearson r ==="
foreach($s in '芝','ダ'){
  $g=$rows|?{$_.surf -eq $s}
  if($g.Count -ge 10){ "  {0}: r={1:N3}  (n={2})" -f $s,(Pearson ([double[]]$g.v) ([double[]]$g.chaku)),$g.Count }
}
""

"=== (4) レース内順位 vs 着順 (同一過去raceに{0}頭以上) ===" -f $MinFieldForRank
$byRace=$rows | Group-Object rid | ?{ $_.Count -ge $MinFieldForRank }
if($byRace.Count -eq 0){ "  対象レースなし(現状は同一過去raceに複数の6/20出走馬が揃う例が少ない)" }
else{
  $rhos=@()
  foreach($g in $byRace){
    $vs=[double[]]($g.Group.v); $cs2=[double[]]($g.Group.chaku)
    $rho=Spearman $vs $cs2
    if(-not [double]::IsNaN($rho)){ $rhos+=$rho }
  }
  "  対象レース数={0} / レース内Spearman平均 ρ={1:N3} (負=指数上位ほど好走)" -f $rhos.Count,(($rhos|Measure-Object -Average).Average)
}
""
"※注意: (1)(2)は同一走の値と着順=走破タイム由来で機械的連動を含む。出馬表時点の指数順位で次走着順を当てる予測力は、能力指数×将来結果の前向き蓄積後に jra-speed-corr 系で別途検証要。"