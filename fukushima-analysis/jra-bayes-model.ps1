# bayes_feat.csv を読み, NB(順位/+脚質+指数/+h2h) と ロジスティック回帰(IRLS) を学習22-24→検証25-26でOOS比較。
$OutputEncoding=[Console]::OutputEncoding=[System.Text.Encoding]::UTF8
$rows=Import-Csv 'C:\jra\fukushima-analysis\jra_bayes_feat.csv'
foreach($r in $rows){ $r.yr=[int]$r.yr;$r.rb=[int]$r.rb;$r.ps=[int]$r.ps;$r.idx=[double]$r.idx;$r.ib=[int]$r.ib;$r.cb=[int]$r.cb;$r.hr=[int]$r.hr;$r.hb=[int]$r.hb;$r.fuku=[int]$r.fuku }
$train=@($rows|Where-Object{$_.yr -le 2024}); $test=@($rows|Where-Object{$_.yr -ge 2025})
Write-Host ("学習 {0}行 / 検証 {1}行" -f $train.Count,$test.Count)

# ===== メトリクス =====
function Metrics($preds,$ys){
  $n=$preds.Count; $brier=0.0;$ll=0.0
  for($i=0;$i -lt $n;$i++){ $p=$preds[$i]; $y=$ys[$i]; $pc=[math]::Min([math]::Max($p,1e-6),1-1e-6)
    $brier+=[math]::Pow($y-$p,2); $ll+=-($y*[math]::Log($pc)+(1-$y)*[math]::Log(1-$pc)) }
  # AUC
  $idx=0..($n-1)|Sort-Object {$preds[$_]}
  $cumNeg=0.0;$auc=0.0;$tp=0.0;$tn=0.0
  foreach($i in $idx){ if($ys[$i] -eq 1){$tp++}else{$tn++} }
  foreach($i in $idx){ if($ys[$i] -eq 1){ $auc+=$cumNeg+0.5 }else{ $cumNeg++ } }
  if($tp*$tn -gt 0){$auc=$auc/($tp*$tn)}else{$auc=[double]::NaN}
  return [pscustomobject]@{Brier=$brier/$n;LogLoss=$ll/$n;AUC=$auc}
}

# ===== NB(バンド, rank層内LR, Laplace) =====
$alpha=0.5; $rbs=1,2,3,4
$levels=@{ps=@(0,1,2,3,4);ib=@(1,2,3,4);hb=@(0,1,2,3,4)}
$prior=@{};$po=@{};$LR=@{ps=@{};ib=@{};hb=@{}}
foreach($rb in $rbs){
  $tr=@($train|Where-Object{$_.rb -eq $rb}); $nf=@($tr|Where-Object{$_.fuku -eq 1}).Count; $na=$tr.Count; $nn=$na-$nf
  $p=$nf/[double]$na; $prior[$rb]=$p; $po[$rb]=$p/(1-$p)
  foreach($ev in 'ps','ib','hb'){ $LR[$ev][$rb]=@{}; $K=$levels[$ev].Count
    foreach($lv in $levels[$ev]){ $cl=@($tr|Where-Object{$_.$ev -eq $lv}); $fk=@($cl|Where-Object{$_.fuku -eq 1}).Count; $tot=$cl.Count;$non=$tot-$fk
      $pf=($fk+$alpha)/($nf+$alpha*$K); $pnn=($non+$alpha)/($nn+$alpha*$K); $LR[$ev][$rb][$lv]=$pf/$pnn } }
}
function NBpost($r,[string[]]$use){ $o=$po[$r.rb]; foreach($ev in $use){ $o*=$LR[$ev][$r.rb][$r.$ev] }; return $o/(1+$o) }

Write-Host "`n=== OOS: NBモデル ==="
Write-Host ("{0,-26} {1,9} {2,9} {3,8}" -f 'モデル','Brier','LogLoss','AUC')
Write-Host ('-'*56)
$ys=@($test|ForEach-Object{$_.fuku})
foreach($m in @(@{n='M0 順位のみ';u=@()},@{n='M2 +脚質+指数';u=@('ps','ib')},@{n='M2h +脚質+指数+h2h';u=@('ps','ib','hb')})){
  $pr=@($test|ForEach-Object{ NBpost $_ $m.u }); $mt=Metrics $pr $ys
  Write-Host ("{0,-26} {1,9:F5} {2,9:F4} {3,8:F4}" -f $m.n,$mt.Brier,$mt.LogLoss,$mt.AUC)
}

# ===== h2h の限界情報: rank層内 hb別 複勝率(学習) =====
Write-Host "`n=== h2hバンド別 複勝率 (学習22-24, rank層内) ※順位制御後もh2hが効くか ==="
Write-Host ("{0,-8} {1,8} {2,8} {3,8} {4,8} {5,8}" -f 'rank','h2h無','h2h1','h2h2-3','h2h4-6','h2h7+')
foreach($rb in $rbs){ $line=("{0,-8}" -f $rb); foreach($lv in 0,1,2,3,4){ $cl=@($train|Where-Object{$_.rb -eq $rb -and $_.hb -eq $lv}); $fr= if($cl.Count){100.0*@($cl|Where-Object{$_.fuku -eq 1}).Count/$cl.Count}else{0}; $line+=(" {0,7:F1}" -f $fr) }; Write-Host $line }

# ===== ロジスティック回帰 (IRLS) =====
$idxM=($train|Measure-Object idx -Average).Average; $idxS=[math]::Sqrt((($train|ForEach-Object{[math]::Pow($_.idx-$idxM,2)})|Measure-Object -Average).Average)
$hrT=@($train|Where-Object{$_.hr -gt 0}); $hrM=($hrT|Measure-Object hr -Average).Average; $hrS=[math]::Sqrt((($hrT|ForEach-Object{[math]::Pow($_.hr-$hrM,2)})|Measure-Object -Average).Average)
function Feat($r){
  $r2=[double]($r.rb -eq 2);$r3=[double]($r.rb -eq 3);$r4=[double]($r.rb -eq 4)
  $p1=[double]($r.ps -eq 1);$p2=[double]($r.ps -eq 2);$p3=[double]($r.ps -eq 3);$p4=[double]($r.ps -eq 4)
  $idxZ=($r.idx-$idxM)/$idxS
  $has=[double]($r.hr -gt 0); $hrZ= if($r.hr -gt 0){($r.hr-$hrM)/$hrS}else{0.0}
  $c1=[double]($r.cb -eq 1);$c2=[double]($r.cb -eq 2);$c3=[double]($r.cb -eq 3)
  return @(1.0,$r2,$r3,$r4,$p1,$p2,$p3,$p4,$idxZ,$has,$hrZ,$c1,$c2,$c3)
}
$D=14
$Xtr=New-Object 'double[][]' $train.Count; $ytr=New-Object 'double[]' $train.Count
for($i=0;$i -lt $train.Count;$i++){ $Xtr[$i]=Feat $train[$i]; $ytr[$i]=$train[$i].fuku }
function Sig($z){ if($z -ge 0){ $e=[math]::Exp(-$z); return 1.0/(1.0+$e) } else { $e=[math]::Exp($z); return $e/(1.0+$e) } }
function Solve($A,$b,$d){ # Gaussian elimination, returns x
  for($c=0;$c -lt $d;$c++){ $piv=$c; for($rr=$c+1;$rr -lt $d;$rr++){ if([math]::Abs($A[$rr][$c]) -gt [math]::Abs($A[$piv][$c])){$piv=$rr} }
    $tmp=$A[$c];$A[$c]=$A[$piv];$A[$piv]=$tmp; $tb=$b[$c];$b[$c]=$b[$piv];$b[$piv]=$tb
    $dia=$A[$c][$c]; if([math]::Abs($dia) -lt 1e-12){$dia=1e-12}
    for($rr=0;$rr -lt $d;$rr++){ if($rr -eq $c){continue}; $f=$A[$rr][$c]/$dia; if($f -eq 0){continue}; for($cc=$c;$cc -lt $d;$cc++){ $A[$rr][$cc]-=$f*$A[$c][$cc] }; $b[$rr]-=$f*$b[$c] } }
  $x=New-Object 'double[]' $d; for($c=0;$c -lt $d;$c++){ $x[$c]=$b[$c]/$A[$c][$c] }; return $x
}
$w=New-Object 'double[]' $D
$lambda=1.0
for($it=0;$it -lt 12;$it++){
  $H=New-Object 'double[][]' $D; for($a=0;$a -lt $D;$a++){ $H[$a]=New-Object 'double[]' $D }
  $g=New-Object 'double[]' $D
  for($i=0;$i -lt $Xtr.Count;$i++){ $x=$Xtr[$i]; $z=0.0; for($a=0;$a -lt $D;$a++){$z+=$w[$a]*$x[$a]}; $p=Sig $z; $wt=$p*(1-$p); if($wt -lt 1e-9){$wt=1e-9}
    $resid=$ytr[$i]-$p
    for($a=0;$a -lt $D;$a++){ $g[$a]+=$resid*$x[$a]; $xa=$x[$a]; if($xa -eq 0){continue}; $row=$H[$a]; for($b2=0;$b2 -lt $D;$b2++){ $row[$b2]+=$wt*$xa*$x[$b2] } } }
  for($a=0;$a -lt $D;$a++){ $H[$a][$a]+=$lambda; $g[$a]-=$lambda*$w[$a] }
  $step=Solve $H $g $D
  $mx=0.0; for($a=0;$a -lt $D;$a++){ $w[$a]+=$step[$a]; if([math]::Abs($step[$a]) -gt $mx){$mx=[math]::Abs($step[$a])} }
  if($mx -lt 1e-6){ break }
}
$prL=New-Object 'double[]' $test.Count
for($i=0;$i -lt $test.Count;$i++){ $x=Feat $test[$i]; $z=0.0; for($a=0;$a -lt $D;$a++){$z+=$w[$a]*$x[$a]}; $prL[$i]=Sig $z }
$mtL=Metrics $prL $ys
Write-Host "`n=== OOS: ロジスティック回帰(IRLS, 順位+脚質+指数+h2h+前走着順) ==="
Write-Host ("LogReg                      {0,9:F5} {1,9:F4} {2,8:F4}" -f $mtL.Brier,$mtL.LogLoss,$mtL.AUC)

# 較正 (LogReg)
Write-Host "`n=== 較正表 LogReg (検証25-26) ==="
Write-Host ("{0,-12} {1,8} {2,9} {3,9} {4,8}" -f '予測帯','頭数','予測平均','実測','差')
$edges=0.0,0.3,0.4,0.5,0.55,0.6,0.65,0.7,0.75,0.8,0.85,1.01
$Ntot=$test.Count;$ece=0.0
for($bi=0;$bi -lt $edges.Count-1;$bi++){ $lo=$edges[$bi];$hi=$edges[$bi+1]; $sel=@(); $ps2=0.0;$fk=0.0;$nn=0
  for($i=0;$i -lt $prL.Count;$i++){ if($prL[$i] -ge $lo -and $prL[$i] -lt $hi){ $nn++;$ps2+=$prL[$i];$fk+=$ys[$i] } }
  if($nn -lt 50){continue}; $pm=$ps2/$nn;$ob=$fk/$nn;$ece+=($nn/[double]$Ntot)*[math]::Abs($pm-$ob)
  Write-Host ("{0,-12} {1,8} {2,9:P1} {3,9:P1} {4,8:P1}" -f ("{0:P0}-{1:P0}" -f $lo,$hi),$nn,$pm,$ob,($pm-$ob)) }
Write-Host ("ECE: {0:P2}" -f $ece)

# 係数
Write-Host "`n=== LogReg係数(標準化) ==="
$names=@('bias','rank2-3','rank4-6','rank7+','前走逃','前走先','前走差','前走追','指数Z','h2h有','h2h順位Z','前走1-3','前走4-6','前走7+')
for($a=0;$a -lt $D;$a++){ Write-Host ("  {0,-10} {1,8:F3}" -f $names[$a],$w[$a]) }
Write-Host "※h2h順位Zは順位降順(小=強)なので負係数=h2h上位ほど複勝↑が期待。"
