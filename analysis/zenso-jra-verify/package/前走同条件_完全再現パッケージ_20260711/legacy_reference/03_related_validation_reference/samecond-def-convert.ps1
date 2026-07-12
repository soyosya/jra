# 転換組の検証: 「中団に変えてきそうな馬」の中団転換率
# 母集団: 同条件60%レースの同条件組のうち、現在の持ち味が中団でない馬(3走平均3角率がメンバー内の前1/3 or 後1/3)
# H-A 乗替転換: 騎手乗り替わりで中団転換率が上がるか(前すぎ/後すぎ別)
# H-B 適所ミスマッチ: 過去3走に中団帯で走った回があり、その回の着順率が非中団回より良い馬は中団に戻るか
# H-C 失敗修正: 前走前めで失速(着順5+)→下げる率 / 前走後方で凡走→上げる率
# 物差し: 今走3角メンバー内中位1/3(=中団勢定義の再現率と同じ・無情報33%)
param([string]$Base='C:\keiba\analysis\samecond_mid_base5.csv',[double]$SameTh=0.60)
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
  # 3走平均3角率のメンバー内位置(前1/3=F/中位=M/後1/3=B)
  $wm=@($sameH | Where-Object { $_.a3_3 -ne '' } | ForEach-Object { [pscustomobject]@{h=$_; u=[int]$_.馬番; v=[double]$_.a3_3} } | Sort-Object v,u)
  $nm=$wm.Count; if($nm -lt 5){ continue }
  for($i=0;$i -lt $nm;$i++){
    $rr=($i+0.5)/$nm
    $pos=$(if($rr -lt (1.0/3)){'F'}elseif($rr -lt (2.0/3)){'M'}else{'B'})
    $h=$wm[$i].h; $u=$wm[$i].u
    if(-not $midT.ContainsKey($u)){ continue }
    # 過去3走の明細: 各走の(3角率, 着順率)
    $runs=@()
    $p3=Num $h.p3r
    $pf=$(if($h.前走着順 -eq ''){$null}else{[double]$h.前走着順})
    $ptou=$(if($h.前走頭数 -eq ''){$null}else{[double]$h.前走頭数})
    if($null -ne $p3 -and $null -ne $pf -and $null -ne $ptou -and $ptou -gt 1){ $runs+=,@($p3,(($pf-1.0)/($ptou-1.0))) }
    $r32=Num $h.r3_2; $fr2=Num $h.fr_2
    if($null -ne $r32 -and $null -ne $fr2){ $runs+=,@($r32,$fr2) }
    $r33=Num $h.r3_3; $fr3=Num $h.fr_3
    if($null -ne $r33 -and $null -ne $fr3){ $runs+=,@($r33,$fr3) }
    # 適所ミスマッチ: 中団帯の回とそれ以外の回が両方あり、中団回の平均着順率が0.10以上良い
    $midRuns=@($runs | Where-Object { $_[0] -ge 0.30 -and $_[0] -le 0.70 })
    $othRuns=@($runs | Where-Object { $_[0] -lt 0.30 -or $_[0] -gt 0.70 })
    $mismatch=0
    if($midRuns.Count -ge 1 -and $othRuns.Count -ge 1){
      $mAvg=($midRuns | ForEach-Object { $_[1] } | Measure-Object -Average).Average
      $oAvg=($othRuns | ForEach-Object { $_[1] } | Measure-Object -Average).Average
      if(($oAvg-$mAvg) -ge 0.10){ $mismatch=1 }
    }
    # 乗替
    $tj=$h.今走騎手; $pj=$h.前走騎手
    $switch=$(if($tj -ne '' -and $pj -ne ''){ if($tj -ne $pj){1}else{0} }else{ $null })
    $REC.Add([pscustomobject]@{
      y=$h.開催日.Substring(0,4); cell="$($h.開催場所)$($h.距離)"
      pos=$pos; mid=$midT[$u]
      p3=$p3; pf=$pf
      mismatch=$mismatch; nRuns=$runs.Count; sw=$switch
    })
  }
}
$arr=$REC.ToArray()
Write-Host ("対象馬 {0}" -f $arr.Count)

function Rep([object[]]$s,[string]$label){
  $x=@($s); $n=$x.Count; if($n -eq 0){ return ('  {0,-52} n=0' -f $label) }
  $mid=@($x | Where-Object { $_.mid -eq 1 }).Count
  '  {0,-52} n={1,6} 中団転換率={2,6:P1} lift={3:N2}' -f $label,$n,($mid/[double]$n),(($mid/[double]$n)/(1.0/3))
}

"`n===== [0] ベースライン: 持ち味ポジション別の今走中団率 ====="
Rep @($arr | Where-Object { $_.pos -eq 'F' }) '前寄り1/3(持ち味が前)'
Rep @($arr | Where-Object { $_.pos -eq 'M' }) '中位1/3(参考=A3-REL)'
Rep @($arr | Where-Object { $_.pos -eq 'B' }) '後寄り1/3(持ち味が後ろ)'

"`n===== [H-A] 乗替転換: 非中団馬×騎手乗り替わり ====="
foreach($p in @('F','B')){
  $g=@($arr | Where-Object { $_.pos -eq $p -and $null -ne $_.sw })
  $lbl=$(if($p -eq 'F'){'前寄り'}else{'後寄り'})
  Rep @($g | Where-Object { $_.sw -eq 1 }) "$lbl × 乗り替わり"
  Rep @($g | Where-Object { $_.sw -eq 0 }) "$lbl × 継続騎乗"
}

"`n===== [H-B] 適所ミスマッチ: 中団で走った回だけ着順が良い(差0.10+)×現在非中団 ====="
foreach($p in @('F','B')){
  $g=@($arr | Where-Object { $_.pos -eq $p -and $_.nRuns -ge 2 })
  $lbl=$(if($p -eq 'F'){'前寄り'}else{'後寄り'})
  Rep @($g | Where-Object { $_.mismatch -eq 1 }) "$lbl × 中団適所ミスマッチあり"
  Rep @($g | Where-Object { $_.mismatch -eq 0 }) "$lbl × ミスマッチなし"
}
"-- ミスマッチ×乗替の合成 --"
foreach($p in @('F','B')){
  $lbl=$(if($p -eq 'F'){'前寄り'}else{'後寄り'})
  Rep @($arr | Where-Object { $_.pos -eq $p -and $_.mismatch -eq 1 -and $_.sw -eq 1 }) "$lbl × ミスマッチ × 乗替"
}

"`n===== [H-C] 失敗修正: 前走の位置×凡走 → 今走中団へ寄せる率 ====="
$fFail=@($arr | Where-Object { $_.pos -eq 'F' -and $null -ne $_.p3 -and $_.p3 -lt 0.30 -and $null -ne $_.pf -and $_.pf -ge 5 })
$fOk  =@($arr | Where-Object { $_.pos -eq 'F' -and $null -ne $_.p3 -and $_.p3 -lt 0.30 -and $null -ne $_.pf -and $_.pf -le 3 })
Rep $fFail '前寄り×前走も前(3角<0.30)×前走5着以下(失敗)'
Rep $fOk   '前寄り×前走も前×前走3着内(成功=変える理由なし)'
$bFail=@($arr | Where-Object { $_.pos -eq 'B' -and $null -ne $_.p3 -and $_.p3 -gt 0.70 -and $null -ne $_.pf -and $_.pf -ge 5 })
$bOk  =@($arr | Where-Object { $_.pos -eq 'B' -and $null -ne $_.p3 -and $_.p3 -gt 0.70 -and $null -ne $_.pf -and $_.pf -le 3 })
Rep $bFail '後寄り×前走も後(3角>0.70)×前走5着以下(失敗)'
Rep $bOk   '後寄り×前走も後×前走3着内(成功=変える理由なし)'
"-- 失敗×乗替の合成 --"
Rep @($fFail | Where-Object { $_.sw -eq 1 }) '前寄り失敗 × 乗替'
Rep @($bFail | Where-Object { $_.sw -eq 1 }) '後寄り失敗 × 乗替'

"`n===== [H-B'] 年別: 最有望群があれば頑健性確認(前寄り×ミスマッチ) ====="
$bestF=@($arr | Where-Object { $_.pos -eq 'F' -and $_.mismatch -eq 1 })
foreach($yy in @('2022','2023','2024','2025','2026')){ Rep @($bestF | Where-Object { $_.y -eq $yy }) ("  前寄りMM $yy") }
$bestB=@($arr | Where-Object { $_.pos -eq 'B' -and $_.mismatch -eq 1 })
foreach($yy in @('2022','2023','2024','2025','2026')){ Rep @($bestB | Where-Object { $_.y -eq $yy }) ("  後寄りMM $yy") }
"`nDONE"
