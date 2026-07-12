# 構成×番組分類の組み合わせ検証(事前固定仮説H1-H5)
# 対象: 同条件60%×中団勢(確定定義)。G0=定義全体(再現率/Δ)・G1=時計1位・G17=時計1位∧進出維持
# 番組属性: age(2歳/3歳/3歳以上/4歳以上)・kin(定量/別定/ハンデ)・shubetsu(一般/特別/重賞)・prize分位(場×年内Q1-Q4)
# 構成: 先行型頭数=同条件組で3走平均3角率<0.30の頭数(絶対band・0-1/2-3/4+)
param([string]$Base='C:\keiba\analysis\samecond_mid_base5.csv',[string]$Attr='C:\keiba\analysis\samecond_race_attr.csv',[double]$SameTh=0.60)
[Console]::OutputEncoding=[System.Text.Encoding]::UTF8
$ErrorActionPreference='Stop'
$rows=Import-Csv $Base -Encoding UTF8
Write-Host ("base {0}行" -f $rows.Count)
$attrRows=Import-Csv $Attr -Encoding UTF8
$AT=@{}
foreach($a in $attrRows){ $AT["$($a.開催日)|$($a.開催場所)|$($a.レース番号)"]=$a }
Write-Host ("attr {0}行" -f $attrRows.Count)
# 賞金分位(場×年内Q1-Q4)
$przGrp=@{}
foreach($a in $attrRows){
  if($a.prize -eq ''){ continue }
  $k="$($a.開催場所)|$($a.開催日.Substring(0,4))"
  if(-not $przGrp.ContainsKey($k)){ $przGrp[$k]=New-Object System.Collections.Generic.List[double] }
  $przGrp[$k].Add([double]$a.prize)
}
$przQ=@{}
foreach($k in $przGrp.Keys){
  $s=@($przGrp[$k].ToArray() | Sort-Object)
  $przQ[$k]=@($s[[int]($s.Count*0.25)],$s[[int]($s.Count*0.5)],$s[[int]($s.Count*0.75)])
}
function PrizeBand([string]$venue,[string]$y,[string]$pz){
  if($pz -eq ''){ return '' }
  $k="$venue|$y"; if(-not $przQ.ContainsKey($k)){ return '' }
  $q=$przQ[$k]; $v=[double]$pz
  if($v -le $q[0]){'賞Q1(下級)'}elseif($v -le $q[1]){'賞Q2'}elseif($v -le $q[2]){'賞Q3'}else{'賞Q4(上級)'}
}
$BLT=@{}
function BandOf([int]$cr){ if($cr -eq 1){'コ1'}elseif($cr -le 4){'コ2-4'}elseif($cr -le 6){'コ5-6'}else{'コ7+'} }
foreach($r in $rows){
  $cr=$(if($r.指数順位 -eq ''){99}else{[int]$r.指数順位})
  $key="$($r.開催場所)$($r.距離)|$(BandOf $cr)"
  if(-not $BLT.ContainsKey($key)){ $BLT[$key]=@{n=0;p=0} }
  $BLT[$key].n++; if([int]$r.着順 -le 3){ $BLT[$key].p++ }
}
function Num($x){ if($x -eq '' -or $null -eq $x){ $null } else { [double]$x } }

$G0=New-Object System.Collections.Generic.List[object]
foreach($grp in ($rows | Group-Object { "$($_.開催日)|$($_.開催場所)|$($_.レース番号)" })){
  $hs=@($grp.Group)
  $tou=[int]$hs[0].頭数
  $sameH=@($hs | Where-Object { $_.same -eq '1' })
  if(($sameH.Count/[double]$tou) -lt $SameTh){ continue }
  $wv=@($hs | Where-Object { $_.t3 -ne '' } | ForEach-Object { [pscustomobject]@{u=[int]$_.馬番; v=[double]$_.t3} } | Sort-Object v,u)
  $m=$wv.Count; if($m -lt 5){ continue }
  $midT=@{}
  for($i=0;$i -lt $m;$i++){ $rr=($i+0.5)/$m; $midT[$wv[$i].u]=$(if($rr -ge (1.0/3) -and $rr -lt (2.0/3)){1}else{0}) }
  $withT=@($sameH | Where-Object { $_.前走時計 -ne '' -and [double]$_.前走時計 -gt 0 } | Sort-Object {[double]$_.前走時計},{[int]$_.馬番})
  $tRank=@{}; for($i=0;$i -lt $withT.Count;$i++){ $tRank[[int]$withT[$i].馬番]=$i+1 }
  $wm=@($sameH | Where-Object { $_.a3_3 -ne '' } | ForEach-Object { [pscustomobject]@{h=$_; u=[int]$_.馬番; v=[double]$_.a3_3} } | Sort-Object v,u)
  $nm=$wm.Count; if($nm -lt 5){ continue }
  # 構成: 絶対先行型頭数
  $nSenko=@($wm | Where-Object { $_.v -lt 0.30 }).Count
  $senB=$(if($nSenko -le 1){'先行0-1'}elseif($nSenko -le 3){'先行2-3'}else{'先行4+'})
  # 番組属性
  $ak=$AT[$grp.Name]
  $age=$(if($ak){[string]$ak.age}else{''})
  $kin=$(if($ak){[string]$ak.kin}else{''})
  $sh=$(if($ak){[string]$ak.shubetsu}else{''})
  $pzB=$(if($ak){ PrizeBand $ak.開催場所 $ak.開催日.Substring(0,4) $ak.prize }else{''})
  for($i=0;$i -lt $nm;$i++){
    $rr=($i+0.5)/$nm
    if(-not ($rr -ge (1.0/3) -and $rr -lt (2.0/3))){ continue }
    $h=$wm[$i].h; $u=$wm[$i].u
    $r1=Num $h.p1r; $r2=Num $h.p2r; $r3=Num $h.p3r
    if($null -eq $r1 -or $null -eq $r2 -or $null -eq $r3){ continue }
    if(-not ($r1 -ge 0.30 -and $r1 -le 0.70 -and $r2 -ge 0.30 -and $r2 -le 0.70 -and $r3 -ge 0.30 -and $r3 -le 0.70)){ continue }
    $wkr=$(if($tou -gt 1){ ([double]$u-1.0)/($tou-1.0) }else{ 0.5 })
    if($wkr -ge 0.80){ continue }
    $isT1=$(if($tRank.ContainsKey($u) -and $tRank[$u] -eq 1){1}else{0})
    $g7=0
    $p4=Num $h.p4r; $a3=Num $h.a3_3; $a4=Num $h.a4_3
    $pf=$(if($h.前走着順 -eq ''){$null}else{[double]$h.前走着順})
    $ptou=$(if($h.前走頭数 -eq ''){$null}else{[double]$h.前走頭数})
    if($null -ne $p4 -and $null -ne $a4 -and $null -ne $pf -and $null -ne $ptou -and $ptou -gt 1){
      $fr1=($pf-1.0)/($ptou-1.0)
      if(($a3-$a4) -gt 0 -and ($r3-$p4) -gt 0 -and $fr1 -lt $p4){ $g7=1 }
    }
    $cr=$(if($h.指数順位 -eq ''){99}else{[int]$h.指数順位})
    $G0.Add([pscustomobject]@{
      y=$h.開催日.Substring(0,4); cell="$($h.開催場所)$($h.距離)"
      fin=[int]$h.着順; crB=(BandOf $cr)
      mid=$(if($midT.ContainsKey($u)){$midT[$u]}else{$null})
      t1=$isT1; g7=$g7
      age=$age; kin=$kin; sh=$sh; pzB=$pzB; senB=$senB
      tan=[int]$h.tanPay; fuku=[int]$h.fukuPay
    })
  }
}
$arr=$G0.ToArray()
$g1=@($arr | Where-Object { $_.t1 -eq 1 })
$g17=@($g1 | Where-Object { $_.g7 -eq 1 })
Write-Host ("中団勢 {0} / G1 {1} / G1∧G7 {2}" -f $arr.Count,$g1.Count,$g17.Count)

function Sim([object[]]$sel,[string]$label){
  $s=@($sel); $n=$s.Count; if($n -eq 0){ return ('  {0,-34} n=0' -f $label) }
  $w=0;$p=0;$tan=0.0;$fuku=0.0;$blSum=0.0;$mN=0;$mH=0
  foreach($o in $s){
    if($o.fin -eq 1){ $w++; $tan+=$o.tan }; if($o.fin -le 3){ $p++; $fuku+=$o.fuku }
    $k="$($o.cell)|$($o.crB)"; if($BLT.ContainsKey($k)){ $blSum+=$BLT[$k].p/$BLT[$k].n }
    if($null -ne $o.mid){ $mN++; if($o.mid -eq 1){ $mH++ } }
  }
  $dl=100.0*($p/$n - $blSum/$n)
  $rep=$(if($mN -gt 0){ '{0,5:P1}' -f ($mH/[double]$mN) }else{ '  -- ' })
  '  {0,-34} n={1,5} 再現{2} 勝率{3,4:P0} 複率{4,4:P0} Δ複={5:+0.0;-0.0}pt 単回{6,5:P0} 複回{7,5:P0}' -f $label,$n,$rep,($w/$n),($p/$n),$dl,($tan/$n/100),($fuku/$n/100)
}

"`n===== [H1] 年齢区分(G0中団勢/G1時計1位) ====="
foreach($a in @('2歳','3歳','3歳以上','4歳以上')){
  Sim @($arr | Where-Object { $_.age -eq $a }) ("G0×"+$a)
}
foreach($a in @('2歳','3歳','3歳以上','4歳以上')){
  Sim @($g1 | Where-Object { $_.age -eq $a }) ("G1×"+$a)
}

"`n===== [H2] クラス=賞金分位(場×年内) ====="
foreach($p in @('賞Q1(下級)','賞Q2','賞Q3','賞Q4(上級)')){
  Sim @($arr | Where-Object { $_.pzB -eq $p }) ("G0×"+$p)
}
foreach($p in @('賞Q1(下級)','賞Q2','賞Q3','賞Q4(上級)')){
  Sim @($g1 | Where-Object { $_.pzB -eq $p }) ("G1×"+$p)
}
"-- 競走種類 --"
foreach($s in @('一般','特別','重賞')){
  Sim @($g1 | Where-Object { $_.sh -eq $s }) ("G1×"+$s)
}

"`n===== [H3] 斤量方式 ====="
foreach($k in @('定量','別定','ハンデ')){
  Sim @($g1 | Where-Object { $_.kin -eq $k }) ("G1×"+$k)
}

"`n===== [H4] 構成=先行型頭数(3走平均3角率<0.30の絶対頭数) ====="
foreach($s in @('先行0-1','先行2-3','先行4+')){
  Sim @($arr | Where-Object { $_.senB -eq $s }) ("G0×"+$s)
}
foreach($s in @('先行0-1','先行2-3','先行4+')){
  Sim @($g1 | Where-Object { $_.senB -eq $s }) ("G1×"+$s)
}
foreach($s in @('先行0-1','先行2-3','先行4+')){
  Sim @($g17 | Where-Object { $_.senB -eq $s }) ("G1∧G7×"+$s)
}

"`n===== [H5] 交差: 年齢×構成 / クラス×構成 (G1・n≥60のみ表示) ====="
foreach($a in @('3歳','3歳以上','4歳以上')){
  foreach($s in @('先行0-1','先行2-3','先行4+')){
    $x=@($g1 | Where-Object { $_.age -eq $a -and $_.senB -eq $s })
    if($x.Count -ge 60){ Sim $x ("G1×"+$a+"×"+$s) }
  }
}
foreach($p in @('賞Q1(下級)','賞Q2','賞Q3','賞Q4(上級)')){
  foreach($s in @('先行0-1','先行2-3','先行4+')){
    $x=@($g1 | Where-Object { $_.pzB -eq $p -and $_.senB -eq $s })
    if($x.Count -ge 60){ Sim $x ("G1×"+$p+"×"+$s) }
  }
}
"`nDONE"

"`n===== [追加確認] 2歳戦の年別(G0/G1) ====="
$a2=@($arr | Where-Object { $_.age -eq '2歳' })
foreach($yy in @('2022','2023','2024','2025','2026')){ Sim @($a2 | Where-Object { $_.y -eq $yy }) ("G0×2歳 $yy") }
"-- セル別(n>=30) --"
foreach($cg in ($a2 | Group-Object cell | Where-Object { $_.Count -ge 30 } | Sort-Object Name)){ Sim $cg.Group ("  "+$cg.Name) }
"-- G1×2歳 年別 --"
$g12s=@($g1 | Where-Object { $_.age -eq '2歳' })
foreach($yy in @('2022','2023','2024','2025','2026')){ Sim @($g12s | Where-Object { $_.y -eq $yy }) ("G1×2歳 $yy") }
"DONE3"
