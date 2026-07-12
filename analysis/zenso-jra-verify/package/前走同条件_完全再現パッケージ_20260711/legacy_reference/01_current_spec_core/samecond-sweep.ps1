# 一斉検証: 確定した中団勢定義(A3-REL∧S1持続∧枠<0.80)の上での有力馬シグナル
# 事前固定仮説: G1時計1位/G2上り1位/G3コンピ2位/G4中団先頭型/G5進出力/G6維持力/G7進出∧維持
#   複合G1×G4-G7 / 修飾G8先行圧力×持続力(G1層別) / G9中団密度(G1層別)
# 前提不変: SameTh=0.60・20セル・2022-2026・Δ複=セル×コンピ帯統制・2M窓=2026-05-10以降
param([string]$Base='C:\keiba\analysis\samecond_mid_base5.csv',[double]$SameTh=0.60)
[Console]::OutputEncoding=[System.Text.Encoding]::UTF8
$ErrorActionPreference='Stop'
$rows=Import-Csv $Base -Encoding UTF8
Write-Host ("ロード {0}行" -f $rows.Count)
function Num($x){ if($x -eq '' -or $null -eq $x){ $null } else { [double]$x } }

# ベースライン(セル×コンピ帯の複勝率)
$BLT=@{}
function BandOf([int]$cr){ if($cr -eq 1){'コ1'}elseif($cr -le 4){'コ2-4'}elseif($cr -le 6){'コ5-6'}else{'コ7+'} }
foreach($r in $rows){
  $cr=$(if($r.指数順位 -eq ''){99}else{[int]$r.指数順位})
  $key="$($r.開催場所)$($r.距離)|$(BandOf $cr)"
  if(-not $BLT.ContainsKey($key)){ $BLT[$key]=@{n=0;p=0} }
  $BLT[$key].n++; if([int]$r.着順 -le 3){ $BLT[$key].p++ }
}

$REC=New-Object System.Collections.Generic.List[object]
$raceCnt=0
foreach($grp in ($rows | Group-Object { "$($_.開催日)|$($_.開催場所)|$($_.レース番号)" })){
  $hs=@($grp.Group)
  $tou=[int]$hs[0].頭数
  $sameH=@($hs | Where-Object { $_.same -eq '1' })
  if(($sameH.Count/[double]$tou) -lt $SameTh){ continue }
  $raceCnt++
  # 同条件組ランク: 前走時計/前走上り
  $withT=@($sameH | Where-Object { $_.前走時計 -ne '' -and [double]$_.前走時計 -gt 0 } | Sort-Object {[double]$_.前走時計},{[int]$_.馬番})
  $tRank=@{}; for($i=0;$i -lt $withT.Count;$i++){ $tRank[[int]$withT[$i].馬番]=$i+1 }
  $withA=@($sameH | Where-Object { $_.前走上り -ne '' -and [double]$_.前走上り -gt 0 } | Sort-Object {[double]$_.前走上り},{[int]$_.馬番})
  $aRank=@{}; for($i=0;$i -lt $withA.Count;$i++){ $aRank[[int]$withA[$i].馬番]=$i+1 }
  # A3相対位置(同条件組)
  $wm=@($sameH | Where-Object { $_.a3_3 -ne '' } | ForEach-Object { [pscustomobject]@{h=$_; u=[int]$_.馬番; v=[double]$_.a3_3} } | Sort-Object v,u)
  $nm=$wm.Count; if($nm -lt 5){ continue }
  # 先行圧力/持続力(レース属性): 前1/3グループ
  $frontH=New-Object System.Collections.Generic.List[object]
  $posOf=@{}
  for($i=0;$i -lt $nm;$i++){
    $rr=($i+0.5)/$nm
    $posOf[$wm[$i].u]=$(if($rr -lt (1.0/3)){'F'}elseif($rr -lt (2.0/3)){'M'}else{'B'})
    if($rr -lt (1.0/3)){ $frontH.Add($wm[$i].h) }
  }
  $fArr=$frontH.ToArray()
  $fPress=$(if($fArr.Count -ge 4){'圧力高'}else{'圧力低'})
  $fFrs=@($fArr | Where-Object { $_.前走着順 -ne '' -and $_.前走頭数 -ne '' -and [double]$_.前走頭数 -gt 1 } | ForEach-Object { ([double]$_.前走着順-1.0)/([double]$_.前走頭数-1.0) })
  $fSust=''
  if($fFrs.Count -ge 2){
    $fAvg=($fFrs | Measure-Object -Average).Average
    $fSust=$(if($fAvg -ge 0.45){'持続低'}else{'持続高'})
  }
  # 中団勢(確定定義)
  $mids=New-Object System.Collections.Generic.List[object]
  foreach($e in $wm){
    if($posOf[$e.u] -ne 'M'){ continue }
    $h=$e.h
    $r1=Num $h.p1r; $r2=Num $h.p2r; $r3=Num $h.p3r
    if($null -eq $r1 -or $null -eq $r2 -or $null -eq $r3){ continue }
    if(-not ($r1 -ge 0.30 -and $r1 -le 0.70 -and $r2 -ge 0.30 -and $r2 -le 0.70 -and $r3 -ge 0.30 -and $r3 -le 0.70)){ continue }
    $wkr=$(if($tou -gt 1){ ([double]$e.u-1.0)/($tou-1.0) }else{ 0.5 })
    if($wkr -ge 0.80){ continue }
    $mids.Add($e)
  }
  $mArr=$mids.ToArray()
  if($mArr.Count -eq 0){ continue }
  $densB=$(if($mArr.Count -eq 1){'密度1'}elseif($mArr.Count -eq 2){'密度2'}else{'密度3+'})
  $frontUma=([int]($mArr | Sort-Object v,u | Select-Object -First 1).u)   # 中団先頭型
  foreach($e in $mArr){
    $h=$e.h; $u=$e.u
    $p3=Num $h.p3r; $p4=Num $h.p4r; $a3=Num $h.a3_3; $a4=Num $h.a4_3
    $pf=$(if($h.前走着順 -eq ''){$null}else{[double]$h.前走着順})
    $ptou=$(if($h.前走頭数 -eq ''){$null}else{[double]$h.前走頭数})
    $fr1=$(if($null -ne $pf -and $null -ne $ptou -and $ptou -gt 1){ ($pf-1.0)/($ptou-1.0) }else{ $null })
    $adv=$(if($null -ne $p4 -and $null -ne $a4 -and $null -ne $a3 -and $null -ne $p3){ if(($a3-$a4) -gt 0 -and ($p3-$p4) -gt 0){1}else{0} }else{ $null })
    $hold=$(if($null -ne $fr1 -and $null -ne $p4){ if($fr1 -lt $p4){1}else{0} }else{ $null })
    $cr=$(if($h.指数順位 -eq ''){99}else{[int]$h.指数順位})
    $REC.Add([pscustomobject]@{
      d=$h.開催日; y=$h.開催日.Substring(0,4); cell="$($h.開催場所)$($h.距離)"
      fin=[int]$h.着順; cr=$cr; crB=(BandOf $cr)
      t1=$(if($tRank.ContainsKey($u) -and $tRank[$u] -eq 1){1}else{0})
      a1=$(if($aRank.ContainsKey($u) -and $aRank[$u] -eq 1){1}else{0})
      lead=$(if($u -eq $frontUma){1}else{0})
      adv=$adv; hold=$hold
      press=$fPress; sust=$fSust; dens=$densB
      tan=[int]$h.tanPay; fuku=[int]$h.fukuPay
    })
  }
}
$arr=$REC.ToArray()
Write-Host ("対象レース {0} / 中団勢(確定定義) {1}頭" -f $raceCnt,$arr.Count)

function Sim([object[]]$sel,[string]$label){
  $s=@($sel); $n=$s.Count; if($n -eq 0){ return ('  {0,-40} n=0' -f $label) }
  $w=0;$p=0;$tan=0.0;$fuku=0.0;$blSum=0.0
  foreach($o in $s){
    if($o.fin -eq 1){ $w++; $tan+=$o.tan }; if($o.fin -le 3){ $p++; $fuku+=$o.fuku }
    $k="$($o.cell)|$($o.crB)"; if($BLT.ContainsKey($k)){ $blSum+=$BLT[$k].p/$BLT[$k].n }
  }
  $dl=100.0*($p/$n - $blSum/$n)
  '  {0,-40} n={1,5} 勝率{2,5:P0} 複率{3,5:P0} Δ複={4:+0.0;-0.0}pt 単回{5,6:P0} 複回{6,6:P0}' -f $label,$n,($w/$n),($p/$n),$dl,($tan/$n/100),($fuku/$n/100)
}
function YearsAnd2M([object[]]$sel,[string]$tag){
  foreach($yy in @('2022','2023','2024','2025','2026')){ Sim @($sel | Where-Object { $_.y -eq $yy }) ("  └ $tag $yy") }
  Sim @($sel | Where-Object { $_.d -ge '2026-05-10' }) ("  └ $tag 直近2ヶ月窓")
}

"`n===== [G0] 中団勢(確定定義)全体 ====="
Sim $arr 'G0: 中団勢全体'

"`n===== 単独シグナル ====="
$g1=@($arr | Where-Object { $_.t1 -eq 1 });   Sim $g1 'G1: 同条件組時計1位'
$g2=@($arr | Where-Object { $_.a1 -eq 1 });   Sim $g2 'G2: 同条件組上り1位'
$g3=@($arr | Where-Object { $_.cr -eq 2 });   Sim $g3 'G3: コンピ2位'
$g4=@($arr | Where-Object { $_.lead -eq 1 }); Sim $g4 'G4: 中団先頭型'
$g5=@($arr | Where-Object { $_.adv -eq 1 });  Sim $g5 'G5: 進出力(3走平均∧前走で3-4角前進)'
$g6=@($arr | Where-Object { $_.hold -eq 1 }); Sim $g6 'G6: 維持力(前走4角→着順で前進)'
$g7=@($arr | Where-Object { $_.adv -eq 1 -and $_.hold -eq 1 }); Sim $g7 'G7: 進出∧維持'
Sim @($arr | Where-Object { $_.adv -eq 0 }) '対照: 進出なし'
Sim @($arr | Where-Object { $_.hold -eq 0 }) '対照: 維持なし(4角から後退)'

"`n===== 複合(G1=時計1位を核に) ====="
Sim @($g1 | Where-Object { $_.lead -eq 1 }) 'G1 ∧ G4中団先頭'
Sim @($g1 | Where-Object { $_.adv -eq 1 })  'G1 ∧ G5進出'
Sim @($g1 | Where-Object { $_.hold -eq 1 }) 'G1 ∧ G6維持'
Sim @($g1 | Where-Object { $_.adv -eq 1 -and $_.hold -eq 1 }) 'G1 ∧ G7進出∧維持'
Sim @($g4 | Where-Object { $_.adv -eq 1 -and $_.hold -eq 1 }) 'G4 ∧ G7進出∧維持'

"`n===== [G8] レース構造: 先行圧力×先行持続力(G1の層別) ====="
Sim @($g1 | Where-Object { $_.press -eq '圧力高' -and $_.sust -eq '持続低' }) 'G1×圧力高∧持続低(docx本命構成)'
Sim @($g1 | Where-Object { $_.press -eq '圧力高' -and $_.sust -eq '持続高' }) 'G1×圧力高∧持続高'
Sim @($g1 | Where-Object { $_.press -eq '圧力低' -and $_.sust -eq '持続低' }) 'G1×圧力低∧持続低'
Sim @($g1 | Where-Object { $_.press -eq '圧力低' -and $_.sust -eq '持続高' }) 'G1×圧力低∧持続高(中団不利想定)'

"`n===== [G9] 中団密度(G1の層別) ====="
foreach($db in @('密度1','密度2','密度3+')){ Sim @($g1 | Where-Object { $_.dens -eq $db }) ("G1×"+$db) }

"`n===== 年別/2M窓: 主要群 ====="
Sim $g1 'G1(再掲)'; YearsAnd2M $g1 'G1'
Sim $g4 'G4(再掲)'; YearsAnd2M $g4 'G4'
$g17=@($g1 | Where-Object { $_.adv -eq 1 -and $_.hold -eq 1 })
Sim $g17 'G1∧G7(再掲)'; YearsAnd2M $g17 'G1G7'
"`nDONE"
