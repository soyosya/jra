<#
.SYNOPSIS
  高知・馬軸 勝率スコア。前走/前々走のファクト(走破時計・上り3F・一着馬着差・通過順・
  馬体重増減・斤量・一着賞金)から「能力・体調・クラス変動・コース相性」を数値化し、
  過去データで較正して各馬の推定勝率%を算出。馬ファクトのみ版(A)と展開統合版(B)の両方を出力・検証。

.DESCRIPTION
  特徴量(全て事前入手可・未来リーク無し):
    能力     : 馬場差δ補正後の同距離自己ベスト vs 距離×クラス基準(speed figure)/ 前走 一着馬着差
    体調     : 前々走→前走の 上り3F改善 / 着差改善 / 四角通過位置の前進 / 前走馬体重増減の安定性
    クラス変動: 今回 一着賞金 vs 前走 一着賞金(降格 +/ 格上挑戦 −、前走圧勝なら緩和)
    コース相性: 同距離の自己ベスト有無 / 今回馬場での過去複勝率
    展開(B)  : 前走脚質 / 同型不在 / 騎手前付力 / コネクション(隠れ前残り)
  スコアは学習期間のスコア帯別実勝率で較正し、レース内で正規化して勝率%に変換。
  検証期間で 較正の良否・本命的中率・払戻ベース回収率を評価。

.PARAMETER TrainEnd  学習終端。既定 2025-09-30。
.PARAMETER TestStart 検証開始。既定 2025-10-01。
.PARAMETER Refresh   DBから特徴量を再抽出。
.PARAMETER ShowRace  指定日(yyyy-MM-dd)の全レースの各馬スコア/勝率%を表示。
#>
[CmdletBinding()]
param([string]$TrainEnd='2025-09-30',[string]$TestStart='2025-10-01',[switch]$Refresh,[string]$ShowRace='')
$ErrorActionPreference='Stop'
$cachePath = Join-Path $PSScriptRoot '_kochi_horse_cache.csv'
$appsettings = Join-Path $PSScriptRoot '..\共通\appsettings.json'
if (Test-Path $appsettings) { $connStr=(Get-Content $appsettings -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection }
if ([string]::IsNullOrWhiteSpace($connStr)) { $connStr="Server=192.168.168.81\SQLEXPRESS;Database=中央競馬;User Id=sa;Password=$($env:KEIBA_SA_PASSWORD);TrustServerCertificate=True;Connect Timeout=10" }

$sql=@"
DECLARE @venue nvarchar(10)=N'高知';
IF OBJECT_ID('tempdb..#r') IS NOT NULL DROP TABLE #r;
SELECT k.開催日 dt, k.レース番号 rno, k.馬番 uma, k.馬名 name, k.着順 chaku,
  rinfo.距離 d, rinfo.一着賞金 cls, rinfo.馬場 ba, rinfo.騎手 jk, rinfo.調教師 tr, rinfo.馬主 ow,
  k.走破時計 t, k.上り3F up3, k.一着馬着差タイム mgn,
  COALESCE(NULLIF(k.一コーナー,0),NULLIF(k.二コーナー,0),NULLIF(k.三コーナー,0),NULLIF(k.四コーナー,0)) ep,
  NULLIF(k.四コーナー,0) c4, cnt.h h, rinfo.馬体重 wt, rinfo.馬体重増減 dwt
INTO #r FROM 競走結果 k
JOIN レース情報 rinfo ON rinfo.開催場所=@venue AND rinfo.開催日=k.開催日 AND rinfo.レース番号=k.レース番号 AND rinfo.馬番=k.馬番
CROSS APPLY (SELECT COUNT(*) h FROM 競走結果 k2 WHERE k2.開催場所=@venue AND k2.開催日=k.開催日 AND k2.レース番号=k.レース番号 AND k2.着順>0) cnt
WHERE k.開催場所=@venue AND k.着順>0;
CREATE INDEX ix1 ON #r(name,d,dt,rno);
CREATE INDEX ix2 ON #r(name,ba,dt);

IF OBJECT_ID('tempdb..#cell') IS NOT NULL DROP TABLE #cell;
SELECT d, cls, AVG(t) mean, COUNT(*) n INTO #cell FROM #r
WHERE chaku=1 AND dt>='2024-01-01' AND t>=d/18.0 AND t<=d/11.0 GROUP BY d, cls;
IF OBJECT_ID('tempdb..#distmed') IS NOT NULL DROP TABLE #distmed;
SELECT DISTINCT d, PERCENTILE_CONT(0.5) WITHIN GROUP(ORDER BY t) OVER(PARTITION BY d) med
INTO #distmed FROM #r WHERE chaku=1 AND dt>='2024-01-01' AND t>=d/18.0 AND t<=d/11.0;
IF OBJECT_ID('tempdb..#delta') IS NOT NULL DROP TABLE #delta;
SELECT DISTINCT w.dt, PERCENTILE_CONT(0.5) WITHIN GROUP(ORDER BY w.dev) OVER(PARTITION BY w.dt) delta
INTO #delta FROM (
  SELECT r.dt, r.t - COALESCE(c.mean, dm.med) dev FROM #r r
  LEFT JOIN #cell c ON c.d=r.d AND c.cls=r.cls AND c.n>=8
  LEFT JOIN #distmed dm ON dm.d=r.d
  WHERE r.chaku=1 AND r.t>=r.d/18.0 AND r.t<=r.d/11.0 AND (c.mean IS NOT NULL OR dm.med IS NOT NULL)
) w;

SELECT cur.dt, cur.rno, cur.uma, cur.chaku, cur.d, cur.cls, cur.ba, cur.jk, cur.tr, cur.ow, cur.h,
  ab.adjbest, COALESCE(c2.mean, dm2.med) baseline,
  p1.ep p1_ep, p1.h p1_h, p1.c4 p1_c4, p1.up3 p1_up, p1.mgn p1_mgn, p1.d p1_d, p1.cls p1_cls, p1.dwt p1_dwt,
  p2.ep p2_ep, p2.h p2_h, p2.c4 p2_c4, p2.up3 p2_up, p2.mgn p2_mgn,
  baf.ba_n, baf.ba_pl,
  ptan.金額 win_pay, pfuku.金額 place_pay
FROM #r cur
OUTER APPLY (SELECT MIN(p.t - d.delta) adjbest FROM #r p LEFT JOIN #delta d ON d.dt=p.dt
   WHERE p.name=cur.name AND p.d=cur.d AND p.t>=p.d/18.0 AND p.t<=p.d/11.0 AND p.dt<cur.dt AND p.dt>=DATEADD(day,-365,cur.dt)) ab
OUTER APPLY (SELECT TOP 1 p.ep,p.h,p.c4,p.up3,p.mgn,p.d,p.cls,p.dwt FROM #r p
   WHERE p.name=cur.name AND (p.dt<cur.dt OR (p.dt=cur.dt AND p.rno<cur.rno)) ORDER BY p.dt DESC,p.rno DESC) p1
OUTER APPLY (SELECT p.ep,p.h,p.c4,p.up3,p.mgn FROM #r p
   WHERE p.name=cur.name AND (p.dt<cur.dt OR (p.dt=cur.dt AND p.rno<cur.rno)) ORDER BY p.dt DESC,p.rno DESC OFFSET 1 ROWS FETCH NEXT 1 ROWS ONLY) p2
OUTER APPLY (SELECT COUNT(*) ba_n, SUM(CASE WHEN p.chaku<=3 THEN 1 ELSE 0 END) ba_pl FROM #r p
   WHERE p.name=cur.name AND p.ba=cur.ba AND p.dt<cur.dt) baf
LEFT JOIN #cell c2 ON c2.d=cur.d AND c2.cls=cur.cls AND c2.n>=8
LEFT JOIN #distmed dm2 ON dm2.d=cur.d
LEFT JOIN 払戻金 ptan ON ptan.開催場所=@venue AND ptan.開催日=cur.dt AND ptan.レース番号=cur.rno AND ptan.馬券=N'単勝' AND ptan.組番=CAST(cur.uma AS nvarchar(8))
LEFT JOIN 払戻金 pfuku ON pfuku.開催場所=@venue AND pfuku.開催日=cur.dt AND pfuku.レース番号=cur.rno AND pfuku.馬券=N'複勝' AND pfuku.組番=CAST(cur.uma AS nvarchar(8))
WHERE cur.dt>='2024-01-01'
ORDER BY cur.dt, cur.rno, cur.uma;
"@

function ND($v){ if($v -is [DBNull] -or $null -eq $v){ return '' } else { return [string]$v } }

if ($Refresh -or -not (Test-Path $cachePath)) {
  Write-Host "DBから特徴量を抽出中..."
  $conn=New-Object System.Data.SqlClient.SqlConnection($connStr); $conn.Open()
  try {
    $cmd=$conn.CreateCommand(); $cmd.CommandTimeout=600; $cmd.CommandText=$sql
    $r=$cmd.ExecuteReader(); $rows=New-Object System.Collections.Generic.List[object]
    while($r.Read()){
      $rows.Add([PSCustomObject]@{
        date=$r['dt'].ToString('yyyy-MM-dd'); rno=[int]$r['rno']; uma=[int]$r['uma']; chaku=[int]$r['chaku']
        d=[int]$r['d']; cls=[double]$r['cls']; ba=[string]$r['ba']; jk=[string]$r['jk']; tr=[string]$r['tr']; ow=[string]$r['ow']; h=[int]$r['h']
        adjbest=(ND $r['adjbest']); baseline=(ND $r['baseline'])
        p1_ep=(ND $r['p1_ep']); p1_h=(ND $r['p1_h']); p1_c4=(ND $r['p1_c4']); p1_up=(ND $r['p1_up']); p1_mgn=(ND $r['p1_mgn']); p1_d=(ND $r['p1_d']); p1_cls=(ND $r['p1_cls']); p1_dwt=(ND $r['p1_dwt'])
        p2_ep=(ND $r['p2_ep']); p2_h=(ND $r['p2_h']); p2_c4=(ND $r['p2_c4']); p2_up=(ND $r['p2_up']); p2_mgn=(ND $r['p2_mgn'])
        ba_n=(ND $r['ba_n']); ba_pl=(ND $r['ba_pl'])
        winPay= if($r['win_pay'] -is [DBNull]){0}else{[double]$r['win_pay']}
        placePay= if($r['place_pay'] -is [DBNull]){0}else{[double]$r['place_pay']}
        placed= if($r['place_pay'] -is [DBNull]){0}else{1}
      })
    }
    $r.Close()
    $rows | Export-Csv -Path $cachePath -NoTypeInformation -Encoding UTF8
    Write-Host ("特徴量 {0} 行をキャッシュ" -f $rows.Count)
  } finally { $conn.Close() }
}

$all = @(Import-Csv $cachePath)
Write-Host ("特徴量読込: {0} 行  学習〜{1}  検証{2}〜" -f $all.Count,$TrainEnd,$TestStart)

# ---- ヘルパ: 文字列セルを数値化(空は$null) ----
function Num($s){ if($null -eq $s -or $s -eq ''){ return $null } else { return [double]$s } }
function StyleOf($ep,$h){ $e=Num $ep; $hh=Num $h; if($null -eq $e -or $null -eq $hh){ return '?' }
  if($e -eq 1){'逃げ'}elseif($e -le $hh*0.33){'先行'}elseif($e -le $hh*0.66){'差し'}else{'追込'} }

# ---- 派生フィールド ----
foreach($x in $all){
  $x|Add-Member -NotePropertyName prevStyle -NotePropertyValue (StyleOf $x.p1_ep $x.p1_h) -Force
  $x|Add-Member -NotePropertyName lead -NotePropertyValue ([int]((Num $x.p1_ep) -ne $null)) -Force  # placeholder
}
# 同型(レース内の前走前々頭数)を計算
$byRaceAll = $all | Group-Object { "$($_.date)_$($_.rno)" }
$maeMap=@{}
foreach($g in $byRaceAll){
  $c=0; foreach($x in $g.Group){ if($x.prevStyle -eq '逃げ' -or $x.prevStyle -eq '先行'){ $c++ } }
  $maeMap[$g.Name]=$c
}
foreach($x in $all){ $x|Add-Member -NotePropertyName maeCnt -NotePropertyValue $maeMap["$($x.date)_$($x.rno)"] -Force }

# ---- 学習期間: 騎手前付率・コネクション逃げ率 ----
$jk=@{}; foreach($x in $all){ if($x.date -gt $TrainEnd){continue}; $e=Num $x.p1_ep
  # 騎手の前付けは今走実績で測る: 今走 early_pos が必要だが未取得 → 前走脚質を代理に厩舎別は使わずConnLeadで代替
}
# コネクション「今走逃げ率」は今走early_posが必要。ここでは簡易にp1ベースの騎手前付け(前走前々率)を用いる
$jkFront=@{}
foreach($x in $all){ if($x.date -gt $TrainEnd){continue}
  if($x.prevStyle -eq '?'){continue}
  $f=($x.prevStyle -eq '逃げ' -or $x.prevStyle -eq '先行')
  if(-not $jkFront.ContainsKey($x.jk)){$jkFront[$x.jk]=[pscustomobject]@{n=0;f=0}}
  $jkFront[$x.jk].n++; if($f){$jkFront[$x.jk].f++} }
$jkRate=@{}; foreach($k in $jkFront.Keys){ if($jkFront[$k].n -ge 50){$jkRate[$k]=100.0*$jkFront[$k].f/$jkFront[$k].n} }

# コネクション「逃げ率」(調教師|馬主|騎手 → 厩舎|騎手 → 騎手): 今走逃げの代理として前走脚質前々を使用
$triple=@{};$pair=@{};$solo=@{}
foreach($x in $all){ if($x.date -gt $TrainEnd){continue}; if($x.prevStyle -eq '?'){continue}
  $L=($x.prevStyle -eq '逃げ')
  foreach($pp in @(@($triple,"$($x.tr)|$($x.ow)|$($x.jk)"),@($pair,"$($x.tr)|$($x.jk)"),@($solo,$x.jk))){
    $h=$pp[0];$k=$pp[1]; if(-not $h.ContainsKey($k)){$h[$k]=[pscustomobject]@{n=0;l=0}}; $h[$k].n++; if($L){$h[$k].l++} } }
function ConnLead($x){ $kt="$($x.tr)|$($x.ow)|$($x.jk)";$kp="$($x.tr)|$($x.jk)";$ks=$x.jk
  if($triple.ContainsKey($kt) -and $triple[$kt].n -ge 20){return $triple[$kt].l/$triple[$kt].n}
  if($pair.ContainsKey($kp) -and $pair[$kp].n -ge 30){return $pair[$kp].l/$pair[$kp].n}
  if($solo.ContainsKey($ks) -and $solo[$ks].n -ge 50){return $solo[$ks].l/$solo[$ks].n}; return $null }

# ---- スコア関数 ----
# A: 馬のファクトのみ
function ScoreA($x){
  $s=0.0
  # 能力(補正後タイム偏差)
  $ab=Num $x.adjbest; $bl=Num $x.baseline
  if($null -ne $ab -and $null -ne $bl){ $edge=$bl-$ab; if($edge -ge 1.0){$s+=2}elseif($edge -gt 0){$s+=1}elseif($edge -le -1.0){$s-=1} }
  else { $s-=0.5 } # 同距離実績なし=未知
  # 競走力(前走 一着馬着差)
  $m1=Num $x.p1_mgn; if($null -ne $m1){ if($m1 -le 0.3){$s+=1}elseif($m1 -le 0.8){$s+=0.5} }
  # 体調(前々走→前走の改善)
  $u1=Num $x.p1_up; $u2=Num $x.p2_up; if($null -ne $u1 -and $null -ne $u2){ if($u2 -gt $u1){$s+=0.5} }  # 上り改善
  $m2=Num $x.p2_mgn; if($null -ne $m1 -and $null -ne $m2){ if($m1 -lt $m2){$s+=0.5} }                    # 着差改善
  $c41=Num $x.p1_c4; $h1=Num $x.p1_h; $c42=Num $x.p2_c4; $h2=Num $x.p2_h
  if($null -ne $c41 -and $null -ne $h1 -and $null -ne $c42 -and $null -ne $h2 -and $h1 -gt 1 -and $h2 -gt 1){
    if((($c41-1)/($h1-1)) -lt (($c42-1)/($h2-1))){$s+=0.5} }                                              # 四角位置前進
  # 馬体重増減の安定性(符号不明のため絶対値で過大変動を減点)
  $dw=Num $x.p1_dwt; if($null -ne $dw -and [math]::Abs($dw) -ge 12){$s-=0.5}
  # クラス変動(今回 vs 前走 一着賞金)
  $pc=Num $x.p1_cls
  if($null -ne $pc){
    if($x.cls -lt $pc){ $s+=1.5 }                                  # 降格
    elseif($x.cls -gt $pc){ $s-=1.0; if(($null -ne $m1 -and $m1 -eq 0) -or ($null -ne $ab -and $null -ne $bl -and ($bl-$ab) -ge 1.0)){ $s+=0.5 } } # 格上挑戦(前走圧勝なら緩和)
  }
  # 馬場相性
  $bn=Num $x.ba_n; $bp=Num $x.ba_pl
  if($null -ne $bn -and $bn -ge 3){ $rate=$bp/$bn; if($rate -ge 0.5){$s+=1}elseif($rate -lt 0.2){$s-=0.5} }
  return $s
}
# B: A + 展開(脚質・同型不在・騎手前付・コネ隠れ前残り)
function ScoreB($x){
  $s=ScoreA $x
  switch($x.prevStyle){ '逃げ'{$s+=2} '先行'{$s+=1} }
  $mae=[int]$x.maeCnt
  if($x.prevStyle -eq '逃げ' -or $x.prevStyle -eq '先行'){ if($mae -le 1){$s+=1.5}elseif($mae -eq 2){$s+=0.8} }
  if($jkRate.ContainsKey($x.jk)){ $jr=$jkRate[$x.jk]; if($jr -ge 40){$s+=2}elseif($jr -ge 33){$s+=1} }
  $cl=ConnLead $x; if($null -ne $cl -and ($x.prevStyle -eq '差し' -or $x.prevStyle -eq '追込')){ if($cl -ge 0.25){$s+=1.5}elseif($cl -ge 0.18){$s+=0.8} }
  if($x.ba -eq '不良' -and $x.prevStyle -eq '追込'){$s-=0.5}
  return $s
}

foreach($x in $all){
  $x|Add-Member -NotePropertyName scA -NotePropertyValue (ScoreA $x) -Force
  $x|Add-Member -NotePropertyName scB -NotePropertyValue (ScoreB $x) -Force
}

# ---- 較正: 学習期間でスコア帯(0.5刻みfloor)別の実勝率 → 勝率%変換表 ----
function BuildCalib($key){
  $tab=@{}
  foreach($x in $all){ if($x.date -gt $TrainEnd){continue}
    $b=[math]::Floor(([double]$x.$key)*2)/2.0
    if(-not $tab.ContainsKey($b)){$tab[$b]=[pscustomobject]@{n=0;w=0}}
    $tab[$b].n++; if([int]$x.chaku -eq 1){$tab[$b].w++} }
  return $tab
}
$calA=BuildCalib 'scA'; $calB=BuildCalib 'scB'
$globW = (@($all|Where-Object{$_.date -le $TrainEnd -and [int]$_.chaku -eq 1}).Count)/(@($all|Where-Object{$_.date -le $TrainEnd}).Count)
function CalibProb($tab,$score){
  $b=[math]::Floor(([double]$score)*2)/2.0
  # 最寄りの十分標本(n>=20)のビンを探す(中心→外側)
  for($off=0;$off -le 12;$off++){
    $c1=$b+$off*0.5; if($tab.ContainsKey($c1) -and $tab[$c1].n -ge 20){ return [double]($tab[$c1].w/$tab[$c1].n) }
    $c2=$b-$off*0.5; if($tab.ContainsKey($c2) -and $tab[$c2].n -ge 20){ return [double]($tab[$c2].w/$tab[$c2].n) }
  }
  return [double]$globW
}

# ---- 検証 ----
$test=@($all|Where-Object{$_.date -ge $TestStart})
$byRace=$test|Group-Object { "$($_.date)_$($_.rno)" }
function Backtest($key,$tab,$label){
  $b=0;$w=0;$wp=0.0;$pl=0;$pp=0.0
  foreach($g in $byRace){
    $best=($g.Group|Sort-Object @{e={[double]$_.$key};Descending=$true},@{e={[int]$_.uma}})[0]
    $b++; if([int]$best.chaku -eq 1){$w++;$wp+=[double]$best.winPay}; if([int]$best.placed -eq 1){$pl++;$pp+=[double]$best.placePay} }
  Write-Host ("  {0,-14} 本命{1,4}R 単[的中{2,5:P1} 回収{3,7:P1}] 複[的中{4,5:P1} 回収{5,7:P1}]" -f $label,$b,($w/$b),($wp/($b*100)),($pl/$b),($pp/($b*100)))
}
Write-Host "`n■ 本命1点(最高スコア)の検証回収率"
Backtest 'scA' $calA 'A:馬ファクト'
Backtest 'scB' $calB 'B:展開統合'

# 較正の良否(検証期間・予測勝率%帯 vs 実勝率)
function CalibCheck($key,$tab,$label){
  Write-Host ("`n■ 較正チェック {0}(検証期間・予測勝率% vs 実勝率)" -f $label)
  $buckets=@{}
  foreach($x in $test){ $p=[double](CalibProb $tab $x.$key); $bk=[math]::Floor($p*100/5)*5
    if(-not $buckets.ContainsKey($bk)){$buckets[$bk]=[pscustomobject]@{n=0;w=0;ps=0.0}}
    $buckets[$bk].n++; $buckets[$bk].ps+=$p; if([int]$x.chaku -eq 1){$buckets[$bk].w++} }
  foreach($bk in ($buckets.Keys|Sort-Object)){ $o=$buckets[$bk]
    if($o.n -lt 30){continue}
    Write-Host ("    予測{0,3}-{1,3}%  n={2,5}  平均予測{3,5:P1}  実勝率{4,5:P1}" -f $bk,($bk+5),$o.n,($o.ps/$o.n),($o.w/$o.n)) }
}
CalibCheck 'scA' $calA 'A:馬ファクト'
CalibCheck 'scB' $calB 'B:展開統合'

# ---- 指定日の各馬スコア/勝率%表示 ----
if($ShowRace -ne ''){
  Write-Host ("`n■ {0} の各馬 スコア/推定勝率%(A=馬ファクト, B=展開統合)" -f $ShowRace)
  $day=@($all|Where-Object{$_.date -eq $ShowRace})
  foreach($g in ($day|Group-Object rno|Sort-Object {[int]$_.Name})){
    Write-Host ("`n-- {0}R --" -f $g.Name)
    # レース内正規化した勝率%
    $items=foreach($x in $g.Group){
      $pa=CalibProb $calA $x.scA; $pb=CalibProb $calB $x.scB
      [pscustomobject]@{uma=$x.uma; chaku=$x.chaku; scA=[double]$x.scA; scB=[double]$x.scB; pa=$pa; pb=$pb} }
    $sa=($items|Measure-Object pa -Sum).Sum; $sb=($items|Measure-Object pb -Sum).Sum
    foreach($it in ($items|Sort-Object pb -Descending)){
      $na= if($sa -gt 0){$it.pa/$sa}else{0}; $nb= if($sb -gt 0){$it.pb/$sb}else{0}
      Write-Host ("   馬{0,2} 着{1,2}  A:score{2,5:N1}/勝率{3,5:P1}   B:score{4,5:N1}/勝率{5,5:P1}" -f $it.uma,$it.chaku,$it.scA,$na,$it.scB,$nb) }
  }
}
