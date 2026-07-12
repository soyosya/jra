# 新定義(A3-REL∧S1持続)×今走枠順: 馬番相対位置で再現率が変わるか
# 枠は発走前に既知=当日条件として正当。帯別再現率+年別頑健性
param([string]$Base='C:\keiba\analysis\samecond_mid_base3.csv',[double]$SameTh=0.60)
[Console]::OutputEncoding=[System.Text.Encoding]::UTF8
$ErrorActionPreference='Stop'
$rows=Import-Csv $Base -Encoding UTF8
Write-Host ("ロード {0}行" -f $rows.Count)
function Num($x){ if($x -eq '' -or $null -eq $x){ $null } else { [double]$x } }

$REC=New-Object System.Collections.Generic.List[object]
foreach($grp in ($rows | Group-Object { "$($_.開催日)|$($_.開催場所)|$($_.レース番号)" })){
  $hs=@($grp.Group)
  $tou=[int]$hs[0].頭数
  $sameH=@($hs | Where-Object { $_.same -eq '1' })
  if(($sameH.Count/[double]$tou) -lt $SameTh){ continue }
  $wv=@($hs | Where-Object { $_.t3 -ne '' } | ForEach-Object { [pscustomobject]@{u=[int]$_.馬番; v=[double]$_.t3} } | Sort-Object v,u)
  $m=$wv.Count; if($m -lt 5){ continue }
  $midT=@{}
  for($i=0;$i -lt $m;$i++){ $rr=($i+0.5)/$m; $midT[$wv[$i].u]=$(if($rr -ge (1.0/3) -and $rr -lt (2.0/3)){1}else{0}) }
  # A3-REL: 同条件組のa3_3中位1/3
  $wm=@($sameH | Where-Object { $_.a3_3 -ne '' -and $_.p3r -ne '' } | ForEach-Object { [pscustomobject]@{h=$_; u=[int]$_.馬番; v=[double]$_.a3_3} } | Sort-Object v,u)
  $nm=$wm.Count; if($nm -lt 5){ continue }
  for($i=0;$i -lt $nm;$i++){
    $rr=($i+0.5)/$nm
    if(-not ($rr -ge (1.0/3) -and $rr -lt (2.0/3))){ continue }
    $h=$wm[$i].h; $u=$wm[$i].u
    if(-not $midT.ContainsKey($u)){ continue }
    $r1=Num $h.p1r; $r2=Num $h.p2r; $r3=Num $h.p3r
    if($null -eq $r1 -or $null -eq $r2 -or $null -eq $r3){ continue }
    if(-not ($r1 -ge 0.30 -and $r1 -le 0.70 -and $r2 -ge 0.30 -and $r2 -le 0.70 -and $r3 -ge 0.30 -and $r3 -le 0.70)){ continue }
    $wkr=$(if($tou -gt 1){ ($u-1.0)/($tou-1.0) }else{ 0.5 })
    $REC.Add([pscustomobject]@{
      y=$h.開催日.Substring(0,4); cell="$($h.開催場所)$($h.距離)"
      mid=$midT[$u]; wkr=$wkr; tou=$tou; u=$u
    })
  }
}
$combo=$REC.ToArray()
Write-Host ("新定義(A3-REL∧S1持続)該当 {0}頭" -f $combo.Count)

function Rep([object[]]$s,[string]$label){
  $x=@($s); $n=$x.Count; if($n -eq 0){ return ('  {0,-40} n=0' -f $label) }
  $mid=@($x | Where-Object { $_.mid -eq 1 }).Count
  '  {0,-40} n={1,6} 再現率={2,6:P1} lift={3:N2}' -f $label,$n,($mid/[double]$n),(($mid/[double]$n)/(1.0/3))
}

"`n===== [1] 今走馬番相対位置(5分位)別の再現率 ====="
Rep @($combo | Where-Object { $_.wkr -lt 0.20 }) '最内 (0.00-0.20)'
Rep @($combo | Where-Object { $_.wkr -ge 0.20 -and $_.wkr -lt 0.40 }) '内   (0.20-0.40)'
Rep @($combo | Where-Object { $_.wkr -ge 0.40 -and $_.wkr -lt 0.60 }) '中   (0.40-0.60)'
Rep @($combo | Where-Object { $_.wkr -ge 0.60 -and $_.wkr -lt 0.80 }) '外   (0.60-0.80)'
Rep @($combo | Where-Object { $_.wkr -ge 0.80 }) '大外 (0.80-1.00)'

"`n===== [2] 粗い帯(3分割) ====="
Rep @($combo | Where-Object { $_.wkr -lt (1.0/3) }) '内1/3'
Rep @($combo | Where-Object { $_.wkr -ge (1.0/3) -and $_.wkr -lt (2.0/3) }) '中1/3'
Rep @($combo | Where-Object { $_.wkr -ge (2.0/3) }) '外1/3'

"`n===== [3] 最良帯の年別頑健性(結果を見て中央寄り帯を事前想定: 0.20-0.80) ====="
$best=@($combo | Where-Object { $_.wkr -ge 0.20 -and $_.wkr -lt 0.80 })
Rep $best '枠0.20-0.80 全体'
foreach($yy in @('2022','2023','2024','2025','2026')){ Rep @($best | Where-Object { $_.y -eq $yy }) ("  $yy") }
$worst=@($combo | Where-Object { $_.wkr -lt 0.20 -or $_.wkr -ge 0.80 })
Rep $worst '両端(最内+大外) 全体'
foreach($yy in @('2022','2023','2024','2025','2026')){ Rep @($worst | Where-Object { $_.y -eq $yy }) ("  $yy") }

"`n===== [4] 参考: 定義なし全馬(同条件組)での枠→今走中団率(枠効果の一般性) ====="
$ALL=New-Object System.Collections.Generic.List[object]
foreach($grp in ($rows | Group-Object { "$($_.開催日)|$($_.開催場所)|$($_.レース番号)" })){
  $hs=@($grp.Group)
  $tou=[int]$hs[0].頭数
  $sameH=@($hs | Where-Object { $_.same -eq '1' })
  if(($sameH.Count/[double]$tou) -lt $SameTh){ continue }
  $wv=@($hs | Where-Object { $_.t3 -ne '' } | ForEach-Object { [pscustomobject]@{u=[int]$_.馬番; v=[double]$_.t3} } | Sort-Object v,u)
  $m=$wv.Count; if($m -lt 5){ continue }
  $midT=@{}
  for($i=0;$i -lt $m;$i++){ $rr=($i+0.5)/$m; $midT[$wv[$i].u]=$(if($rr -ge (1.0/3) -and $rr -lt (2.0/3)){1}else{0}) }
  foreach($h in $sameH){
    $u=[int]$h.馬番
    if(-not $midT.ContainsKey($u)){ continue }
    $wkr=$(if($tou -gt 1){ ($u-1.0)/($tou-1.0) }else{ 0.5 })
    $ALL.Add([pscustomobject]@{ mid=$midT[$u]; wkr=$wkr })
  }
}
$alla=$ALL.ToArray()
Rep @($alla | Where-Object { $_.wkr -lt 0.20 }) '全馬 最内'
Rep @($alla | Where-Object { $_.wkr -ge 0.20 -and $_.wkr -lt 0.80 }) '全馬 中央帯'
Rep @($alla | Where-Object { $_.wkr -ge 0.80 }) '全馬 大外'
"`nDONE"
