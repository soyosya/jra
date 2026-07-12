# 深掘り(オッズ不使用): G1∧G7(中団勢×時計1位×進出∧維持)の回収構造
# D1コンピ帯/D2セル別/D4頭数帯/D6進出・維持の強度/D7出走間隔帯
param([string]$Base='C:\keiba\analysis\samecond_mid_base5.csv',[double]$SameTh=0.60)
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
$REC=New-Object System.Collections.Generic.List[object]
foreach($grp in ($rows | Group-Object { "$($_.開催日)|$($_.開催場所)|$($_.レース番号)" })){
  $hs=@($grp.Group)
  $tou=[int]$hs[0].頭数
  $sameH=@($hs | Where-Object { $_.same -eq '1' })
  if(($sameH.Count/[double]$tou) -lt $SameTh){ continue }
  $withT=@($sameH | Where-Object { $_.前走時計 -ne '' -and [double]$_.前走時計 -gt 0 } | Sort-Object {[double]$_.前走時計},{[int]$_.馬番})
  $tRank=@{}; for($i=0;$i -lt $withT.Count;$i++){ $tRank[[int]$withT[$i].馬番]=$i+1 }
  $wm=@($sameH | Where-Object { $_.a3_3 -ne '' } | ForEach-Object { [pscustomobject]@{h=$_; u=[int]$_.馬番; v=[double]$_.a3_3} } | Sort-Object v,u)
  $nm=$wm.Count; if($nm -lt 5){ continue }
  for($i=0;$i -lt $nm;$i++){
    $rr=($i+0.5)/$nm
    if(-not ($rr -ge (1.0/3) -and $rr -lt (2.0/3))){ continue }
    $h=$wm[$i].h; $u=$wm[$i].u
    $r1=Num $h.p1r; $r2=Num $h.p2r; $r3=Num $h.p3r; $p4=Num $h.p4r; $a3=Num $h.a3_3; $a4=Num $h.a4_3
    if($null -eq $r1 -or $null -eq $r2 -or $null -eq $r3){ continue }
    if(-not ($r1 -ge 0.30 -and $r1 -le 0.70 -and $r2 -ge 0.30 -and $r2 -le 0.70 -and $r3 -ge 0.30 -and $r3 -le 0.70)){ continue }
    $wkr=$(if($tou -gt 1){ ([double]$u-1.0)/($tou-1.0) }else{ 0.5 })
    if($wkr -ge 0.80){ continue }
    if(-not ($tRank.ContainsKey($u) -and $tRank[$u] -eq 1)){ continue }   # G1
    $pf=$(if($h.前走着順 -eq ''){$null}else{[double]$h.前走着順})
    $ptou=$(if($h.前走頭数 -eq ''){$null}else{[double]$h.前走頭数})
    $fr1=$(if($null -ne $pf -and $null -ne $ptou -and $ptou -gt 1){ ($pf-1.0)/($ptou-1.0) }else{ $null })
    if($null -eq $p4 -or $null -eq $a4 -or $null -eq $fr1){ continue }
    if(-not (($a3-$a4) -gt 0 -and ($r3-$p4) -gt 0 -and $fr1 -lt $p4)){ continue }   # G7
    $advM=$r3-$p4; $holdM=$p4-$fr1
    $itv=$null
    if($h.前走日 -ne ''){ $itv=([datetime]$h.開催日 - [datetime]$h.前走日).Days }
    $cr=$(if($h.指数順位 -eq ''){99}else{[int]$h.指数順位})
    $REC.Add([pscustomobject]@{
      d=$h.開催日; y=$h.開催日.Substring(0,4); cell="$($h.開催場所)$($h.距離)"
      fin=[int]$h.着順; cr=$cr; crB=(BandOf $cr); tou=$tou
      advM=$advM; holdM=$holdM; itv=$itv
      tan=[int]$h.tanPay; fuku=[int]$h.fukuPay
    })
  }
}
$arr=$REC.ToArray()
Write-Host ("G1∧G7該当 {0}頭" -f $arr.Count)
function Sim([object[]]$sel,[string]$label){
  $s=@($sel); $n=$s.Count; if($n -eq 0){ return ('  {0,-36} n=0' -f $label) }
  $w=0;$p=0;$tan=0.0;$fuku=0.0;$blSum=0.0
  foreach($o in $s){
    if($o.fin -eq 1){ $w++; $tan+=$o.tan }; if($o.fin -le 3){ $p++; $fuku+=$o.fuku }
    $k="$($o.cell)|$($o.crB)"; if($BLT.ContainsKey($k)){ $blSum+=$BLT[$k].p/$BLT[$k].n }
  }
  $dl=100.0*($p/$n - $blSum/$n)
  '  {0,-36} n={1,5} 勝率{2,5:P0} 複率{3,5:P0} Δ複={4:+0.0;-0.0}pt 単回{5,6:P0} 複回{6,6:P0}' -f $label,$n,($w/$n),($p/$n),$dl,($tan/$n/100),($fuku/$n/100)
}
"`n===== D1 コンピ帯別 ====="
foreach($b in @('コ1','コ2-4','コ5-6','コ7+')){ Sim @($arr | Where-Object { $_.crB -eq $b }) ("G1G7×"+$b) }
"`n===== D2 セル別(n≥15) ====="
foreach($cg in ($arr | Group-Object cell | Where-Object { $_.Count -ge 15 } | Sort-Object Name)){ Sim $cg.Group ("  "+$cg.Name) }
"`n===== D4 頭数帯 ====="
Sim @($arr | Where-Object { $_.tou -le 8 }) '頭数≤8'
Sim @($arr | Where-Object { $_.tou -ge 9 -and $_.tou -le 11 }) '頭数9-11'
Sim @($arr | Where-Object { $_.tou -ge 12 }) '頭数12+'
"`n===== D6 用量反応: 進出幅/維持幅(中央値で二分) ====="
$mAdv=($arr | ForEach-Object { $_.advM } | Sort-Object)[[int]($arr.Count/2)]
$mHold=($arr | ForEach-Object { $_.holdM } | Sort-Object)[[int]($arr.Count/2)]
'  (中央値: 進出幅={0:N3} 維持幅={1:N3})' -f $mAdv,$mHold
Sim @($arr | Where-Object { $_.advM -gt $mAdv }) '進出幅 大(中央値超)'
Sim @($arr | Where-Object { $_.advM -le $mAdv }) '進出幅 小'
Sim @($arr | Where-Object { $_.holdM -gt $mHold }) '維持幅 大'
Sim @($arr | Where-Object { $_.holdM -le $mHold }) '維持幅 小'
Sim @($arr | Where-Object { $_.advM -gt $mAdv -and $_.holdM -gt $mHold }) '進出大∧維持大'
"`n===== D7 出走間隔帯 ====="
Sim @($arr | Where-Object { $null -ne $_.itv -and $_.itv -le 21 }) '間隔≤21日'
Sim @($arr | Where-Object { $null -ne $_.itv -and $_.itv -ge 22 -and $_.itv -le 35 }) '間隔22-35日'
Sim @($arr | Where-Object { $null -ne $_.itv -and $_.itv -ge 36 -and $_.itv -le 90 }) '間隔36-90日'
Sim @($arr | Where-Object { $null -ne $_.itv -and $_.itv -ge 91 }) '間隔91日+(休み明け)'
"`nDONE"
