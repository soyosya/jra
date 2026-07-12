# relay-floor compi-boundary counterfactual BT.
# For 2025 summer 3-venue 456R, trifecta axis-nagashi (partners ExportN=5, C(5,2)=10 pts),
# compare floor boundary K=3(current)/5(proposed)/7 on hitrate and ROI.
# axis/eval/compi/sougou from cache json; top3 finish and trifecta payout from DB.
# NOTE: in-sample descriptive counterfactual (not OOS). Goal = quantify missed-cover reduction, not +EV.
$cs=(Get-Content 'C:\jra\共通\appsettings.json' -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
function Q($sql){ $cn=New-Object System.Data.SqlClient.SqlConnection $cs; $cn.Open(); $c=$cn.CreateCommand(); $c.CommandText=$sql; $dt=New-Object System.Data.DataTable; [void](New-Object System.Data.SqlClient.SqlDataAdapter $c).Fill($dt); $cn.Close(); ,$dt }
$dates=@('2025-07-26','2025-07-27','2025-08-02','2025-08-03','2025-08-09','2025-08-10','2025-08-16','2025-08-17','2025-08-23','2025-08-24','2025-08-30','2025-08-31','2025-09-06','2025-09-07')
$venues=@('新潟','中京','札幌')
$ExportN=5
$Ks=@(3,5,7)
$agg=@{}
foreach($k in $Ks){ $agg["$k"]=[ordered]@{R=0;hit=0;inv=0.0;pay=0.0} }
$negRe='危|不調|相悪|前敗|長休|種替|不適'
foreach($d in $dates){
  $ymd=($d -replace '-','')
  foreach($v in $venues){
    $cf="C:\temp\jra_reason_${ymd}_${v}.json"
    if(-not (Test-Path $cf)){ continue }
    $J=Get-Content $cf -Raw -Encoding UTF8 | ConvertFrom-Json
    $res=@{}
    foreach($x in (Q "SELECT レース番号 R,馬番,着順 FROM dbo.競走結果 WHERE 開催日='$d' AND 開催場所=N'$v' AND 着順 BETWEEN 1 AND 3").Rows){
      $rr="$($x.R)"; if(-not $res.ContainsKey($rr)){$res[$rr]=@{}}; $res[$rr]["$($x.馬番)"]=[int]$x.着順
    }
    $pay=@{}
    foreach($x in (Q "SELECT レース番号 R,組番,CAST(金額 AS int) 金額 FROM dbo.払戻金 WHERE 開催日='$d' AND 開催場所=N'$v' AND 馬券=N'三連複'").Rows){
      $rr="$($x.R)"
      $nums=@(($x.組番 -split '[^0-9]+') | Where-Object { $_ -ne '' } | ForEach-Object {[int]$_} | Sort-Object)
      $key=($nums -join '-')
      $pay[($rr+'#'+$key)]=[int]$x.金額
    }
    foreach($rp in $J.PSObject.Properties){
      $rr=$rp.Name; $race=$rp.Value
      $axis="$($race.axis)"
      if([string]::IsNullOrWhiteSpace($axis)){ continue }
      if(-not $res.ContainsKey($rr)){ continue }
      $top3=$res[$rr]
      if($top3.Count -lt 3){ continue }
      $cand=@()
      foreach($hp in $race.horses.PSObject.Properties){
        $uma=$hp.Name; $h=$hp.Value
        if("$uma" -eq "$axis"){ continue }
        if("$($h.eval)" -match '消|遠危|休消'){ continue }
        $so=$null; if("$($h.sougou)" -match '^-?[0-9]'){ $so=[double]$h.sougou }
        $co=$null; if("$($h.compi)" -match '^[0-9]+$'){ $co=[int]$h.compi }
        $isneg=$false; if("$($h.eval)" -match $negRe){ $isneg=$true }
        $cand+=[pscustomobject]@{uma=$uma;compi=$co;sougou=$so;neg=$isneg}
      }
      $sorted=@($cand | Sort-Object @{e={ if($null -eq $_.sougou){-999}else{-$_.sougou} }})
      foreach($k in $Ks){
        $picklist=@($sorted | Where-Object {
          $ok=(-not $_.neg)
          if(-not $ok){ if(($null -ne $_.compi -and $_.compi -le $k) -or ($null -ne $_.sougou -and $_.sougou -ge 0.6)){ $ok=$true } }
          $ok
        } | Select-Object -First $ExportN)
        $partners=@($picklist | ForEach-Object { "$($_.uma)" })
        if($partners.Count -lt 2){ continue }
        $a=$agg["$k"]; $a.R++
        $nP=$partners.Count
        $a.inv += ($nP*($nP-1)/2)*100
        $t3keys=@($top3.Keys)
        if($t3keys -contains "$axis"){
          $others=@($t3keys | Where-Object { "$_" -ne "$axis" })
          if($others.Count -eq 2 -and ($partners -contains "$($others[0])") -and ($partners -contains "$($others[1])")){
            $trio=@([int]$axis,[int]$others[0],[int]$others[1]) | Sort-Object
            $key=($trio -join '-')
            $amt=$pay[($rr+'#'+$key)]
            if($amt){ $a.hit++; $a.pay += $amt }
          }
        }
      }
    }
  }
}
Write-Output '=== relay-floor compi-boundary BT (2025 summer 3venues 456R, trifecta axis-nagashi) ==='
foreach($k in $Ks){
  $a=$agg["$k"]
  $hr=0.0; if($a.R -gt 0){ $hr=[math]::Round(100.0*$a.hit/$a.R,1) }
  $roi=0.0; if($a.inv -gt 0){ $roi=[math]::Round(100.0*$a.pay/$a.inv,1) }
  Write-Output ('floor_compi<=' + $k + '  R=' + $a.R + '  hit=' + $a.hit + '  hitrate=' + $hr + '%  inv=' + [int]$a.inv + '  pay=' + [int]$a.pay + '  roi=' + $roi + '%')
}
