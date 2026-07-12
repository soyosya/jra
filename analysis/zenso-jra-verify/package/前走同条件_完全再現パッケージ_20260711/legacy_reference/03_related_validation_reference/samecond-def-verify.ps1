# 中団勢の定義検証: コーナー軸(前走3角/前走4角/3走平均3角/3走平均4角)×相対化方式(絶対band/メンバー内相対/先行除外後前目)
# 確からしさ = 今走で実際に中団(同コーナーのメンバー内中位1/3)に入った率。無情報ベースライン≈33%
# 追加検証: 頭数帯別・先行型頭数別の安定性/E=定義×時計1位のΔ複(シグナルの切れ)
param([string]$Base='C:\keiba\analysis\samecond_mid_base3.csv',[double]$SameTh=0.60)
[Console]::OutputEncoding=[System.Text.Encoding]::UTF8
$ErrorActionPreference='Stop'
$rows=Import-Csv $Base -Encoding UTF8
Write-Host ("ロード {0}行" -f $rows.Count)

# ベースライン(セル×コンピ帯の複勝率) — E判定用
$BLT=@{}
function BandOf([int]$cr){ if($cr -eq 1){'コ1'}elseif($cr -le 4){'コ2-4'}elseif($cr -le 6){'コ5-6'}else{'コ7+'} }
foreach($r in $rows){
  $cr=$(if($r.指数順位 -eq ''){99}else{[int]$r.指数順位})
  $key="$($r.開催場所)$($r.距離)|$(BandOf $cr)"
  if(-not $BLT.ContainsKey($key)){ $BLT[$key]=@{n=0;p=0} }
  $BLT[$key].n++; if([int]$r.着順 -le 3){ $BLT[$key].p++ }
}

function Num($x){ if($x -eq '' -or $null -eq $x){ $null } else { [double]$x } }

# 変種: コーナー軸×方式
$VARIANTS=@('P3-ABS','P3-REL','P3-EXS','P4-ABS','P4-REL','P4-EXS','A3-ABS','A3-REL','A3-EXS','A4-ABS','A4-REL','A4-EXS')
$REC=@{}; foreach($v in $VARIANTS){ $REC[$v]=New-Object System.Collections.Generic.List[object] }
$raceCnt=0

foreach($grp in ($rows | Group-Object { "$($_.開催日)|$($_.開催場所)|$($_.レース番号)" })){
  $hs=@($grp.Group)
  $tou=[int]$hs[0].頭数
  $sameH=@($hs | Where-Object { $_.same -eq '1' })
  if(($sameH.Count/[double]$tou) -lt $SameTh){ continue }
  $raceCnt++

  # 今走の実位置: 全馬をt3/t4でランク→メンバー内相対位置(中位1/3判定)
  $midToday=@{}   # 't3'/'t4' -> hashtable[馬番]=0/1
  foreach($tc in @('t3','t4')){
    $wv=@($hs | Where-Object { $_.$tc -ne '' } | ForEach-Object { [pscustomobject]@{u=[int]$_.馬番; v=[double]$_.$tc} } | Sort-Object v,u)
    $m=$wv.Count; $h=@{}
    if($m -ge 5){
      for($i=0;$i -lt $m;$i++){
        $rr=($i+0.5)/$m
        $h[$wv[$i].u]=$(if($rr -ge (1.0/3) -and $rr -lt (2.0/3)){1}else{0})
      }
    }
    $midToday[$tc]=$h
  }

  # 同条件組: 前走時計ランク(E判定用)・先行型頭数(前走3角<0.30)
  $withT=@($sameH | Where-Object { $_.前走時計 -ne '' -and [double]$_.前走時計 -gt 0 } | Sort-Object {[double]$_.前走時計},{[int]$_.馬番})
  $tRank=@{}; for($i=0;$i -lt $withT.Count;$i++){ $tRank[[int]$withT[$i].馬番]=$i+1 }
  $senkoN=@($sameH | Where-Object { $_.p3r -ne '' -and [double]$_.p3r -lt 0.30 }).Count
  $senkoB=$(if($senkoN -le 2){'先行0-2'}elseif($senkoN -le 4){'先行3-4'}else{'先行5+'})
  $touB=$(if($tou -le 8){'頭数≤8'}elseif($tou -le 11){'頭数9-11'}else{'頭数12+'})

  # 各変種の選定
  foreach($ax in @(@{k='P3';c='p3r';o='t3'},@{k='P4';c='p4r';o='t4'},@{k='A3';c='a3_3';o='t3'},@{k='A4';c='a4_3';o='t4'})){
    $col=$ax.c; $oc=$ax.o
    $wm=@($sameH | Where-Object { $_.$col -ne '' } | ForEach-Object { [pscustomobject]@{h=$_; u=[int]$_.馬番; v=[double]$_.$col} } | Sort-Object v,u)
    $nm=$wm.Count
    if($nm -lt 5){ continue }
    # ABS: 0.30-0.70
    $selAbs=@($wm | Where-Object { $_.v -ge 0.30 -and $_.v -le 0.70 })
    # REL: メンバー内中位1/3
    $selRel=New-Object System.Collections.Generic.List[object]
    for($i=0;$i -lt $nm;$i++){ $rr=($i+0.5)/$nm; if($rr -ge (1.0/3) -and $rr -lt (2.0/3)){ $selRel.Add($wm[$i]) } }
    # EXS: 先行型(<0.30)除外→残りの前目半分
    $rest=@($wm | Where-Object { $_.v -ge 0.30 })
    $selExs=New-Object System.Collections.Generic.List[object]
    $half=[math]::Ceiling($rest.Count/2.0)
    for($i=0;$i -lt [math]::Min($half,$rest.Count);$i++){ $selExs.Add($rest[$i]) }
    foreach($mv in @(@{m='ABS';s=$selAbs},@{m='REL';s=$selRel.ToArray()},@{m='EXS';s=$selExs.ToArray()})){
      $vk="$($ax.k)-$($mv.m)"
      foreach($e in @($mv.s)){
        $hh=$e.h; $u=$e.u
        $om=$midToday[$oc]
        if($om.Count -eq 0 -or -not $om.ContainsKey($u)){ continue }  # 今走位置不明は除外
        $cr=$(if($hh.指数順位 -eq ''){99}else{[int]$hh.指数順位})
        $REC[$vk].Add([pscustomobject]@{
          y=$hh.開催日.Substring(0,4); cell="$($hh.開催場所)$($hh.距離)"
          mid=$om[$u]; fin=[int]$hh.着順; crB=(BandOf $cr)
          tr=$(if($tRank.ContainsKey($u)){$tRank[$u]}else{0})
          touB=$touB; senkoB=$senkoB; nSel=0
          tan=[int]$hh.tanPay; fuku=[int]$hh.fukuPay; race=$grp.Name
        })
      }
    }
  }
}
Write-Host ("対象レース {0}" -f $raceCnt)

"`n===== [A] 定義×再現率(今走で実際に中団=同コーナー中位1/3に入った率 / 無情報≈33%) ====="
'  {0,-8} {1,8} {2,10} {3,10} {4,12}' -f '定義','n','頭/R','再現率','lift(×1/3比)'
foreach($v in $VARIANTS){
  $a=$REC[$v].ToArray(); $n=$a.Count; if($n -eq 0){ '  {0,-8} n=0' -f $v; continue }
  $races=@($a | Group-Object race).Count
  $mid=@($a | Where-Object { $_.mid -eq 1 }).Count
  '  {0,-8} {1,8} {2,10:N2} {3,9:P1} {4,11:N2}' -f $v,$n,($n/[double]$races),($mid/[double]$n),(($mid/[double]$n)/(1.0/3))
}

"`n===== [B] 頭数帯別の再現率(定義の安定性) ====="
foreach($v in $VARIANTS){
  $a=$REC[$v].ToArray(); if($a.Count -eq 0){ continue }
  $parts=foreach($tb in @('頭数≤8','頭数9-11','頭数12+')){
    $s=@($a | Where-Object { $_.touB -eq $tb }); if($s.Count -eq 0){ "$tb=--" } else { $m=@($s | Where-Object { $_.mid -eq 1 }).Count; '{0}={1:P0}(n{2})' -f $tb,($m/[double]$s.Count),$s.Count }
  }
  '  {0,-8} {1}' -f $v,($parts -join ' ')
}

"`n===== [C] 先行型頭数別の再現率(脚質構成依存) ====="
foreach($v in $VARIANTS){
  $a=$REC[$v].ToArray(); if($a.Count -eq 0){ continue }
  $parts=foreach($sb in @('先行0-2','先行3-4','先行5+')){
    $s=@($a | Where-Object { $_.senkoB -eq $sb }); if($s.Count -eq 0){ "$sb=--" } else { $m=@($s | Where-Object { $_.mid -eq 1 }).Count; '{0}={1:P0}(n{2})' -f $sb,($m/[double]$s.Count),$s.Count }
  }
  '  {0,-8} {1}' -f $v,($parts -join ' ')
}

"`n===== [D] シグナルの切れ: 定義∧同条件組時計1位 のΔ複(セル×コンピ帯統制) ====="
function SimE([object[]]$sel,[string]$label){
  $s=@($sel); $n=$s.Count; if($n -eq 0){ return ('  {0,-10} n=0' -f $label) }
  $w=0;$p=0;$tan=0.0;$fuku=0.0;$blSum=0.0
  foreach($o in $s){
    if($o.fin -eq 1){ $w++; $tan+=$o.tan }; if($o.fin -le 3){ $p++; $fuku+=$o.fuku }
    $k="$($o.cell)|$($o.crB)"; if($BLT.ContainsKey($k)){ $blSum+=$BLT[$k].p/$BLT[$k].n }
  }
  $dl=100.0*($p/$n - $blSum/$n)
  '  {0,-10} n={1,5} 勝率{2,5:P0} 複率{3,5:P0} Δ複={4:+0.0;-0.0}pt 単回{5,6:P0} 複回{6,6:P0}' -f $label,$n,($w/$n),($p/$n),$dl,($tan/$n/100),($fuku/$n/100)
}
foreach($v in $VARIANTS){
  $a=@($REC[$v].ToArray() | Where-Object { $_.tr -eq 1 })
  SimE $a $v
}

"`n===== [E] 年別再現率(上位変種の頑健性) ====="
foreach($v in $VARIANTS){
  $a=$REC[$v].ToArray(); if($a.Count -eq 0){ continue }
  $parts=foreach($yy in @('2022','2023','2024','2025','2026')){
    $s=@($a | Where-Object { $_.y -eq $yy }); if($s.Count -eq 0){ "$yy=--" } else { $m=@($s | Where-Object { $_.mid -eq 1 }).Count; '{0}={1:P0}' -f $yy,($m/[double]$s.Count) }
  }
  '  {0,-8} {1}' -f $v,($parts -join ' ')
}
"`nDONE"
