<#
  JRAベイズ複勝較正の本番焼き込み(地方bayes-finalizeの実証済みソルバを流用)。
  全データ22-26でLogReg(IRLS)を学習し係数JSON出力。出力=モデルA(順位band+指数Z+h2h)。
  JRAは脚質≈0で無寄与のため本番はA採用([[jra-bayes-fukusho-calibration]])。Bは脚質を足した確認用。
  → C:\jra\fukushima-analysis\jra-bayes-coef.json を jra-card.ps1 が読み各馬の複勝確率P→軸確度ラベル化。
#>
$OutputEncoding=[Console]::OutputEncoding=[System.Text.Encoding]::UTF8
$rows=Import-Csv 'C:\jra\fukushima-analysis\jra_bayes_feat.csv'
foreach($r in $rows){ $r.yr=[int]$r.yr;$r.rb=[int]$r.rb;$r.ps=[int]$r.ps;$r.idx=[double]$r.idx;$r.cb=[int]$r.cb;$r.hr=[int]$r.hr;$r.fuku=[int]$r.fuku }
$train=@($rows|Where-Object{$_.yr -le 2024}); $test=@($rows|Where-Object{$_.yr -ge 2025})

function Sig($z){ if($z -ge 0){ $e=[math]::Exp(-$z); return 1.0/(1.0+$e) } else { $e=[math]::Exp($z); return $e/(1.0+$e) } }
function Solve($A,$b,$d){ for($c=0;$c -lt $d;$c++){ $piv=$c; for($rr=$c+1;$rr -lt $d;$rr++){ if([math]::Abs($A[$rr][$c]) -gt [math]::Abs($A[$piv][$c])){$piv=$rr} }
    $t=$A[$c];$A[$c]=$A[$piv];$A[$piv]=$t; $tb=$b[$c];$b[$c]=$b[$piv];$b[$piv]=$tb; $dia=$A[$c][$c]; if([math]::Abs($dia) -lt 1e-12){$dia=1e-12}
    for($rr=0;$rr -lt $d;$rr++){ if($rr -eq $c){continue}; $f=$A[$rr][$c]/$dia; if($f -eq 0){continue}; for($cc=$c;$cc -lt $d;$cc++){ $A[$rr][$cc]-=$f*$A[$c][$cc] }; $b[$rr]-=$f*$b[$c] } }
  $x=[double[]]::new($d); for($c=0;$c -lt $d;$c++){ $x[$c]=$b[$c]/$A[$c][$c] }; return $x }
function FitStd($data){ $im=($data|Measure-Object idx -Average).Average; $is=[math]::Sqrt((($data|ForEach-Object{[math]::Pow($_.idx-$im,2)})|Measure-Object -Average).Average)
  $ht=@($data|Where-Object{$_.hr -gt 0}); $hm=($ht|Measure-Object hr -Average).Average; $hs=[math]::Sqrt((($ht|ForEach-Object{[math]::Pow($_.hr-$hm,2)})|Measure-Object -Average).Average)
  return @{idxM=$im;idxS=$is;hrM=$hm;hrS=$hs} }
function FeatOf($r,$std,$usePs){
  $hz= if($r.hr -gt 0){($r.hr-$std.hrM)/$std.hrS}else{0.0}
  $base=@(1.0,[double]($r.rb -eq 2),[double]($r.rb -eq 3),[double]($r.rb -eq 4),(($r.idx-$std.idxM)/$std.idxS),[double]($r.hr -gt 0),[double]$hz)
  if($usePs){ $base+=@([double]($r.ps -eq 1),[double]($r.ps -eq 2),[double]($r.ps -eq 3),[double]($r.ps -eq 4)) }
  return ,([double[]]$base)
}
function TrainIRLS($data,$std,$usePs,$D){
  $N=$data.Count; $xs=[object[]]::new($N); $y=[double[]]::new($N)
  for($i=0;$i -lt $N;$i++){ $xs[$i]=FeatOf $data[$i] $std $usePs; $y[$i]=$data[$i].fuku }
  $w=[double[]]::new($D); $lam=1.0
  for($it=0;$it -lt 20;$it++){ $H=[object[]]::new($D); for($a=0;$a -lt $D;$a++){$H[$a]=[double[]]::new($D)}; $g=[double[]]::new($D)
    for($i=0;$i -lt $N;$i++){ $x=$xs[$i];$z=0.0; for($a=0;$a -lt $D;$a++){$z+=$w[$a]*$x[$a]}; $p=Sig $z; $wt=$p*(1-$p); if($wt -lt 1e-9){$wt=1e-9}; $res=$y[$i]-$p
      for($a=0;$a -lt $D;$a++){ $g[$a]+=$res*$x[$a]; $xa=$x[$a]; if($xa -eq 0){continue}; $row=$H[$a]; for($b=0;$b -lt $D;$b++){$row[$b]+=$wt*$xa*$x[$b]} } }
    for($a=0;$a -lt $D;$a++){ $H[$a][$a]+=$lam; $g[$a]-=$lam*$w[$a] }
    $st=Solve $H $g $D; $mx=0.0; for($a=0;$a -lt $D;$a++){ $w[$a]+=$st[$a]; if([math]::Abs($st[$a]) -gt $mx){$mx=[math]::Abs($st[$a])} }
    if($mx -lt 1e-7){break} }
  return $w
}
function Eval($data,$std,$w,$usePs,$D){
  $n=$data.Count; $br=0.0;$ll=0.0; $pr=[double[]]::new($n); $ys=[double[]]::new($n)
  for($i=0;$i -lt $n;$i++){ $x=FeatOf $data[$i] $std $usePs; $z=0.0; for($a=0;$a -lt $D;$a++){$z+=$w[$a]*$x[$a]}; $p=Sig $z; $pr[$i]=$p; $ys[$i]=$data[$i].fuku
    $pc=[math]::Min([math]::Max($p,1e-6),1-1e-6); $br+=[math]::Pow($ys[$i]-$p,2); $ll+=-($ys[$i]*[math]::Log($pc)+(1-$ys[$i])*[math]::Log(1-$pc)) }
  $ix=0..($n-1)|Sort-Object {$pr[$_]}; $cn=0.0;$auc=0.0;$tp=0.0;$tn=0.0
  foreach($i in $ix){ if($ys[$i] -eq 1){$tp++}else{$tn++} }
  foreach($i in $ix){ if($ys[$i] -eq 1){$auc+=$cn+0.5}else{$cn++} }
  $auc= if($tp*$tn){$auc/($tp*$tn)}else{[double]::NaN}
  return [pscustomobject]@{Brier=$br/$n;AUC=$auc}
}

$stdTr=FitStd $train
Write-Host "=== OOS(学習22-24→検証25-26) ==="
foreach($v in @(@{n='A 順位+指数+h2h';ps=$false;D=7},@{n='B +前走脚質';ps=$true;D=11})){
  $w=TrainIRLS $train $stdTr $v.ps $v.D; $e=Eval $test $stdTr $w $v.ps $v.D
  Write-Host ("  {0,-18} Brier={1:F5} AUC={2:F4}" -f $v.n,$e.Brier,$e.AUC) }

# 本番=モデルA を全データ学習→JSON
$stdAll=FitStd $rows
$names=@('bias','rank2-3','rank4-6','rank7+','idxZ','h2hHas','h2hRankZ')
$w=TrainIRLS $rows $stdAll $false 7
$obj=[ordered]@{ model='A'; note='JRA複勝較正 LogReg 全データ22-26。P=sigmoid(Σ w*feat)。脚質無寄与で除外。rb:1=コ1位/2=コ2-3/3=コ4-6/4=コ7+。';
  idxM=[math]::Round($stdAll.idxM,4); idxS=[math]::Round($stdAll.idxS,4); hrM=[math]::Round($stdAll.hrM,4); hrS=[math]::Round($stdAll.hrS,4);
  names=$names; weights=@($w | ForEach-Object{[math]::Round($_,5)}) }
$json=$obj | ConvertTo-Json -Depth 4
$json | Set-Content -Path 'C:\jra\fukushima-analysis\jra-bayes-coef.json' -Encoding UTF8   # 作業記録用
$json | Set-Content -Path 'C:\jra\tools\jra-bayes-model-A.json' -Encoding UTF8          # 本番(jra-card.ps1が読む)
Write-Host "`n=== 最終係数(全データ・モデルA) → jra-bayes-coef.json ==="
for($a=0;$a -lt 7;$a++){ Write-Host ("  {0,-10} {1,8:F3}" -f $names[$a],$w[$a]) }

function Pof($rb,$idx,$hr){ $hz= if($hr -gt 0){($hr-$stdAll.hrM)/$stdAll.hrS}else{0.0}; $f=@(1.0,[double]($rb -eq 2),[double]($rb -eq 3),[double]($rb -eq 4),(($idx-$stdAll.idxM)/$stdAll.idxS),[double]($hr -gt 0),$hz); $z=0.0; for($a=0;$a -lt 7;$a++){$z+=$w[$a]*$f[$a]}; Sig $z }
Write-Host "`n--- 代表ケースの複勝確率P(較正) ---"
Write-Host ("コ1位/指数88/h2h1位: {0:P1}" -f (Pof 1 88 1))
Write-Host ("コ1位/指数80/h2h3位: {0:P1}" -f (Pof 1 80 3))
Write-Host ("コ1位/指数72/h2h無 : {0:P1}" -f (Pof 1 72 0))
Write-Host ("コ4位/指数76/h2h2位: {0:P1}" -f (Pof 3 76 2))
Write-Host ("コ8位/指数60/h2h無 : {0:P1}" -f (Pof 4 60 0))
