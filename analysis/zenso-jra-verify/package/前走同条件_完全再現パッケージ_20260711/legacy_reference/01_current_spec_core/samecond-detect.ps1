# 中団勢 検出(正準・単一実装): 前走同条件60%レース×確定中団勢定義×有力馬シグナル
#   中団勢 = 直近3走平均3角率が同条件組メンバー内中位1/3 ∧ 前走1・2・3角すべて0.30-0.70 ∧ 今走馬番相対<0.80
#   有力馬 = S: 同条件組時計1位∧進出∧維持(BT n=408 勝率24%/複率61%/Δ複+13.2pt全年+・回収<100%=確度専用)
#            A: 同条件組時計1位のみ(n=1200 複率55%/Δ+11.0pt)
#   検証: analysis/samecond-sweep.ps1 / samecond-def-{verify,sustain,waku}.ps1 (2026-07-10)
#   注意: 1-2角通過の無い場(盛岡/門別/大井1200等)はS1持続判定不可=検出対象外(自動で外れる)
# 呼び出し元: compi-today-blend.ps1(-UseSameCond時のprefetch・表示のみ)
# 出力: PSCustomObject { venue; race; rate; mids; pick_u; tier } (中団勢が居るレースのみ)
param([string]$Date=(Get-Date).ToString('yyyy-MM-dd'),[string]$Venue='')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'keiba-common.ps1')
$cn=New-Object System.Data.SqlClient.SqlConnection (Get-KeibaConnString); $cn.Open()
$cmd=$cn.CreateCommand(); $cmd.CommandTimeout=300
$cmd.CommandText=@"
WITH cell AS (   -- 検証済み20セル(analysis/samecond-sweep.ps1と同一・拡張時はBT必須)
  SELECT v, d FROM (VALUES
    (N'園田',1400),(N'佐賀',1400),(N'笠松',1400),(N'名古屋',1500),(N'名古屋',1400),(N'金沢',1400),(N'金沢',1500),
    (N'高知',1300),(N'高知',1400),(N'高知',1600),(N'水沢',1400),(N'大井',1200),(N'大井',1600),(N'門別',1000),(N'門別',1200),
    (N'船橋',1200),(N'浦和',1400),(N'川崎',1400),(N'盛岡',1400),(N'佐賀',1300)) t(v,d)
),
ent AS (
  SELECT ri.開催場所 v, ri.レース番号 r, ri.馬番 u, ri.馬名 nm, ri.血統登録番号 lid, ri.距離 dist,
         COUNT(*) OVER(PARTITION BY ri.開催場所, ri.レース番号) tou
  FROM dbo.レース情報 ri
  JOIN cell ce ON ce.v=ri.開催場所 AND ce.d=ri.距離
  WHERE ri.開催日=@d AND (@v=N'' OR ri.開催場所=@v)
),
h3 AS (
  SELECT * FROM (
    SELECT e.v, e.r, e.u, e.dist, e.tou,
           vv.開催場所 pv, vv.距離 pdist, vv.着順 pf, vv.走破時計 pt, vv.頭数 ptou,
           CASE WHEN vv.頭数>1 AND vv.一コーナー>0 THEN (vv.一コーナー-1.0)/(vv.頭数-1.0) END pr1,
           CASE WHEN vv.頭数>1 AND vv.二コーナー>0 THEN (vv.二コーナー-1.0)/(vv.頭数-1.0) END pr2,
           CASE WHEN vv.頭数>1 AND vv.三コーナー>0 THEN (vv.三コーナー-1.0)/(vv.頭数-1.0) END pr3,
           CASE WHEN vv.頭数>1 AND vv.四コーナー>0 THEN (vv.四コーナー-1.0)/(vv.頭数-1.0) END pr4,
           ROW_NUMBER() OVER(PARTITION BY e.v, e.r, e.u ORDER BY vv.開催日 DESC, vv.レース番号 DESC) rn
    FROM ent e
    JOIN dbo.vw_競走結果統合 vv
      ON vv.馬名=e.nm AND vv.開催日<@d AND vv.着順>0 AND vv.開催場所<>N'帯広ば'
     AND (e.lid IS NULL OR vv.血統登録番号 IS NULL OR vv.血統登録番号=e.lid)
  ) x WHERE rn<=3
)
SELECT e.v, e.r, e.u, e.tou, e.dist,
       h.rn, h.pv, h.pdist, h.pf, h.pt, h.ptou, h.pr1, h.pr2, h.pr3, h.pr4
FROM ent e
LEFT JOIN h3 h ON h.v=e.v AND h.r=e.r AND h.u=e.u
ORDER BY e.v, e.r, e.u, h.rn
"@
[void]$cmd.Parameters.AddWithValue('@d',$Date)
[void]$cmd.Parameters.AddWithValue('@v',$Venue)
$dt=New-Object System.Data.DataTable
(New-Object System.Data.SqlClient.SqlDataAdapter $cmd).Fill($dt)|Out-Null
$cn.Close()

function NVal($x){ if($x -is [DBNull] -or $null -eq $x){ $null } else { [double]$x } }
$out=New-Object System.Collections.Generic.List[object]
foreach($rg in ($dt.Rows | Group-Object v,r)){
  $venueN=[string]$rg.Group[0].v; $rno=[int]$rg.Group[0].r
  $tou=[int]$rg.Group[0].tou; $dist=[int]$rg.Group[0].dist
  if($tou -lt 5){ continue }
  # 馬ごとに直近3走を集約
  $horses=@{}
  foreach($ug in ($rg.Group | Group-Object u)){
    $u=[int]$ug.Group[0].u
    $h=@{u=$u; same=0; p1=$null;p2=$null;p3=$null;p4=$null; pt=$null; pf=$null; ptou=$null; a3s=@(); a4s=@()}
    foreach($row in ($ug.Group | Sort-Object {if($_.rn -is [DBNull]){99}else{[int]$_.rn}})){
      if($row.rn -is [DBNull]){ continue }
      $rn=[int]$row.rn
      $q3=NVal $row.pr3; $q4=NVal $row.pr4
      if($null -ne $q3){ $h.a3s+=$q3 }
      if($null -ne $q4){ $h.a4s+=$q4 }
      if($rn -eq 1){
        if(([string]$row.pv) -eq $venueN -and -not ($row.pdist -is [DBNull]) -and [int]$row.pdist -eq $dist){ $h.same=1 }
        $h.p1=NVal $row.pr1; $h.p2=NVal $row.pr2; $h.p3=$q3; $h.p4=$q4
        $h.pt=NVal $row.pt; $h.pf=NVal $row.pf; $h.ptou=NVal $row.ptou
      }
    }
    $horses[$u]=$h
  }
  $sameH=@($horses.Values | Where-Object { $_.same -eq 1 })
  if(($sameH.Count/[double]$tou) -lt 0.60){ continue }
  # A3相対(同条件組)
  $wm=@($sameH | Where-Object { $_.a3s.Count -ge 1 } | ForEach-Object { [pscustomobject]@{h=$_; u=$_.u; a3=(($_.a3s | Measure-Object -Average).Average)} } | Sort-Object a3,u)
  $nm=$wm.Count; if($nm -lt 5){ continue }
  # 時計1位(同条件組)
  $withT=@($sameH | Where-Object { $null -ne $_.pt -and $_.pt -gt 0 } | Sort-Object pt,u)
  $t1u=$(if($withT.Count -ge 1){ [int]$withT[0].u }else{ -1 })
  $mids=New-Object System.Collections.Generic.List[object]
  for($i=0;$i -lt $nm;$i++){
    $rr=($i+0.5)/$nm
    if(-not ($rr -ge (1.0/3) -and $rr -lt (2.0/3))){ continue }
    $h=$wm[$i].h
    if($null -eq $h.p1 -or $null -eq $h.p2 -or $null -eq $h.p3){ continue }
    if(-not ($h.p1 -ge 0.30 -and $h.p1 -le 0.70 -and $h.p2 -ge 0.30 -and $h.p2 -le 0.70 -and $h.p3 -ge 0.30 -and $h.p3 -le 0.70)){ continue }
    $wkr=$(if($tou -gt 1){ ([double]$h.u-1.0)/($tou-1.0) }else{ 0.5 })
    if($wkr -ge 0.80){ continue }
    $mids.Add([pscustomobject]@{u=$h.u; a3=$wm[$i].a3; h=$h})
  }
  if($mids.Count -eq 0){ continue }
  # 有力馬: S=時計1位∧進出∧維持 / A=時計1位のみ
  $pickU=''; $tier=''
  foreach($mo in ($mids.ToArray() | Sort-Object a3,u)){
    if([int]$mo.u -ne $t1u){ continue }
    $h=$mo.h
    $tier='A'
    if($h.a3s.Count -ge 1 -and $h.a4s.Count -ge 1 -and $null -ne $h.p4 -and $null -ne $h.pf -and $null -ne $h.ptou -and $h.ptou -gt 1){
      $a3v=($h.a3s | Measure-Object -Average).Average
      $a4v=($h.a4s | Measure-Object -Average).Average
      $fr1=($h.pf-1.0)/($h.ptou-1.0)
      if(($a3v-$a4v) -gt 0 -and ($h.p3-$h.p4) -gt 0 -and $fr1 -lt $h.p4){ $tier='S' }
    }
    $pickU=[int]$mo.u
    break
  }
  $rate=$sameH.Count/[double]$tou
  $out.Add([pscustomobject]@{
    venue=$venueN; race=$rno; rate=[math]::Round($rate,3)
    mids=(($mids.ToArray() | Sort-Object u | ForEach-Object { $_.u }) -join ',')
    pick_u=$pickU; tier=$tier
  })
}
$out.ToArray()
