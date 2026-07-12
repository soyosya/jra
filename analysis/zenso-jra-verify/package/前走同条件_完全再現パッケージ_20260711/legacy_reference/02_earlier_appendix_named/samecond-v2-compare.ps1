# V2.0改良版設計書の検証: B0〜B7・P(構造分岐コア)・P-TB(タイブレーク派生)の比較(V2.0 §13.1)
# ADV/HOLD = V2.0 §5の符号再現ゲート:
#   有効走j: r3_j/r4_j/fr_j すべて存在。ADV_j=r3rel-r4rel(>0=前進)、HOLD_j=r4rel-frrel(≥0=維持)
#   k=3: ADV通過=正が2走+∧中央値>0 / HOLD通過=≥0が2走+∧中央値≥0。k=2: 2走とも。k<2: unknown(不通過扱い)
# M_raw=同条件組A3相対中位1/3(nm≥5)。M_base=M_raw∧S1∧枠<0.80(下げ組はS1が包含・能力下限は当方に無し)
# mid_rank=M_raw内のa3昇順。密度high=|M_raw|≥ceil(nm/3)+1(当方修正版=母数nm)
# 構造: 圧力high=同条件組a3<0.30が4頭+(プロキシ・G8と同一)。持続力=F_raw(a3<0.30)のHOLD比率(V2.0 §7.2)
# 経路: low×*→S / high×high→S / high×low→C / high×unknown→判定不能
param([string]$Base='C:\keiba\analysis\samecond_mid_base6.csv',[double]$SameTh=0.60)
[Console]::OutputEncoding=[System.Text.Encoding]::UTF8
$ErrorActionPreference='Stop'
$rows=Import-Csv $Base -Encoding UTF8
Write-Host ("ロード {0}行" -f $rows.Count)
function Num($x){ if($x -eq '' -or $null -eq $x){ $null } else { [double]$x } }
$BLT=@{}
function BandOf([int]$cr){ if($cr -eq 1){'コ1'}elseif($cr -le 4){'コ2-4'}elseif($cr -le 6){'コ5-6'}else{'コ7+'} }
foreach($r in $rows){
  $cr=$(if($r.指数順位 -eq ''){99}else{[int]$r.指数順位})
  $key="$($r.開催場所)$($r.距離)|$(BandOf $cr)"
  if(-not $BLT.ContainsKey($key)){ $BLT[$key]=@{n=0;p=0} }
  $BLT[$key].n++; if([int]$r.着順 -le 3){ $BLT[$key].p++ }
}

# ADV/HOLD判定(V2.0 §5.4)
function GatePass([object[]]$vals,[bool]$isAdv){
  $k=$vals.Count
  if($k -lt 2){ return 'unknown' }
  $ok=@($vals | Where-Object { if($isAdv){ $_ -gt 0 }else{ $_ -ge 0 } }).Count
  $sorted=@($vals | Sort-Object)
  $med=$(if($k -eq 3){ $sorted[1] }else{ ($sorted[0]+$sorted[1])/2.0 })
  if($k -eq 3){
    if($ok -ge 2 -and ($(if($isAdv){ $med -gt 0 }else{ $med -ge 0 }))){ 'pass' } else { 'fail' }
  } else {
    if($ok -eq 2){ 'pass' } else { 'fail' }
  }
}

$REC=New-Object System.Collections.Generic.List[object]   # 馬単位(B系)
$PRC=New-Object System.Collections.Generic.List[object]   # レース単位(P系)
$raceCnt=0
foreach($grp in ($rows | Group-Object { "$($_.開催日)|$($_.開催場所)|$($_.レース番号)" })){
  $hs=@($grp.Group)
  $tou=[int]$hs[0].頭数
  $sameH=@($hs | Where-Object { $_.same -eq '1' })
  if(($sameH.Count/[double]$tou) -lt $SameTh){ continue }
  $wm=@($sameH | Where-Object { $_.a3_3 -ne '' } | ForEach-Object { [pscustomobject]@{h=$_; u=[int]$_.馬番; v=[double]$_.a3_3} } | Sort-Object v,u)
  $nm=$wm.Count; if($nm -lt 5){ continue }
  $raceCnt++
  # 時計1位
  $withT=@($sameH | Where-Object { $_.前走時計 -ne '' -and [double]$_.前走時計 -gt 0 } | Sort-Object {[double]$_.前走時計},{[int]$_.馬番})
  $t1u=$(if($withT.Count -ge 1){ [int]$withT[0].馬番 }else{ -1 })
  # 各馬のADV/HOLD(有効走=3角/4角/着順率が揃う走)
  $gate=@{}
  foreach($e in $wm){
    $h=$e.h
    $advs=New-Object System.Collections.Generic.List[object]
    $holds=New-Object System.Collections.Generic.List[object]
    # rn=1
    $q3=Num $h.p3r; $q4=Num $h.p4r
    $pf=$(if($h.前走着順 -eq ''){$null}else{[double]$h.前走着順})
    $pt2=$(if($h.前走頭数 -eq ''){$null}else{[double]$h.前走頭数})
    $fr1=$(if($null -ne $pf -and $null -ne $pt2 -and $pt2 -gt 1){ ($pf-1.0)/($pt2-1.0) }else{ $null })
    if($null -ne $q3 -and $null -ne $q4 -and $null -ne $fr1){ $advs.Add($q3-$q4); $holds.Add($q4-$fr1) }
    # rn=2,3
    foreach($sfx in @('2','3')){
      $x3=Num $h.("r3_$sfx"); $x4=Num $h.("r4_$sfx"); $xf=Num $h.("fr_$sfx")
      if($null -ne $x3 -and $null -ne $x4 -and $null -ne $xf){ $advs.Add($x3-$x4); $holds.Add($x4-$xf) }
    }
    $gate[$e.u]=@{ adv=(GatePass $advs.ToArray() $true); hold=(GatePass $holds.ToArray() $false) }
  }
  # M_raw(中位1/3)・mid_rank・密度
  $mraw=New-Object System.Collections.Generic.List[object]
  for($i=0;$i -lt $nm;$i++){
    $rr=($i+0.5)/$nm
    if($rr -ge (1.0/3) -and $rr -lt (2.0/3)){ $mraw.Add($wm[$i]) }
  }
  $mrawA=@($mraw.ToArray() | Sort-Object v,u)
  if($mrawA.Count -eq 0){ continue }
  $midRank=@{}; for($i=0;$i -lt $mrawA.Count;$i++){ $midRank[$mrawA[$i].u]=$i+1 }
  $densHigh=($mrawA.Count -ge ([math]::Ceiling($nm/3.0)+1))
  # 構造判定
  $senkoAbs=@($wm | Where-Object { $_.v -lt 0.30 })
  $press=$(if($senkoAbs.Count -ge 4){'high'}else{'low'})
  $fTotal=$senkoAbs.Count
  $fKnown=0; $fUnk=0
  foreach($f in $senkoAbs){
    $g=$gate[$f.u]
    if($g.hold -eq 'unknown'){ $fUnk++ } elseif($g.hold -eq 'pass'){ $fKnown++ }
  }
  $fs='unknown'
  if($fTotal -eq 0){ $fs='none' }
  elseif($fKnown -gt ($fTotal/2.0)){ $fs='high' }
  elseif((($fKnown+$fUnk)/[double]$fTotal) -le 0.5){ $fs='low' }
  $route='UNKNOWN'
  if($press -eq 'low'){ $route='S' }
  elseif($press -eq 'high' -and $fs -eq 'high'){ $route='S' }
  elseif($press -eq 'high' -and $fs -eq 'low'){ $route='C' }
  # 馬単位レコード(M_raw全員)
  $mbaseSel=New-Object System.Collections.Generic.List[object]
  foreach($e in $mrawA){
    $h=$e.h; $u=$e.u
    $r1=Num $h.p1r; $r2=Num $h.p2r; $r3=Num $h.p3r
    $s1=($null -ne $r1 -and $null -ne $r2 -and $null -ne $r3 -and $r1 -ge 0.30 -and $r1 -le 0.70 -and $r2 -ge 0.30 -and $r2 -le 0.70 -and $r3 -ge 0.30 -and $r3 -le 0.70)
    $wkr=$(if($tou -gt 1){ ([double]$u-1.0)/($tou-1.0) }else{ 0.5 })
    $b1=($s1 -and $wkr -lt 0.80)
    $g=$gate[$u]
    $cr=$(if($h.指数順位 -eq ''){99}else{[int]$h.指数順位})
    $o=[pscustomobject]@{
      d=$h.開催日; y=$h.開催日.Substring(0,4); cell="$($h.開催場所)$($h.距離)"
      fin=[int]$h.着順; crB=(BandOf $cr)
      b1=$b1; mrk=$midRank[$u]; adv=$g.adv; hold=$g.hold
      t1=$(if($u -eq $t1u){1}else{0})
      route=$route; dens=$densHigh
      tan=[int]$h.tanPay; fuku=[int]$h.fukuPay
    }
    $REC.Add($o)
    if($b1){ $mbaseSel.Add($o) }
  }
  # P(コア)判定
  $mb=$mbaseSel.ToArray()
  $cand=@()
  if($route -eq 'S'){
    $cand=@($mb | Where-Object { $_.mrk -eq 1 -and $_.hold -eq 'pass' })
    if($densHigh){ $cand=@($cand | Where-Object { $_.adv -eq 'pass' }) }
  } elseif($route -eq 'C'){
    $cand=@($mb | Where-Object { $_.mrk -le 2 -and $_.adv -eq 'pass' -and $_.hold -eq 'pass' })
  }
  $sel=$null; $status='NO_BET'
  if($route -eq 'UNKNOWN'){ $status='STRUCT_UNK' }
  elseif($cand.Count -eq 1){ $sel=$cand[0]; $status='SELECT' }
  elseif($cand.Count -ge 2){ $status='MULTI' }
  # P-TB: 複数時 mid_rank最小(→hold/adv回数は同値情報無のためmid_rank→馬番)
  $selTb=$sel
  if($status -eq 'MULTI'){ $selTb=@($cand | Sort-Object mrk)[0] }
  $PRC.Add([pscustomobject]@{ y=$hs[0].開催日.Substring(0,4); d=$hs[0].開催日; route=$route; status=$status; sel=$sel; selTb=$selTb })
}
$arr=$REC.ToArray()
Write-Host ("対象レース {0} / M_raw {1}頭" -f $raceCnt,$arr.Count)

function Sim([object[]]$sel,[string]$label){
  $s=@($sel); $n=$s.Count; if($n -eq 0){ return ('  {0,-40} n=0' -f $label) }
  $w=0;$p=0;$tan=0.0;$fuku=0.0;$blSum=0.0
  foreach($o in $s){
    if($o.fin -eq 1){ $w++; $tan+=$o.tan }; if($o.fin -le 3){ $p++; $fuku+=$o.fuku }
    $k="$($o.cell)|$($o.crB)"; if($BLT.ContainsKey($k)){ $blSum+=$BLT[$k].p/$BLT[$k].n }
  }
  $dl=100.0*($p/$n - $blSum/$n)
  '  {0,-40} n={1,5} 勝率{2,4:P0} 複率{3,4:P0} Δ複={4:+0.0;-0.0}pt 単回{5,5:P0} 複回{6,5:P0}' -f $label,$n,($w/$n),($p/$n),$dl,($tan/$n/100),($fuku/$n/100)
}

"`n===== V2.0 §13.1 比較モデル(馬単位・全て同条件60%×A3相対中位1/3=M_raw起点) ====="
Sim $arr 'B0: M_raw(A3-REL中団のみ)'
$b1=@($arr | Where-Object { $_.b1 })
Sim $b1 'B1: +S1+枠<0.80(確定定義)'
Sim @($b1 | Where-Object { $_.mrk -eq 1 }) 'B2: B1+mid_rank=1(中団先頭)'
Sim @($b1 | Where-Object { $_.adv -eq 'pass' }) 'B3: B1+ADV通過(符号再現版)'
Sim @($b1 | Where-Object { $_.hold -eq 'pass' }) 'B4: B1+HOLD通過'
$b5=@($b1 | Where-Object { $_.adv -eq 'pass' -and $_.hold -eq 'pass' })
Sim $b5 'B5: B1+ADV∧HOLD'
$b5x=@($b5 | Where-Object { $_.t1 -eq 1 })
Sim $b5x 'B5x: B5+同条件組時計1位(当方推奨)'
Sim @($b1 | Where-Object { $_.mrk -eq 1 -and $_.hold -eq 'pass' }) 'B6: 全R一律 経路S条件'
Sim @($b1 | Where-Object { $_.mrk -le 2 -and $_.adv -eq 'pass' -and $_.hold -eq 'pass' }) 'B7: 全R一律 経路C条件'
"-- 対照(ゲート不通過側) --"
Sim @($b1 | Where-Object { $_.adv -eq 'fail' }) '  ADV fail'
Sim @($b1 | Where-Object { $_.adv -eq 'unknown' }) '  ADV unknown(有効走<2)'
Sim @($b1 | Where-Object { $_.hold -eq 'fail' }) '  HOLD fail'

"`n===== P: 構造分岐コア(レース単位) ====="
$prc=$PRC.ToArray()
$routeCnt=$prc | Group-Object route | Sort-Object Name
foreach($g in $routeCnt){ '  経路{0}: {1}レース({2:P0})' -f $g.Name,$g.Count,($g.Count/[double]$prc.Count) }
$stCnt=$prc | Group-Object status
foreach($g in $stCnt){ '  status {0}: {1}' -f $g.Name,$g.Count }
$pSel=@($prc | Where-Object { $_.status -eq 'SELECT' } | ForEach-Object { $_.sel })
Sim $pSel 'P: コア選出馬(全経路)'
Sim @($prc | Where-Object { $_.status -eq 'SELECT' -and $_.route -eq 'S' } | ForEach-Object { $_.sel }) '  └ 経路S選出'
Sim @($prc | Where-Object { $_.status -eq 'SELECT' -and $_.route -eq 'C' } | ForEach-Object { $_.sel }) '  └ 経路C選出'
$pTb=@($prc | Where-Object { $null -ne $_.selTb } | ForEach-Object { $_.selTb })
Sim $pTb 'P-TB: タイブレーク込み選出'

"`n===== H3検証: ADVの増分は構造で変わるか(B1母集団・ADV pass vs fail のΔ複差) ====="
foreach($rt in @('S','C','UNKNOWN')){
  $g=@($b1 | Where-Object { $_.route -eq $rt })
  Sim @($g | Where-Object { $_.adv -eq 'pass' }) ("route$rt × ADV pass")
  Sim @($g | Where-Object { $_.adv -eq 'fail' }) ("route$rt × ADV fail")
}

"`n===== 年別頑健性(B5・B5x) ====="
foreach($yy in @('2022','2023','2024','2025','2026')){ Sim @($b5 | Where-Object { $_.y -eq $yy }) ("B5 $yy") }
Sim @($b5 | Where-Object { $_.d -ge '2026-05-10' }) 'B5 直近2ヶ月窓'
foreach($yy in @('2022','2023','2024','2025','2026')){ Sim @($b5x | Where-Object { $_.y -eq $yy }) ("B5x $yy") }
Sim @($b5x | Where-Object { $_.d -ge '2026-05-10' }) 'B5x 直近2ヶ月窓'
"`nDONE"

"`n===== [追加] 頑健性: B6 / Pコア / routeC×ADVpass の年別+2M窓 ====="
$b6=@($b1 | Where-Object { $_.mrk -eq 1 -and $_.hold -eq 'pass' })
foreach($yy in @('2022','2023','2024','2025','2026')){ Sim @($b6 | Where-Object { $_.y -eq $yy }) ("B6 $yy") }
Sim @($b6 | Where-Object { $_.d -ge '2026-05-10' }) 'B6 直近2ヶ月窓'
"--"
foreach($yy in @('2022','2023','2024','2025','2026')){ Sim @($pSel | Where-Object { $_.y -eq $yy }) ("P $yy") }
Sim @($pSel | Where-Object { $_.d -ge '2026-05-10' }) 'P 直近2ヶ月窓'
"--"
$rcAdv=@($b1 | Where-Object { $_.route -eq 'C' -and $_.adv -eq 'pass' })
foreach($yy in @('2022','2023','2024','2025','2026')){ Sim @($rcAdv | Where-Object { $_.y -eq $yy }) ("routeC×ADVpass $yy") }
"-- B6のセル別(n>=100) --"
foreach($cg in ($b6 | Group-Object cell | Where-Object { $_.Count -ge 100 } | Sort-Object Name)){ Sim $cg.Group ("  "+$cg.Name) }
"-- 高配当依存チェック: B6/Pの単勝払戻分布 --"
$b6w=@($b6 | Where-Object { $_.fin -eq 1 })
$pw=@($pSel | Where-Object { $_.fin -eq 1 })
'  B6的中{0}件: 払戻中央値{1}円 / 最大{2}円 / 2000円+の件数{3}(payout比{4:P0})' -f $b6w.Count,(@($b6w | Sort-Object tan)[[int]($b6w.Count/2)].tan),(($b6w | Measure-Object tan -Maximum).Maximum),@($b6w | Where-Object { $_.tan -ge 2000 }).Count,((($b6w | Where-Object { $_.tan -ge 2000 } | Measure-Object tan -Sum).Sum)/(($b6w | Measure-Object tan -Sum).Sum))
'  P 的中{0}件: 払戻中央値{1}円 / 最大{2}円 / 2000円+の件数{3}(payout比{4:P0})' -f $pw.Count,(@($pw | Sort-Object tan)[[int]($pw.Count/2)].tan),(($pw | Measure-Object tan -Maximum).Maximum),@($pw | Where-Object { $_.tan -ge 2000 }).Count,((($pw | Where-Object { $_.tan -ge 2000 } | Measure-Object tan -Sum).Sum)/(($pw | Measure-Object tan -Sum).Sum))
"DONE4"

"`n===== [追加2] B6 直近2ヶ月窓の中身(的中明細・依存度) ====="
$b62m=@($b6 | Where-Object { $_.d -ge '2026-05-10' })
'  n={0} 的中(単勝)={1}件 複勝的中={2}件' -f $b62m.Count,@($b62m | Where-Object { $_.fin -eq 1 }).Count,@($b62m | Where-Object { $_.fin -le 3 }).Count
"-- 単勝的中の明細 --"
foreach($o in @($b62m | Where-Object { $_.fin -eq 1 } | Sort-Object d)){ '  {0} {1} 単{2}円 複{3}円' -f $o.d,$o.cell,$o.tan,$o.fuku }
$tSum=(@($b62m | Where-Object { $_.fin -eq 1 }) | Measure-Object tan -Sum).Sum
$tMax=(@($b62m | Where-Object { $_.fin -eq 1 }) | Measure-Object tan -Maximum).Maximum
if($tSum -gt 0){ '  単勝: 総払戻{0}円/最大1件{1}円(依存度{2:P0}) 最大1件を除く単回={3:P0}' -f $tSum,$tMax,($tMax/$tSum),(($tSum-$tMax)/100.0/$b62m.Count) }
"-- 月別(5/6/7月) --"
Sim @($b62m | Where-Object { $_.d -lt '2026-06-01' }) '  5/10-5/31'
Sim @($b62m | Where-Object { $_.d -ge '2026-06-01' -and $_.d -lt '2026-07-01' }) '  6月'
Sim @($b62m | Where-Object { $_.d -ge '2026-07-01' }) '  7月'
"-- 参考: 3-4ヶ月前窓(2026-03-10〜05-09)=一つ前の窓 --"
Sim @($b6 | Where-Object { $_.d -ge '2026-03-10' -and $_.d -lt '2026-05-10' }) '  前窓(3/10-5/9)'
"DONE5"
