# 相手戦略バックテスト: 従来 / フロア置換(現行) / フロア純追加(修正点1) / +コンピ中位(修正点2)
# 軸は共通(キャッシュのaxis)。障害・軸空・取消軸は除外。三連複軸1頭流し(C(N,2)点)・ワイド軸流し(N点)・軸複勝で的中率/回収率。
$cs=(Get-Content 'C:\jra\共通\appsettings.json' -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
function Q($sql){ $cn=New-Object System.Data.SqlClient.SqlConnection $cs; $cn.Open(); $c=$cn.CreateCommand(); $c.CommandText=$sql; $dt=New-Object System.Data.DataTable; [void](New-Object System.Data.SqlClient.SqlDataAdapter $c).Fill($dt); $cn.Close(); ,$dt }
$days=@(
 @('2025','小倉','2025-06-28','2025-06-29','2025-07-05','2025-07-06','2025-07-12','2025-07-13','2025-07-19','2025-07-20'),
 @('2025','函館','2025-07-05','2025-07-06','2025-07-12','2025-07-13','2025-07-19','2025-07-20'),
 @('2025','福島','2025-06-28','2025-06-29','2025-07-05','2025-07-06','2025-07-12','2025-07-13','2025-07-19','2025-07-20'),
 @('2026','函館','2026-06-13','2026-06-14','2026-06-20','2026-06-21','2026-06-27','2026-06-28','2026-07-04'),
 @('2026','福島','2026-06-27','2026-06-28','2026-07-04'),
 @('2026','小倉','2026-06-27','2026-06-28','2026-07-04')
)
$variants='V0従来','V1フロア置換','V2純追加','V3+中位'
# 集計器
$agg=@{}; foreach($grp in '2025','2026','ALL'){ foreach($vn in $variants){ $agg["$grp|$vn"]=[ordered]@{ R=0; tHit=0; tInv=0.0; tPay=0.0; wHit=0; wInv=0.0; wPay=0.0; fPay=0.0; fInv=0.0 } } }

function RelaySet($cand,$axis){
  # $cand: 配列(psobj: u,compi,sougou,eval)  総合降順ソート済み前提でない→ここでソート
  $sorted=@($cand | Sort-Object { -[double]$_.sougou })
  $isNeg={ param($e) "$e" -match '危|不調|相悪|前敗|長休|種替|不適' }
  $floor={ param($h) ("$($h.compi)" -match '^\d+$' -and [int]$h.compi -le 3) -or ([double]$h.sougou -ge 0.6) }
  $nonNeg=@($sorted | Where-Object { -not (& $isNeg $_.eval) })
  $flr   =@($sorted | Where-Object { (& $isNeg $_.eval) -and (& $floor $_) })
  # V0: 非ネガ上位5
  $v0=@($nonNeg | Select-Object -First 5 | ForEach-Object { $_.u })
  # V1 フロア置換: (非ネガ∪フロア)総合順 上位5 + 拡幅5
  $mix=@($sorted | Where-Object { (-not (& $isNeg $_.eval)) -or (& $floor $_) })
  $v1=@($mix | Select-Object -First 5 | ForEach-Object { $_.u })
  if($v1.Count -lt 5){ foreach($h in $sorted){ if($v1.Count -ge 5){break}; if($v1 -notcontains $h.u){ $v1+=$h.u } } }
  # V2 純追加: 非ネガ上位5 + フロア(重複除く) 上限7
  $v2=@($v0); foreach($h in $flr){ if($v2.Count -ge 7){break}; if($v2 -notcontains $h.u){ $v2+=$h.u } }
  # V3 = V2 + コ中位(非ネガ コ4-8) を上限9まで
  $v3=@($v2); $mid=@($sorted | Where-Object { (-not (& $isNeg $_.eval)) -and "$($_.compi)" -match '^\d+$' -and [int]$_.compi -ge 4 -and [int]$_.compi -le 8 } | Sort-Object { [int]$_.compi })
  foreach($h in $mid){ if($v3.Count -ge 9){break}; if($v3 -notcontains $h.u){ $v3+=$h.u } }
  return @{ V0従来=$v0; 'V1フロア置換'=$v1; V2純追加=$v2; 'V3+中位'=$v3 }
}

foreach($grp in $days){
  $yr=$grp[0]; $v=$grp[1]
  for($i=2;$i -lt $grp.Count;$i++){
    $d=$grp[$i]; $ymd=$d -replace '-',''
    $f="C:\temp\jra_reason_${ymd}_${v}.json"; if(-not(Test-Path $f)){ continue }
    $j=Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json
    # 結果top3, 払戻
    $res=@{}; foreach($x in (Q "SELECT レース番号 R,馬番,着順 FROM dbo.競走結果 WHERE 開催日='$d' AND 開催場所=N'$v' AND 着順 BETWEEN 1 AND 3").Rows){ if(-not $res.ContainsKey("$($x.R)")){$res["$($x.R)"]=@{}}; $res["$($x.R)"]["$($x.馬番)"]=[int]$x.着順 }
    $pay=Q "SELECT レース番号 R,馬券,組番,金額 FROM dbo.払戻金 WHERE 開催日='$d' AND 開催場所=N'$v'"
    foreach($rprop in $j.PSObject.Properties){
      $r=$rprop.Name; $rr=$rprop.Value; $ax="$($rr.axis)"; if($ax -eq ''){ continue }
      if(-not $res.ContainsKey($r)){ continue }
      $top3=$res[$r]; if($top3.Count -lt 3){ continue }   # 取消等でtop3揃わない場合スキップ
      # 障害除外(距離判定できないのでaxisLabに'障'含み or dist情報無→ここではスキップ条件無し。障害はキャッシュに軸が出る場合ありうるが稀)
      # 候補馬
      $cand=@(); foreach($up in $rr.horses.PSObject.Properties){ $u=$up.Name; if($u -eq $ax){continue}; $h=$up.Value; $e="$($h.eval)"; if($e -eq '消' -or $e -match '△遠|△休'){continue}; if($null -eq $h.sougou){continue}; $cand+=[pscustomobject]@{u=$u; compi=$h.compi; sougou=$h.sougou; eval=$e} }
      if($cand.Count -lt 2){ continue }
      $rel=RelaySet $cand $ax
      $axIn = $top3.ContainsKey($ax)
      # 払戻辞書
      $tri = @($pay.Rows | Where-Object { "$($_.R)" -eq $r -and $_.馬券 -eq '三連複' })
      $triPay = if($tri.Count){ [int]$tri[0].金額 }else{ 0 }
      $wide = @{}; foreach($w in ($pay.Rows | Where-Object { "$($_.R)" -eq $r -and $_.馬券 -eq 'ワイド' })){ $nums=@(([regex]::Matches("$($w.組番)",'\d+') | ForEach-Object { $_.Value })); if($nums.Count -eq 2){ $wide[($nums|Sort-Object)-join'-']=[int]$w.金額 } }
      $fuku=@{}; foreach($fp in ($pay.Rows | Where-Object { "$($_.R)" -eq $r -and $_.馬券 -eq '複勝' })){ $n=([regex]::Match("$($fp.組番)",'\d+')).Value; if($n){ $fuku[$n]=[int]$fp.金額 } }
      $othersTop3=@($top3.Keys | Where-Object { $_ -ne $ax })
      foreach($vn in $variants){
        $R=$rel[$vn]; $N=$R.Count; if($N -lt 2){ continue }
        $key2="$yr|$vn"; $keyA="ALL|$vn"
        foreach($k in @($key2,$keyA)){ $agg[$k].R++ }
        # 三連複軸1頭流し
        $ptsT=[int]($N*($N-1)/2); $invT=$ptsT*100
        $hitT = $axIn -and ($othersTop3.Count -eq 2) -and ($R -contains $othersTop3[0]) -and ($R -contains $othersTop3[1])
        foreach($k in @($key2,$keyA)){ $agg[$k].tInv+=$invT; if($hitT){ $agg[$k].tHit++; $agg[$k].tPay+=$triPay } }
        # ワイド軸流し(軸-相手 N点)。軸がtop3かつ相手がtop3→そのペア的中
        $invW=$N*100; $wpay=0; $whit=0
        if($axIn){ foreach($rp in $R){ if($top3.ContainsKey($rp)){ $pk=(@($ax,$rp)|Sort-Object)-join'-'; if($wide.ContainsKey($pk)){ $wpay+=$wide[$pk]; $whit=1 } } } }
        foreach($k in @($key2,$keyA)){ $agg[$k].wInv+=$invW; if($whit){ $agg[$k].wHit++; $agg[$k].wPay+=$wpay } }
        # 軸複勝(参考・変種非依存だが各変種行に同値計上)
        $fp= if($axIn -and $fuku.ContainsKey($ax)){ $fuku[$ax] }else{ 0 }
        foreach($k in @($key2,$keyA)){ $agg[$k].fInv+=100; $agg[$k].fPay+=$fp }
      }
    }
  }
}
# 出力
foreach($grp in '2025','2026','ALL'){
  Write-Output ""
  Write-Output ("========== $grp =========="); Write-Output ("変種            | R | 三複的中 投資 払戻 回収% | ワイド的中 回収% | 軸複回収%")
  foreach($vn in $variants){ $a=$agg["$grp|$vn"]; $tr= if($a.tInv){100*$a.tPay/$a.tInv}else{0}; $wr= if($a.wInv){100*$a.wPay/$a.wInv}else{0}; $fr= if($a.fInv){100*$a.fPay/$a.fInv}else{0}
    Write-Output ("{0,-14}| {1,4} | {2,4} {3,9:N0} {4,9:N0} {5,6:N1} | {6,4} {7,6:N1} | {8,6:N1}" -f $vn,$a.R,$a.tHit,$a.tInv,$a.tPay,$tr,$a.wHit,$wr,$fr) }
}
