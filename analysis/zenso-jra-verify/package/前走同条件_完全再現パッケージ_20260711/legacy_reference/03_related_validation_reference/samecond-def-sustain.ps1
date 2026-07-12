# 持続中団の検証: 1-3角の通過系列で「真の中団」を判定
# 仮説1(汚染): 3角中団のうち 下げ組(先行→3角で下げ)/まくり組(後方→3角で前進) は再現率が低い
# 仮説2(持続): 前走1・2・3角すべて0.30-0.70=持続中団 は再現率が高い
# 再現率 = 今走3角のメンバー内中位1/3(従来と同一物差し・無情報33%)
param([string]$Base='C:\keiba\analysis\samecond_mid_base3.csv',[double]$SameTh=0.60)
[Console]::OutputEncoding=[System.Text.Encoding]::UTF8
$ErrorActionPreference='Stop'
$rows=Import-Csv $Base -Encoding UTF8
Write-Host ("ロード {0}行" -f $rows.Count)

function Num($x){ if($x -eq '' -or $null -eq $x){ $null } else { [double]$x } }

$REC=New-Object System.Collections.Generic.List[object]
$raceCnt=0
foreach($grp in ($rows | Group-Object { "$($_.開催日)|$($_.開催場所)|$($_.レース番号)" })){
  $hs=@($grp.Group)
  $tou=[int]$hs[0].頭数
  $sameH=@($hs | Where-Object { $_.same -eq '1' })
  if(($sameH.Count/[double]$tou) -lt $SameTh){ continue }
  $raceCnt++

  # 今走3角: 全馬ランク→中位1/3
  $wv=@($hs | Where-Object { $_.t3 -ne '' } | ForEach-Object { [pscustomobject]@{u=[int]$_.馬番; v=[double]$_.t3} } | Sort-Object v,u)
  $m=$wv.Count; if($m -lt 5){ continue }
  $midT=@{}
  for($i=0;$i -lt $m;$i++){ $rr=($i+0.5)/$m; $midT[$wv[$i].u]=$(if($rr -ge (1.0/3) -and $rr -lt (2.0/3)){1}else{0}) }

  foreach($h in $sameH){
    $u=[int]$h.馬番
    if(-not $midT.ContainsKey($u)){ continue }
    $r1=Num $h.p1r; $r2=Num $h.p2r; $r3=Num $h.p3r
    if($null -eq $r3){ continue }
    $a3=Num $h.a3_3
    $REC.Add([pscustomobject]@{
      y=$h.開催日.Substring(0,4); cell="$($h.開催場所)$($h.距離)"
      u=$u; mid=$midT[$u]; r1=$r1; r2=$r2; r3=$r3; a3=$a3
      hasSeq=$(if($null -ne $r1 -and $null -ne $r2){1}else{0})
      race=$grp.Name
    })
  }
}
$arr=$REC.ToArray()
Write-Host ("対象レース {0} / 対象馬 {1} (前走3角あり)" -f $raceCnt,$arr.Count)
$seqOK=@($arr | Where-Object { $_.hasSeq -eq 1 })
Write-Host ("うち1-2角系列あり {0} ({1:P0})" -f $seqOK.Count,($seqOK.Count/[double]$arr.Count))

function Rep([object[]]$s,[string]$label){
  $x=@($s); $n=$x.Count; if($n -eq 0){ return ('  {0,-46} n=0' -f $label) }
  $mid=@($x | Where-Object { $_.mid -eq 1 }).Count
  '  {0,-46} n={1,6} 再現率={2,6:P1} lift={3:N2}' -f $label,$n,($mid/[double]$n),(($mid/[double]$n)/(1.0/3))
}

"`n===== [1] 汚染仮説: 前走3角中団(0.30-0.70)を通過系列で分解 ====="
$p3mid=@($seqOK | Where-Object { $_.r3 -ge 0.30 -and $_.r3 -le 0.70 })
Rep $p3mid '3角中団 全体(=P3-ABS・系列あり分)'
Rep @($p3mid | Where-Object { $_.r1 -ge 0.30 -and $_.r1 -le 0.70 -and $_.r2 -ge 0.30 -and $_.r2 -le 0.70 }) ' └ 持続組: 1角も2角も中団帯'
Rep @($p3mid | Where-Object { $_.r1 -lt 0.30 }) ' └ 下げ組: 1角先行帯→3角中団(1-1-3型)'
Rep @($p3mid | Where-Object { $_.r1 -gt 0.70 }) ' └ まくり/押上げ組: 1角後方帯→3角中団(8-8-3型)'

"`n===== [2] 持続中団の定義候補 ====="
Rep @($seqOK | Where-Object { $_.r1 -ge 0.30 -and $_.r1 -le 0.70 -and $_.r2 -ge 0.30 -and $_.r2 -le 0.70 -and $_.r3 -ge 0.30 -and $_.r3 -le 0.70 }) 'S1: 前走1・2・3角すべて0.30-0.70'
# S2: 平均が帯内かつ振れ小(位置持続)
$s2=@($seqOK | Where-Object {
  $mn=[math]::Min([math]::Min($_.r1,$_.r2),$_.r3); $mx=[math]::Max([math]::Max($_.r1,$_.r2),$_.r3)
  $av=($_.r1+$_.r2+$_.r3)/3.0
  $av -ge 0.30 -and $av -le 0.70 -and ($mx-$mn) -le 0.20 })
Rep $s2 'S2: 1-3角平均が帯内∧振れ(max-min)≤0.20'

"`n===== [3] 3走平均との合成(前回勝者A3-RELの強化) ====="
# A3-REL相当: レース内で a3 を順位化して中位1/3
$byRace=@{}
foreach($g in ($seqOK | Group-Object race)){
  $wm=@($g.Group | Where-Object { $null -ne $_.a3 } | Sort-Object a3,u)
  $nm=$wm.Count; if($nm -lt 5){ continue }
  for($i=0;$i -lt $nm;$i++){ $rr=($i+0.5)/$nm; if($rr -ge (1.0/3) -and $rr -lt (2.0/3)){ $byRace["$($g.Name)|$($wm[$i].u)"]=1 } }
}
$a3rel=@($seqOK | Where-Object { $byRace.ContainsKey("$($_.race)|$($_.u)") })
Rep $a3rel 'A3-REL(系列あり分・参照)'
Rep @($a3rel | Where-Object { $_.r1 -ge 0.30 -and $_.r1 -le 0.70 -and $_.r2 -ge 0.30 -and $_.r2 -le 0.70 -and $_.r3 -ge 0.30 -and $_.r3 -le 0.70 }) 'A3-REL ∧ S1持続(前走1-3角すべて帯内)'
Rep @($a3rel | Where-Object { -not ($_.r1 -lt 0.30 -or $_.r1 -gt 0.70) }) 'A3-REL ∧ 前走1角も帯内(2角不問)'

"`n===== [4] S1持続中団: 年別 ====="
$s1=@($seqOK | Where-Object { $_.r1 -ge 0.30 -and $_.r1 -le 0.70 -and $_.r2 -ge 0.30 -and $_.r2 -le 0.70 -and $_.r3 -ge 0.30 -and $_.r3 -le 0.70 })
foreach($yy in @('2022','2023','2024','2025','2026')){ Rep @($s1 | Where-Object { $_.y -eq $yy }) ("  $yy") }

"`n===== [5] S1持続中団: セル別(n≥300・カバー率注意) ====="
foreach($cg in ($s1 | Group-Object cell | Where-Object { $_.Count -ge 300 } | Sort-Object Name)){ Rep $cg.Group ("  "+$cg.Name) }

"`n===== [6] 参考: 系列カバー率(セル別・前走1-2角の有無) ====="
foreach($cg in ($arr | Group-Object cell | Sort-Object Name)){
  $c=@($cg.Group | Where-Object { $_.hasSeq -eq 1 }).Count
  '  {0,-12} 系列あり {1,6}/{2,6} ({3:P0})' -f $cg.Name,$c,$cg.Count,($c/[double]$cg.Count)
}
"`nDONE"

"`n===== [7] 勝者コンボ: A3-REL ∧ S1持続 の年別/セル別 ====="
$combo=@($a3rel | Where-Object { $_.r1 -ge 0.30 -and $_.r1 -le 0.70 -and $_.r2 -ge 0.30 -and $_.r2 -le 0.70 -and $_.r3 -ge 0.30 -and $_.r3 -le 0.70 })
foreach($yy in @('2022','2023','2024','2025','2026')){ Rep @($combo | Where-Object { $_.y -eq $yy }) ("  $yy") }
"-- セル別(n≥200) --"
foreach($cg in ($combo | Group-Object cell | Where-Object { $_.Count -ge 200 } | Sort-Object Name)){ Rep $cg.Group ("  "+$cg.Name) }
"-- 選定頭数 --"
$perR=@($combo | Group-Object race | ForEach-Object { $_.Count })
$r0=@($a3rel | Group-Object race).Count
'  発火レース {0} / 対象20450 ({1:P0})  発火R内平均 {2:N2}頭' -f $perR.Count,($perR.Count/20450.0),(($perR | Measure-Object -Average).Average)
"DONE2"
