# 騎手プロファイル×中団勢: 「中団で乗るタイプの騎手」で再現率が上がるか
# プロファイル期間2022-2024で騎手ごとの中団率(騎乗が今走3角メンバー内中位1/3に入る率)を計測
# テスト期間2025-2026(OOS)で: 中団勢定義(A3-REL∧S1持続∧非大外)×騎手タイプ別の再現率
# 併せて: 非中団馬×中団型騎手への乗替(転換の精密版)
param([string]$Base='C:\keiba\analysis\samecond_mid_base5.csv',[double]$SameTh=0.60)
[Console]::OutputEncoding=[System.Text.Encoding]::UTF8
$ErrorActionPreference='Stop'
$rows=Import-Csv $Base -Encoding UTF8
Write-Host ("ロード {0}行" -f $rows.Count)
function Num($x){ if($x -eq '' -or $null -eq $x){ $null } else { [double]$x } }

# ---- パス1: 全馬の今走中団フラグ(レース内ランク)を作りつつ、対象馬リスト構築 ----
$ALL=New-Object System.Collections.Generic.List[object]
foreach($grp in ($rows | Group-Object { "$($_.開催日)|$($_.開催場所)|$($_.レース番号)" })){
  $hs=@($grp.Group)
  $tou=[int]$hs[0].頭数
  $sameH=@($hs | Where-Object { $_.same -eq '1' })
  $isTarget=(($sameH.Count/[double]$tou) -ge $SameTh)
  $wv=@($hs | Where-Object { $_.t3 -ne '' } | ForEach-Object { [pscustomobject]@{u=[int]$_.馬番; v=[double]$_.t3} } | Sort-Object v,u)
  $m=$wv.Count; if($m -lt 5){ continue }
  $midT=@{}
  for($i=0;$i -lt $m;$i++){ $rr=($i+0.5)/$m; $midT[$wv[$i].u]=$(if($rr -ge (1.0/3) -and $rr -lt (2.0/3)){1}else{0}) }
  # A3-RELランク(同条件組・対象レースのみ)
  $posMap=@{}
  if($isTarget){
    $wm=@($sameH | Where-Object { $_.a3_3 -ne '' } | ForEach-Object { [pscustomobject]@{u=[int]$_.馬番; v=[double]$_.a3_3} } | Sort-Object v,u)
    $nm=$wm.Count
    if($nm -ge 5){
      for($i=0;$i -lt $nm;$i++){
        $rr=($i+0.5)/$nm
        $posMap[$wm[$i].u]=$(if($rr -lt (1.0/3)){'F'}elseif($rr -lt (2.0/3)){'M'}else{'B'})
      }
    }
  }
  foreach($h in $hs){
    $u=[int]$h.馬番
    if(-not $midT.ContainsKey($u)){ continue }
    $r1=Num $h.p1r; $r2=Num $h.p2r; $r3=Num $h.p3r
    $s1ok=$(if($null -ne $r1 -and $null -ne $r2 -and $null -ne $r3 -and $r1 -ge 0.30 -and $r1 -le 0.70 -and $r2 -ge 0.30 -and $r2 -le 0.70 -and $r3 -ge 0.30 -and $r3 -le 0.70){1}else{0})
    $wkr=$(if($tou -gt 1){ ([double]$u-1.0)/($tou-1.0) }else{ 0.5 })
    $ALL.Add([pscustomobject]@{
      d=$h.開催日; y=$h.開催日.Substring(0,4); v=$h.開催場所
      j=$h.今走騎手; pj=$h.前走騎手; mid=$midT[$u]
      pos=$(if($posMap.ContainsKey($u)){$posMap[$u]}else{''})
      s1=$s1ok; wkr=$wkr; tgt=$(if($isTarget){1}else{0})
    })
  }
}
$alla=$ALL.ToArray()
Write-Host ("全馬(中団フラグ付) {0}" -f $alla.Count)

# ---- 騎手プロファイル(2022-2024・場別・最低100騎乗) ----
$prof=@{}
foreach($x in $alla){
  if($x.y -gt '2024'){ continue }
  if($x.j -eq ''){ continue }
  $k="$($x.v)|$($x.j)"
  if(-not $prof.ContainsKey($k)){ $prof[$k]=@{n=0;m=0} }
  $prof[$k].n++; if($x.mid -eq 1){ $prof[$k].m++ }
}
$JT=@{}   # 騎手タイプ: H(中団型)/L(非中団型)/-(データ不足)
$rates=New-Object System.Collections.Generic.List[double]
foreach($k in $prof.Keys){ if($prof[$k].n -ge 100){ $rates.Add($prof[$k].m/[double]$prof[$k].n) } }
$sorted=@($rates | Sort-Object)
$q1=$sorted[[int]($sorted.Count*0.25)]; $q3=$sorted[[int]($sorted.Count*0.75)]
Write-Host ("騎手×場プロファイル {0}件(n>=100) 中団率 Q1={1:P1} Q3={2:P1}" -f $sorted.Count,$q1,$q3)
foreach($k in $prof.Keys){
  if($prof[$k].n -lt 100){ continue }
  $r=$prof[$k].m/[double]$prof[$k].n
  $JT[$k]=$(if($r -ge $q3){'H'}elseif($r -le $q1){'L'}else{'N'})
}

function Rep([object[]]$s,[string]$label){
  $x=@($s); $n=$x.Count; if($n -eq 0){ return ('  {0,-52} n=0' -f $label) }
  $mid=@($x | Where-Object { $_.mid -eq 1 }).Count
  '  {0,-52} n={1,6} 中団率={2,6:P1} lift={3:N2}' -f $label,$n,($mid/[double]$n),(($mid/[double]$n)/(1.0/3))
}

# ---- OOS(2025-2026): 中団勢定義×騎手タイプ ----
$oos=@($alla | Where-Object { $_.y -ge '2025' -and $_.tgt -eq 1 })
$def=@($oos | Where-Object { $_.pos -eq 'M' -and $_.s1 -eq 1 -and $_.wkr -lt 0.80 })
"`n===== [1] OOS 2025-2026: 中団勢定義(A3-REL∧S1∧非大外)×今走騎手タイプ ====="
Rep $def '定義該当 全体(OOS)'
Rep @($def | Where-Object { $JT["$($_.v)|$($_.j)"] -eq 'H' }) ' × 中団型騎手(場別上位25%)'
Rep @($def | Where-Object { $JT["$($_.v)|$($_.j)"] -eq 'N' }) ' × 中間騎手'
Rep @($def | Where-Object { $JT["$($_.v)|$($_.j)"] -eq 'L' }) ' × 非中団型騎手(下位25%)'
Rep @($def | Where-Object { -not $JT.ContainsKey("$($_.v)|$($_.j)") }) ' × プロファイル無し(騎乗数不足)'

"`n===== [2] OOS: 非中団馬(前寄り/後寄り)×中団型騎手への乗替(転換の精密版) ====="
foreach($p in @('F','B')){
  $lbl=$(if($p -eq 'F'){'前寄り'}else{'後寄り'})
  $g=@($oos | Where-Object { $_.pos -eq $p })
  Rep @($g | Where-Object { $_.j -ne '' -and $_.pj -ne '' -and $_.j -ne $_.pj -and $JT["$($_.v)|$($_.j)"] -eq 'H' }) "$lbl × 中団型騎手へ乗替"
  Rep @($g | Where-Object { $_.j -ne '' -and $_.pj -ne '' -and $_.j -ne $_.pj -and $JT["$($_.v)|$($_.j)"] -eq 'L' }) "$lbl × 非中団型騎手へ乗替"
}

"`n===== [3] 交絡チェック: 騎手タイプは馬の持ち味と独立か(OOS・定義外含む全馬) ====="
Rep @($oos | Where-Object { $JT["$($_.v)|$($_.j)"] -eq 'H' }) '全馬 × 中団型騎手'
Rep @($oos | Where-Object { $JT["$($_.v)|$($_.j)"] -eq 'L' }) '全馬 × 非中団型騎手'
"`nDONE"
