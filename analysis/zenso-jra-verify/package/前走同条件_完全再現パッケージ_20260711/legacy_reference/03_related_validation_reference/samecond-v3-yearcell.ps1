# 先方依頼(§11必須): 年度×セル別の n/勝率/複率/Δ複/単複ROI を C0/C1/C4/C5 についてCSV出力
param([string]$Base='C:\keiba\analysis\samecond_mid_base6.csv',[string]$Out='C:\keiba\analysis\samecond_v3_yearcell.csv',[double]$SameTh=0.60)
[Console]::OutputEncoding=[System.Text.Encoding]::UTF8
$ErrorActionPreference='Stop'
$rows=Import-Csv $Base -Encoding UTF8
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
  for($i=0;$i -lt $nm;$i++){
    $rr=($i+0.5)/$nm
    if(-not ($rr -ge (1.0/3) -and $rr -lt (2.0/3))){ continue }
    $h=$wm[$i].h; $u=$wm[$i].u
    $r1=Num $h.p1r; $r2=Num $h.p2r; $r3=Num $h.p3r
    $s1=($null -ne $r1 -and $null -ne $r2 -and $null -ne $r3 -and $r1 -ge 0.30 -and $r1 -le 0.70 -and $r2 -ge 0.30 -and $r2 -le 0.70 -and $r3 -ge 0.30 -and $r3 -le 0.70)
    $wkr=$(if($tou -gt 1){ ([double]$u-1.0)/($tou-1.0) }else{ 0.5 })
    if(-not ($s1 -and $wkr -lt 0.80)){ continue }
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
    $a3v=Num $h.a3_3; $a4v=Num $h.a4_3
    $simple=0
    if($null -ne $q4 -and $null -ne $a4v -and $null -ne $a3v -and $null -ne $q3 -and $null -ne $fr1){
      if(($a3v-$a4v) -gt 0 -and ($q3-$q4) -gt 0 -and $fr1 -lt $q4){ $simple=1 }
    }
    $cr=$(if($h.指数順位 -eq ''){99}else{[int]$h.指数順位})
    $REC.Add([pscustomobject]@{
      y=$h.開催日.Substring(0,4); cell="$($h.開催場所)$($h.距離)"
      fin=[int]$h.着順; crB=(BandOf $cr)
      t1=$(if($u -eq $t1u){1}else{0})
      advP=$((GatePass $advs.ToArray() $true) -eq 'pass'); holdP=$((GatePass $holds.ToArray() $false) -eq 'pass')
      simple=$simple; tan=[int]$h.tanPay; fuku=[int]$h.fukuPay
    })
  }
}
$b1=$REC.ToArray()
$sw=New-Object System.IO.StreamWriter($Out,$false,[System.Text.Encoding]::UTF8)
$sw.WriteLine('group,year,cell,n,winRate,fukuRate,deltaFuku_pt,tanROI,fukuROI')
function EmitRows([object[]]$set,[string]$gname){
  foreach($yg in ($set | Group-Object y | Sort-Object Name)){
    foreach($cg in ($yg.Group | Group-Object cell | Sort-Object Name)){
      $s=@($cg.Group); $n=$s.Count
      $w=@($s | Where-Object { $_.fin -eq 1 }).Count
      $p=@($s | Where-Object { $_.fin -le 3 }).Count
      $tan=($s | Measure-Object tan -Sum).Sum
      $fuku=($s | Measure-Object fuku -Sum).Sum
      $blSum=0.0
      foreach($o in $s){ $k="$($o.cell)|$($o.crB)"; if($BLT.ContainsKey($k)){ $blSum+=$BLT[$k].p/$BLT[$k].n } }
      $dl=100.0*($p/$n - $blSum/$n)
      $sw.WriteLine(('{0},{1},{2},{3},{4},{5},{6},{7},{8}' -f $gname,$yg.Name,$cg.Name,$n,[math]::Round($w/$n,4),[math]::Round($p/$n,4),[math]::Round($dl,2),[math]::Round($tan/100.0/$n,4),[math]::Round($fuku/100.0/$n,4)))
    }
  }
}
EmitRows $b1 'C0_B1'
EmitRows @($b1 | Where-Object { $_.t1 -eq 1 }) 'C1_clock1'
EmitRows @($b1 | Where-Object { $_.t1 -eq 1 -and $_.advP -and $_.holdP }) 'C4_robust'
EmitRows @($b1 | Where-Object { $_.t1 -eq 1 -and $_.simple -eq 1 }) 'C5_simple'
$sw.Close()
Write-Host ("DONE -> {0}" -f $Out)
