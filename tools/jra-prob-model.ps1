<#
.SYNOPSIS
  中央競馬 軸確度の較正済み確率モデル(ロジスティック回帰)。手重みを学習重みへ置換。
.DESCRIPTION
  特徴量 テーブルを読み、2023 H1(〜6/30)で学習・H2(7/1〜)で検証。
  - 学習ループは inline C#(高速)。L2正則化つきバッチ勾配降下。
  - ラベル win(着順1)。特徴は出走前既知のみ(コンピ/過去SF/構造)。欠損は補完+有無フラグ。
  - 評価: LogLoss / AUC / 較正(予測確率ビン vs 実勝率) / レース本命的中率(モデル vs コンピ1位 vs 1番人気)。
  - 全2023行の予測 p_win を 予測 テーブルへ書き出し(EV検証 jra-ev-backtest.ps1 が利用)。
#>
[CmdletBinding()] param([int]$Iters=600,[double]$Lr=0.3,[double]$L2=1.0,[switch]$UseMarket,[switch]$UseAgari,
  [int]$TestYear=0,[int[]]$TrainYears=@(2023))
$ErrorActionPreference='Stop'
$connStr=(Get-Content 'C:\jra\共通\appsettings.json' -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection

Add-Type -TypeDefinition @"
using System;
public static class LogReg {
  public static double[] Fit(double[][] X,int[] y,int iters,double lr,double l2){
    int n=X.Length, d=X[0].Length; var w=new double[d]; double b=0;
    for(int it=0;it<iters;it++){
      var g=new double[d]; double gb=0;
      for(int i=0;i<n;i++){
        double z=b; var xi=X[i]; for(int j=0;j<d;j++) z+=w[j]*xi[j];
        double p=1.0/(1.0+Math.Exp(-z)); double e=p-y[i];
        for(int j=0;j<d;j++) g[j]+=e*xi[j]; gb+=e;
      }
      for(int j=0;j<d;j++){ g[j]=g[j]/n + l2*w[j]/n; w[j]-=lr*g[j]; }
      b-=lr*gb/n;
    }
    var res=new double[d+1]; Array.Copy(w,res,d); res[d]=b; return res;
  }
  public static double P(double[] w,double b,double[] x){
    double z=b; for(int j=0;j<x.Length;j++) z+=w[j]*x[j]; return 1.0/(1.0+Math.Exp(-z));
  }
}
"@

$conn=New-Object System.Data.SqlClient.SqlConnection($connStr); $conn.Open()
$years = if($TestYear -gt 0){ @($TrainYears + $TestYear) | Select-Object -Unique } else { @(2023) }
$yearList = ($years -join ',')
$sql=@"
SELECT 開催場所,開催日,レース番号,馬番,頭数,
 compi_z,compi_relrank,sf_best,sf_avg3,sf_last,n_prior,days_since,kinryo_z,taiju_delta,waku,age,is_hin,
 v3,keshi,h2h,n_h2h,agari_st,
 tan_odds,ninki,win,plc
FROM 特徴量 WHERE YEAR(開催日) IN ($yearList) AND tan_odds IS NOT NULL AND tan_odds>0
"@
$cmd=$conn.CreateCommand();$cmd.CommandTimeout=120;$cmd.CommandText=$sql
$r=$cmd.ExecuteReader()
$rows=New-Object System.Collections.Generic.List[object]
function DV($v){ if($v -is [DBNull]){return $null}; return $v }
while($r.Read()){
  $rows.Add([PSCustomObject]@{
    v=$r['開催場所'];d=[datetime]$r['開催日'];rno=[int]$r['レース番号'];no=[int]$r['馬番'];cnt=[int]$r['頭数']
    compi_z=DV $r['compi_z']; relrank=DV $r['compi_relrank']
    sfb=DV $r['sf_best']; sfa=DV $r['sf_avg3']; sfl=DV $r['sf_last']; np=[int]$r['n_prior']; ds=DV $r['days_since']
    kz=DV $r['kinryo_z']; td=DV $r['taiju_delta']; waku=[int]$r['waku']; age=[int]$r['age']; hin=[int]$r['is_hin']
    v3=DV $r['v3']; keshi=DV $r['keshi']; h2h=DV $r['h2h']; nh2h=DV $r['n_h2h']; ast=DV $r['agari_st']
    odds=[double]$r['tan_odds']; nin=(DV $r['ninki']); win=[int]$r['win']; plc=[int]$r['plc']
  })
}
$r.Close()
Write-Host ("読込 {0} 行(2023・オッズ有)" -f $rows.Count)

# 市場含意勝率(レース内で 1/odds を正規化)を各馬へ付与
foreach($g in ($rows | Group-Object {"$($_.v)|$($_.d.ToString('yyyyMMdd'))|$($_.rno)"})){
  $sum=0.0; foreach($x in $g.Group){ $sum += 1.0/$x.odds }
  foreach($x in $g.Group){ $x | Add-Member mktp ((1.0/$x.odds)/$sum) -Force }
}

# --- 特徴ベクトル化(欠損補完+フラグ) ---
$featNames=@('compi_z','relrank','sfb','sfa','sfl','np','ds','kz','td','waku','age','hin','hassf','v3','keshi','h2h','hash2h')
if($UseMarket){ $featNames += 'mktp' }
if($UseAgari){ $featNames += 'agari' }
function Vec($x){
  $hassf = [double]([int]($x.np -gt 0))
  $hash2h = [double]([int]($null -ne $x.h2h))
  $base = @(
    [double]$(if($null -ne $x.compi_z){$x.compi_z}else{0}),
    [double]$(if($null -ne $x.relrank){$x.relrank}else{0.5}),
    [double]$(if($null -ne $x.sfb){$x.sfb}else{50}),
    [double]$(if($null -ne $x.sfa){$x.sfa}else{50}),
    [double]$(if($null -ne $x.sfl){$x.sfl}else{50}),
    [double]$x.np,
    [double]$(if($null -ne $x.ds){[math]::Min($x.ds,400)}else{45}),
    [double]$(if($null -ne $x.kz){$x.kz}else{0}),
    [double]$(if($null -ne $x.td){$x.td}else{0}),
    [double]$x.waku,[double]$x.age,[double]$x.hin,$hassf,
    [double]$(if($null -ne $x.v3){$x.v3}else{0}),
    [double]$(if($null -ne $x.keshi){$x.keshi}else{0}),
    [double]$(if($null -ne $x.h2h){$x.h2h}else{0}),
    $hash2h
  )
  if($UseMarket){ $base += [double]$x.mktp }
  if($UseAgari){ $base += [double]$(if($null -ne $x.ast){$x.ast}else{0}) }
  ,$base
}
foreach($x in $rows){ $x | Add-Member raw (Vec $x) -Force }

# --- 学習/検証分割 ---
if($TestYear -gt 0){
  $train=$rows | Where-Object { $TrainYears -contains $_.d.Year }
  $test =$rows | Where-Object { $_.d.Year -eq $TestYear }
  $splitDesc = "学習 $($TrainYears -join '+') → 検証 $TestYear (クロスイヤーOOS)"
} else {
  $cut=[datetime]'2023-07-01'
  $train=$rows | Where-Object { $_.d -lt $cut }
  $test =$rows | Where-Object { $_.d -ge $cut }
  $splitDesc = "2023 H1学習 → H2検証"
}
Write-Host ("[{0}]  学習 {1} / 検証 {2} 行" -f $splitDesc,$train.Count,$test.Count)

# --- 標準化(学習データの平均/SD) ---
$D=$featNames.Count; $mu=New-Object double[] $D; $sd=New-Object double[] $D
for($j=0;$j -lt $D;$j++){
  $col=[double[]]($train | ForEach-Object { $_.raw[$j] })
  $m=($col|Measure-Object -Average).Average; $mu[$j]=$m
  $v=0.0; foreach($c in $col){ $v+=($c-$m)*($c-$m) }; $s=[math]::Sqrt($v/[math]::Max($col.Count-1,1)); if($s -le 0){$s=1}; $sd[$j]=$s
}
function Std($raw){ $o=New-Object double[] $D; for($j=0;$j -lt $D;$j++){ $o[$j]=($raw[$j]-$mu[$j])/$sd[$j] }; ,$o }
foreach($x in $rows){ $x | Add-Member z (Std $x.raw) -Force }

# --- 学習 ---
$X=New-Object 'double[][]' $train.Count; $Y=New-Object 'int[]' $train.Count
for($i=0;$i -lt $train.Count;$i++){ $X[$i]=$train[$i].z; $Y[$i]=$train[$i].win }
$wb=[LogReg]::Fit($X,$Y,$Iters,$Lr,$L2)
$w=$wb[0..($D-1)]; $b=$wb[$D]
Write-Host "`n■ 学習済み係数(標準化空間, 効き順):"
$pairs=for($j=0;$j -lt $D;$j++){ [PSCustomObject]@{f=$featNames[$j];w=[math]::Round($w[$j],3)} }
$pairs | Sort-Object { -[math]::Abs($_.w) } | ForEach-Object { "  {0,-9} {1,7}" -f $_.f,$_.w }

# --- 予測付与 ---
foreach($x in $rows){ $x | Add-Member p ([LogReg]::P($w,$b,$x.z)) -Force }

# --- 評価関数 ---
function LogLoss($set){ $s=0.0;$n=0; foreach($x in $set){ $p=[math]::Min([math]::Max($x.p,1e-9),1-1e-9); $s+= -($x.win*[math]::Log($p)+(1-$x.win)*[math]::Log(1-$p)); $n++ }; $s/$n }
function AUC($set){
  $pos=$set|Where-Object{$_.win -eq 1}; $neg=$set|Where-Object{$_.win -eq 0}
  if($pos.Count -eq 0 -or $neg.Count -eq 0){return [double]::NaN}
  $all=$set|Sort-Object p; $rank=1;$sum=0.0
  foreach($x in $all){ if($x.win -eq 1){$sum+=$rank}; $rank++ }
  ($sum - $pos.Count*($pos.Count+1)/2)/($pos.Count*$neg.Count)
}
"`n■ 検証({2}):  LogLoss {0:F4}   AUC {1:F4}" -f (LogLoss $test),(AUC $test),$splitDesc
"   参考 学習側:   LogLoss {0:F4}   AUC {1:F4}" -f (LogLoss $train),(AUC $train)

# --- 較正(検証データ・予測確率十分位) ---
"`n■ 較正(H2検証・予測p_win 十分位):"
"{0,-10} {1,7} {2,9} {3,9}" -f 'pバケット','n','平均p','実勝率'
$sortedTest=$test|Sort-Object p
$bn=[int][math]::Ceiling($sortedTest.Count/10)
for($i=0;$i -lt 10;$i++){
  $grp=$sortedTest[($i*$bn)..([math]::Min(($i+1)*$bn-1,$sortedTest.Count-1))]
  if($grp.Count -eq 0){continue}
  $ap=($grp|Measure-Object p -Average).Average; $aw=($grp|Measure-Object win -Average).Average
  "{0,-10} {1,7} {2,9:P1} {3,9:P1}" -f ("D"+($i+1)),$grp.Count,$ap,$aw
}

# --- レース本命的中: モデル最上位 vs コンピ1位 vs 1番人気 ---
function TopHit($set,$selector){
  $races=$set|Group-Object {"$($_.v)|$($_.d.ToString('yyyyMMdd'))|$($_.rno)"}
  $hit=0;$tot=0
  foreach($g in $races){ $pick=$g.Group|Sort-Object $selector|Select-Object -First 1; if($pick.win -eq 1){$hit++}; $tot++ }
  [PSCustomObject]@{hit=$hit;tot=$tot;rate=[double]$hit/$tot}
}
$mh=TopHit $test { -$_.p }
$ch=TopHit $test { $_.relrank }     # relrank 0=コンピ1位
$nh=TopHit $test { $(if($null -eq $_.nin){999}else{$_.nin}) }   # 人気 1=1番人気
"`n■ レース本命の1着的中率({0} レース):" -f $mh.tot
"  モデル最上位 : {0:P1}  ({1}/{2})" -f $mh.rate,$mh.hit,$mh.tot
"  コンピ1位    : {0:P1}  ({1}/{2})" -f $ch.rate,$ch.hit,$ch.tot
"  1番人気      : {0:P1}  ({1}/{2})" -f $nh.rate,$nh.hit,$nh.tot

# --- 軸の堅さ(勝率/複勝率): モデル本命 vs 1番人気 ---
function TopStat($set,$selector){
  $races=$set|Group-Object {"$($_.v)|$($_.d.ToString('yyyyMMdd'))|$($_.rno)"}
  $w=0;$p=0;$tot=0
  foreach($g in $races){ $pick=$g.Group|Sort-Object $selector|Select-Object -First 1; if($pick.win -eq 1){$w++}; if($pick.plc -eq 1){$p++}; $tot++ }
  [PSCustomObject]@{win=[double]$w/$tot;plc=[double]$p/$tot;tot=$tot}
}
$ms=TopStat $test { -$_.p }
$fs=TopStat $test { $(if($null -eq $_.nin){999}else{$_.nin}) }
"`n■ 軸の堅さ({4}R):  モデル本命 勝{0:P1}/複{1:P1}   1番人気 勝{2:P1}/複{3:P1}" -f $ms.win,$ms.plc,$fs.win,$fs.plc,$ms.tot
"  → モデル−人気 差: 勝 {0:+0.0;-0.0}pt / 複 {1:+0.0;-0.0}pt" -f (100*($ms.win-$fs.win)),(100*($ms.plc-$fs.plc))

# --- 予測テーブルへ書き出し ---
$conn2=$conn
$ensure=@"
IF OBJECT_ID('dbo.予測','U') IS NULL
CREATE TABLE dbo.予測(開催場所 nvarchar(10),開催日 date,レース番号 int,馬番 int,p_win float,split nvarchar(8),
 CONSTRAINT PK_予測 PRIMARY KEY(開催場所,開催日,レース番号,馬番));
"@
$c=$conn2.CreateCommand();$c.CommandText=$ensure;[void]$c.ExecuteNonQuery()
if($TestYear -gt 0){
  # OOS: 検証年のみ split='oos' で書き出し(2023のpre-odds予測は保持)
  $c.CommandText="DELETE FROM dbo.予測 WHERE YEAR(開催日)=$TestYear"; [void]$c.ExecuteNonQuery()
  $writeRows=$test; $splitVal='oos'
}else{
  $c.CommandText="DELETE FROM dbo.予測 WHERE YEAR(開催日)=2023"; [void]$c.ExecuteNonQuery()
  $writeRows=$rows; $splitVal=$null
}
$dt=New-Object System.Data.DataTable; '開催場所','開催日','レース番号','馬番','p_win','split'|ForEach-Object{[void]$dt.Columns.Add($_)}
foreach($x in $writeRows){
  $sp = if($null -ne $splitVal){$splitVal} elseif($x.d -lt $cut){'train'} else {'test'}
  [void]$dt.Rows.Add($x.v,$x.d,$x.rno,$x.no,$x.p,$sp)
}
$bulk=New-Object System.Data.SqlClient.SqlBulkCopy($conn2);$bulk.DestinationTableName='dbo.予測';$bulk.BatchSize=5000
foreach($cc in $dt.Columns){[void]$bulk.ColumnMappings.Add($cc.ColumnName,$cc.ColumnName)}
$bulk.WriteToServer($dt)
if($TestYear -le 0){
  $model=[PSCustomObject]@{features=$featNames;w=$w;b=$b;mu=$mu;sd=$sd;trainCut='2023-07-01'}
  $model|ConvertTo-Json -Depth 5|Set-Content (Join-Path $PSScriptRoot '_jra_prob_model.json') -Encoding UTF8
}
Write-Host ("`n✓ 予測 へ {0} 行 (split={1})" -f $dt.Rows.Count,$(if($splitVal){$splitVal}else{'train/test'}))
$conn.Close()
