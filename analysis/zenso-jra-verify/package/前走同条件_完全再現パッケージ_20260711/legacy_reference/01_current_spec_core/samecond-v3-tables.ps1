# V3提案書が依頼する検証表の作成
# [1] mid_rank×HOLDの4群表(留保1: 交互作用の直接確認)
# [2] C0-C5増分ラダー(§6: 時計1位後のADV/HOLD追加増分・頑健版vs簡易版)
# [3] ADV/HOLD判定可能率(§7: セル別/年度別/時計順位別=欠損選択バイアス)
# [4] 主要値の95%信頼区間(レースクラスタ無視の二項近似・注記付)
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
function GatePass([object[]]$vals,[bool]$isAdv){
  $k=$vals.Count
  if($k -lt 2){ return 'unknown' }
  $ok=@($vals | Where-Object { if($isAdv){ $_ -gt 0 }else{ $_ -ge 0 } }).Count
  $sorted=@($vals | Sort-Object)
  $med=$(if($k -eq 3){ $sorted[1] }else{ ($sorted[0]+$sorted[1])/2.0 })
  if($k -eq 3){ if($ok -ge 2 -and ($(if($isAdv){ $med -gt 0 }else{ $med -ge 0 }))){ 'pass' } else { 'fail' } }
  else { if($ok -eq 2){ 'pass' } else { 'fail' } }
}
$REC=New-Object System.Collections.Generic.List[object]
foreach($grp in ($rows | Group-Object { "$($_.開催日)|$($_.開催場所)|$($_.レース番号)" })){
  $hs=@($grp.Group)
  $tou=[int]$hs[0].頭数
  $sameH=@($hs | Where-Object { $_.same -eq '1' })
  if(($sameH.Count/[double]$tou) -lt $SameTh){ continue }
  $wm=@($sameH | Where-Object { $_.a3_3 -ne '' } | ForEach-Object { [pscustomobject]@{h=$_; u=[int]$_.馬番; v=[double]$_.a3_3} } | Sort-Object v,u)
  $nm=$wm.Count; if($nm -lt 5){ continue }
  $withT=@($sameH | Where-Object { $_.前走時計 -ne '' -and [double]$_.前走時計 -gt 0 } | Sort-Object {[double]$_.前走時計},{[int]$_.馬番})
  $t1u=$(if($withT.Count -ge 1){ [int]$withT[0].馬番 }else{ -1 })
  $mraw=New-Object System.Collections.Generic.List[object]
  for($i=0;$i -lt $nm;$i++){
    $rr=($i+0.5)/$nm
    if($rr -ge (1.0/3) -and $rr -lt (2.0/3)){ $mraw.Add($wm[$i]) }
  }
  $mrawA=@($mraw.ToArray() | Sort-Object v,u)
  if($mrawA.Count -eq 0){ continue }
  $midRank=@{}; for($i=0;$i -lt $mrawA.Count;$i++){ $midRank[$mrawA[$i].u]=$i+1 }
  foreach($e in $mrawA){
    $h=$e.h; $u=$e.u
    $r1=Num $h.p1r; $r2=Num $h.p2r; $r3=Num $h.p3r
    $s1=($null -ne $r1 -and $null -ne $r2 -and $null -ne $r3 -and $r1 -ge 0.30 -and $r1 -le 0.70 -and $r2 -ge 0.30 -and $r2 -le 0.70 -and $r3 -ge 0.30 -and $r3 -le 0.70)
    $wkr=$(if($tou -gt 1){ ([double]$u-1.0)/($tou-1.0) }else{ 0.5 })
    if(-not ($s1 -and $wkr -lt 0.80)){ continue }   # B1のみ収集
    # 頑健ADV/HOLD
    $advs=New-Object System.Collections.Generic.List[object]
    $holds=New-Object System.Collections.Generic.List[object]
    $q3=Num $h.p3r; $q4=Num $h.p4r
    $pf=$(if($h.前走着順 -eq ''){$null}else{[double]$h.前走着順})
    $pt2=$(if($h.前走頭数 -eq ''){$null}else{[double]$h.前走頭数})
    $fr1=$(if($null -ne $pf -and $null -ne $pt2 -and $pt2 -gt 1){ ($pf-1.0)/($pt2-1.0) }else{ $null })
    if($null -ne $q3 -and $null -ne $q4 -and $null -ne $fr1){ $advs.Add($q3-$q4); $holds.Add($q4-$fr1) }
    foreach($sfx in @('2','3')){
      $x3=Num $h.("r3_$sfx"); $x4=Num $h.("r4_$sfx"); $xf=Num $h.("fr_$sfx")
      if($null -ne $x3 -and $null -ne $x4 -and $null -ne $xf){ $advs.Add($x3-$x4); $holds.Add($x4-$xf) }
    }
    # 簡易版(実装済みG7): 3走平均前進∧前走前進∧前走4角→着順前進
    $a3v=Num $h.a3_3; $a4v=Num $h.a4_3
    $simple=0
    if($null -ne $q4 -and $null -ne $a4v -and $null -ne $a3v -and $null -ne $q3 -and $null -ne $fr1){
      if(($a3v-$a4v) -gt 0 -and ($q3-$q4) -gt 0 -and $fr1 -lt $q4){ $simple=1 }
    }
    $cr=$(if($h.指数順位 -eq ''){99}else{[int]$h.指数順位})
    $REC.Add([pscustomobject]@{
      d=$h.開催日; y=$h.開催日.Substring(0,4); cell="$($h.開催場所)$($h.距離)"
      fin=[int]$h.着順; crB=(BandOf $cr)
      mrk=$midRank[$u]; adv=(GatePass $advs.ToArray() $true); hold=(GatePass $holds.ToArray() $false)
      simple=$simple; t1=$(if($u -eq $t1u){1}else{0})
      tan=[int]$h.tanPay; fuku=[int]$h.fukuPay
    })
  }
}
$b1=$REC.ToArray()
Write-Host ("B1(確定定義) {0}頭" -f $b1.Count)

function Sim([object[]]$sel,[string]$label){
  $s=@($sel); $n=$s.Count; if($n -eq 0){ return ('  {0,-44} n=0' -f $label) }
  $w=0;$p=0;$tan=0.0;$fuku=0.0;$blSum=0.0
  foreach($o in $s){
    if($o.fin -eq 1){ $w++; $tan+=$o.tan }; if($o.fin -le 3){ $p++; $fuku+=$o.fuku }
    $k="$($o.cell)|$($o.crB)"; if($BLT.ContainsKey($k)){ $blSum+=$BLT[$k].p/$BLT[$k].n }
  }
  $pr=$p/$n
  $ci=1.96*[math]::Sqrt($pr*(1-$pr)/$n)
  $dl=100.0*($pr - $blSum/$n)
  '  {0,-44} n={1,5} 勝率{2,4:P0} 複率{3,5:P1}±{4:P1} Δ複={5:+0.0;-0.0}pt 単回{6,5:P0} 複回{7,5:P0}' -f $label,$n,($w/$n),$pr,$ci,$dl,($tan/$n/100),($fuku/$n/100)
}

"`n===== [1] mid_rank×HOLDの4群表(B1母集団・留保1の直接確認) ====="
$g11=@($b1 | Where-Object { $_.mrk -eq 1 -and $_.hold -eq 'pass' })
$g01=@($b1 | Where-Object { $_.mrk -gt 1 -and $_.hold -eq 'pass' })
$g10=@($b1 | Where-Object { $_.mrk -eq 1 -and $_.hold -eq 'fail' })
$g00=@($b1 | Where-Object { $_.mrk -gt 1 -and $_.hold -eq 'fail' })
Sim $g11 'mid_rank=1 × HOLD通過'
Sim $g01 'mid_rank>1 × HOLD通過'
Sim $g10 'mid_rank=1 × HOLD不通過'
Sim $g00 'mid_rank>1 × HOLD不通過(基準群)'
$f=[Func[object[],double]]{ param($s) $p=@($s | Where-Object { $_.fin -le 3 }).Count; 100.0*$p/$s.Count }
$did=($f.Invoke($g11)-$f.Invoke($g01))-($f.Invoke($g10)-$f.Invoke($g00))
'  交互作用(差の差): mid_rankの増分(HOLD通過時-不通過時)={0:+0.0;-0.0}pt' -f $did
"-- mid_rank増分(HOLD通過群内・年別方向) --"
foreach($yy in @('2022','2023','2024','2025','2026')){
  $a=@($g11 | Where-Object { $_.y -eq $yy }); $b=@($g01 | Where-Object { $_.y -eq $yy })
  if($a.Count -gt 20 -and $b.Count -gt 20){ '  {0}: mrk1複率{1:P0}(n{2}) vs mrk>1複率{3:P0}(n{4}) 差={5:+0.0;-0.0}pt' -f $yy,($f.Invoke($a)/100),$a.Count,($f.Invoke($b)/100),$b.Count,($f.Invoke($a)-$f.Invoke($b)) }
}

"`n===== [2] C0-C5増分ラダー(§6: 時計1位後の追加増分) ====="
Sim $b1 'C0: B1(A3-REL∧S1∧枠<0.80)'
$c1=@($b1 | Where-Object { $_.t1 -eq 1 })
Sim $c1 'C1: C0+同条件組時計1位'
Sim @($c1 | Where-Object { $_.adv -eq 'pass' }) 'C2: C1+頑健ADV'
Sim @($c1 | Where-Object { $_.hold -eq 'pass' }) 'C3: C1+頑健HOLD'
$c4=@($c1 | Where-Object { $_.adv -eq 'pass' -and $_.hold -eq 'pass' })
Sim $c4 'C4: C1+頑健ADV∧頑健HOLD'
$c5=@($c1 | Where-Object { $_.simple -eq 1 })
Sim $c5 'C5: C1+簡易進出∧簡易維持(既報n=408)'
"-- 年別: C4 vs C5(頑健版vs簡易版のOOS安定性) --"
foreach($yy in @('2022','2023','2024','2025','2026')){
  Sim @($c4 | Where-Object { $_.y -eq $yy }) ("C4 $yy")
  Sim @($c5 | Where-Object { $_.y -eq $yy }) ("C5 $yy")
}

"`n===== [3] ADV/HOLD判定可能率(欠損選択バイアス・B1母集団) ====="
"-- セル別 unknown率 --"
foreach($cg in ($b1 | Group-Object cell | Where-Object { $_.Count -ge 200 } | Sort-Object Name)){
  $g=@($cg.Group)
  $ua=@($g | Where-Object { $_.adv -eq 'unknown' }).Count
  '  {0,-10} n={1,5} ADV/HOLD unknown率={2,5:P1}' -f $cg.Name,$g.Count,($ua/[double]$g.Count)
}
"-- 年度別 unknown率 --"
foreach($yg in ($b1 | Group-Object y | Sort-Object Name)){
  $g=@($yg.Group); $ua=@($g | Where-Object { $_.adv -eq 'unknown' }).Count
  '  {0} unknown率={1:P1}' -f $yg.Name,($ua/[double]$g.Count)
}
"-- 偏りチェック: unknown群の時計1位率/コンピ帯 --"
$unk=@($b1 | Where-Object { $_.adv -eq 'unknown' })
$kno=@($b1 | Where-Object { $_.adv -ne 'unknown' })
'  unknown群: 時計1位率={0:P1} コ1-4率={1:P1} 複率={2:P1}' -f (@($unk | Where-Object { $_.t1 -eq 1 }).Count/[double]$unk.Count),(@($unk | Where-Object { $_.crB -in @('コ1','コ2-4') }).Count/[double]$unk.Count),(@($unk | Where-Object { $_.fin -le 3 }).Count/[double]$unk.Count)
'  判定可能群: 時計1位率={0:P1} コ1-4率={1:P1} 複率={2:P1}' -f (@($kno | Where-Object { $_.t1 -eq 1 }).Count/[double]$kno.Count),(@($kno | Where-Object { $_.crB -in @('コ1','コ2-4') }).Count/[double]$kno.Count),(@($kno | Where-Object { $_.fin -le 3 }).Count/[double]$kno.Count)
"`nDONE"
