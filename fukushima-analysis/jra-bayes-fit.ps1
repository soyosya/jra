<#
  JRAベイズ複勝較正 モデルA(順位band+指数Z+h2h)を全データ(jra_bayes_feat.csv)で学習し
  係数JSON(C:\jra\tools\jra-bayes-model-A.json)を出力。jra-cardが読み込み複勝確率→確度ラベル化する。
  特徴量: [bias, rank2-3, rank4-6, rank7+, idxZ, h2hHas, h2hRankZ]  (脚質はJRAで寄与≈0のため除外)
#>
$ErrorActionPreference='Stop'
try{ $OutputEncoding=[Console]::OutputEncoding=[Text.Encoding]::UTF8 }catch{}
$featCsv= if(Test-Path 'C:\jra\fukushima-analysis\jra_bayes_feat.csv'){'C:\jra\fukushima-analysis\jra_bayes_feat.csv'}else{'C:\temp\jra_bayes_feat.csv'}
$rows=Import-Csv $featCsv
$data=@(foreach($r in $rows){ [pscustomobject]@{ rb=[int]$r.rb; idx=[double]$r.idx; hr=[int]$r.hr; fuku=[int]$r.fuku } })
$N=$data.Count
Write-Host "学習データ: $N 行"
# 標準化
$idxM=($data|Measure-Object idx -Average).Average
$idxS=[math]::Sqrt((($data|ForEach-Object{ ($_.idx-$idxM)*($_.idx-$idxM) })|Measure-Object -Average).Average)
$ht=@($data|Where-Object{ $_.hr -gt 0 })
$hrM=($ht|Measure-Object hr -Average).Average
$hrS=[math]::Sqrt((($ht|ForEach-Object{ ($_.hr-$hrM)*($_.hr-$hrM) })|Measure-Object -Average).Average)
Write-Host ("std: idxM={0:F2} idxS={1:F2} hrM={2:F2} hrS={3:F2}  h2h有={4}行" -f $idxM,$idxS,$hrM,$hrS,$ht.Count)
# 設計行列(モデルA, D=7)
$D=7
$X=[System.Collections.Generic.List[double[]]]::new($N); $Y=[System.Collections.Generic.List[double]]::new($N)
for($i=0;$i -lt $N;$i++){ $r=$data[$i]
  $hz= if($r.hr -gt 0){ ($r.hr-$hrM)/$hrS } else { 0.0 }
  $X.Add([double[]]@(1.0,[double]($r.rb -eq 2),[double]($r.rb -eq 3),[double]($r.rb -eq 4),(($r.idx-$idxM)/$idxS),[double]($r.hr -gt 0),[double]$hz))
  $Y.Add([double]$r.fuku)
}
function Sig($z){ if($z -ge 0){ 1.0/(1.0+[math]::Exp(-$z)) } else { $e=[math]::Exp($z); $e/(1.0+$e) } }
function Solve($A,$b,$d){ for($c=0;$c -lt $d;$c++){ $piv=$c; for($rr=$c+1;$rr -lt $d;$rr++){ if([math]::Abs($A[$rr][$c]) -gt [math]::Abs($A[$piv][$c])){$piv=$rr} }
    $t=$A[$c];$A[$c]=$A[$piv];$A[$piv]=$t; $tb=$b[$c];$b[$c]=$b[$piv];$b[$piv]=$tb; $dia=$A[$c][$c]; if([math]::Abs($dia) -lt 1e-12){$dia=1e-12}
    for($rr=0;$rr -lt $d;$rr++){ if($rr -eq $c){continue}; $f=$A[$rr][$c]/$dia; if($f -eq 0){continue}; for($cc=$c;$cc -lt $d;$cc++){ $A[$rr][$cc]-=$f*$A[$c][$cc] }; $b[$rr]-=$f*$b[$c] } }
  $x=New-Object 'double[]' $d; for($c=0;$c -lt $d;$c++){ $x[$c]=$b[$c]/$A[$c][$c] }; return $x }
# IRLS + L2(λ=1, bias除く)
$w=New-Object 'double[]' $D; $lam=1.0
for($it=0;$it -lt 30;$it++){
  $H=New-Object 'double[][]' $D; for($a=0;$a -lt $D;$a++){ $H[$a]=New-Object 'double[]' $D }; $g=New-Object 'double[]' $D
  for($i=0;$i -lt $N;$i++){ $xr=$X[$i]; $z=0.0; for($a=0;$a -lt $D;$a++){ $z+=$w[$a]*$xr[$a] }
    $p=Sig $z; $wt=$p*(1-$p); if($wt -lt 1e-9){$wt=1e-9}; $res=$Y[$i]-$p
    for($a=0;$a -lt $D;$a++){ $xa=$xr[$a]; $g[$a]+=$res*$xa; if($xa -eq 0){continue}; $row=$H[$a]; for($b=0;$b -lt $D;$b++){ $row[$b]+=$wt*$xa*$xr[$b] } } }
  for($a=1;$a -lt $D;$a++){ $H[$a][$a]+=$lam; $g[$a]-=$lam*$w[$a] }  # biasは正則化しない
  $step=Solve $H $g $D; $mx=0.0; for($a=0;$a -lt $D;$a++){ $w[$a]+=$step[$a]; if([math]::Abs($step[$a]) -gt $mx){ $mx=[math]::Abs($step[$a]) } }
  if($mx -lt 1e-7){ break }
}
$names=@('bias','rank2-3','rank4-6','rank7+','idxZ','h2hHas','h2hRankZ')
Write-Host "`n=== モデルA 係数(全データ学習) ==="
for($a=0;$a -lt $D;$a++){ Write-Host ("  {0,-10} {1,8:F4}" -f $names[$a],$w[$a]) }
# 較正チェック(全データ・in-sample簡易): 予測帯別 実測複勝率
$bins=@{}; for($i=0;$i -lt $N;$i++){ $xr=$X[$i]; $z=0.0; for($a=0;$a -lt $D;$a++){ $z+=$w[$a]*$xr[$a] }; $p=Sig $z
  $bk=[math]::Floor($p*10); if($bk -gt 9){$bk=9}; if(-not $bins.ContainsKey($bk)){ $bins[$bk]=@{n=0;ps=0.0;y=0} }
  $bins[$bk].n++; $bins[$bk].ps+=$p; $bins[$bk].y+=$Y[$i] }
Write-Host "`n=== 較正(in-sample) 予測帯|頭数|予測平均|実測 ==="
foreach($bk in ($bins.Keys|Sort-Object)){ $b=$bins[$bk]; Write-Host ("  {0,3}0%: n={1,6} 予測{2,6:P1} 実測{3,6:P1}" -f $bk,$b.n,($b.ps/$b.n),($b.y/$b.n)) }
# JSON出力(jra-card読み取り先)
$obj=[ordered]@{ model='A'; idxM=$idxM; idxS=$idxS; hrM=$hrM; hrS=$hrS; names=$names; weights=@($w) }
$json=$obj|ConvertTo-Json -Depth 4
[IO.File]::WriteAllText('C:\jra\tools\jra-bayes-model-A.json',$json,(New-Object Text.UTF8Encoding($false)))
Write-Host "`n=== 出力: C:\jra\tools\jra-bayes-model-A.json ==="
