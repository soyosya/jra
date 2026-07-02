# 指定レースの「全頭 買目表」(JSON)。JRA版(地方 buyme.ps1 移植)。読み取り専用。
#  コンピ全頭 + 印(ipat_bets CSV) + 軸確度/波乱度(コンピ算出) + 全馬h2h(rank+tag) + 現単複オッズ
#  + 定性(調教/厩舎の話=ツールチップ) + 確定(着順/確定単複払戻)。指数断層はクライアント側(horse.idx)で表示。
param([string]$Venue='',[int]$Race=0,[string]$Date='')
$OutputEncoding=[Console]::OutputEncoding=[System.Text.Encoding]::UTF8
$ErrorActionPreference='SilentlyContinue'
if([string]::IsNullOrWhiteSpace($Venue) -or $Race -le 0){ [ordered]@{ error='venue/race が必要です' } | ConvertTo-Json -Compress; return }
$date= if($Date){$Date}else{(Get-Date -Format 'yyyy-MM-dd')}; $ymd=($date -replace '[^0-9]','')
# A9: 取りやめ(レース中止)判定
$cancelled=$false; try{ $kf='C:\jra\RunnerControl\race-cancel.json'; if(Test-Path $kf){ $kj=Get-Content $kf -Raw -Encoding UTF8|ConvertFrom-Json; if($kj -and "$($kj.date)" -eq $date){ foreach($kk in @($kj.cancelled)){ if("$kk" -eq "$Venue|$Race"){$cancelled=$true} } } } }catch{}
$RecentN=6; $RecentDays=365
function Median($a){ $s=@($a|Sort-Object); $n=$s.Count; if($n -eq 0){return $null}; if($n%2 -eq 1){return [double]$s[[int](($n-1)/2)]}; return ([double]$s[$n/2-1]+[double]$s[$n/2])/2.0 }
# ★較正複勝確率モデルA(コンピ順位band+指数Z+h2h)。全頭の確度を確率表示(表示用・+EVでない)[[jra-bayes-fukusho-calibration]]
$bayesA=$null; try{ $bj='C:\jra\tools\jra-bayes-model-A.json'; if(Test-Path $bj){ $bayesA=Get-Content $bj -Raw -Encoding UTF8|ConvertFrom-Json } }catch{ $bayesA=$null }
function Get-BayesFuku($rk,$idx,$h2hRk){ if($null -eq $bayesA -or $rk -lt 1){ return $null }
  $rb= if($rk -eq 1){1}elseif($rk -le 3){2}elseif($rk -le 6){3}else{4}
  $idxZ=([double]$idx-$bayesA.idxM)/$bayesA.idxS
  $hh=0.0; $hz=0.0; if($h2hRk -gt 0){ $hh=1.0; $hz=($h2hRk-$bayesA.hrM)/$bayesA.hrS }
  $w=$bayesA.weights
  $z=$w[0]+$w[1]*[double]($rb -eq 2)+$w[2]*[double]($rb -eq 3)+$w[3]*[double]($rb -eq 4)+$w[4]*$idxZ+$w[5]*$hh+$w[6]*$hz
  if($z -ge 0){ 1.0/(1.0+[math]::Exp(-$z)) }else{ $e=[math]::Exp($z); $e/(1.0+$e) } }

$cs=(Get-Content 'C:\jra\共通\appsettings.json' -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
$cn=New-Object System.Data.SqlClient.SqlConnection $cs; $cn.Open()
function Q1([string]$sql,[hashtable]$p){ $c=$cn.CreateCommand(); $c.CommandText=$sql; foreach($k in $p.Keys){[void]$c.Parameters.AddWithValue($k,$p[$k])}; $dt=New-Object System.Data.DataTable; (New-Object System.Data.SqlClient.SqlDataAdapter $c).Fill($dt)|Out-Null; ,$dt }

# 1) 印(ipat_bets CSV: axis=◎ / partners=○▲△押)
$mark=@{}; $meta=[ordered]@{conf='';kind='ワイド 軸流し(相手3)';seg='';rec=0;wide1=0;wide2=0;keshiUma=0;keshiReason=''}
$betCsv="C:\temp\ipat_bets_$ymd.csv"
if(Test-Path $betCsv){
  $prow=@(Import-Csv $betCsv -Encoding UTF8 | Where-Object { $_.venue -eq $Venue -and [int]$_.race -eq $Race })[0]
  if($prow){
    if("$($prow.axis)" -ne ''){ $mark[[int]$prow.axis]='◎' }
    $pl=@(("$($prow.partners)" -split '\|') | Where-Object{ $_ -ne '' })
    $pm=@('○','▲','△','押')
    for($i=0;$i -lt $pl.Count -and $i -lt 4;$i++){ $u=[int]$pl[$i]; if(-not $mark.ContainsKey($u)){ $mark[$u]=$pm[$i] } }
    if("$($prow.bettype)" -ne ''){ $meta.kind="$($prow.bettype) 軸流し(相手$($pl.Count))" }
  }
}

# 2) 全頭(コンピ最新+前走指数+騎手+距離+発走+競走名)
$hd=Q1 @"
WITH cur AS (SELECT 馬番,馬名,指数,指数順位, ROW_NUMBER() OVER(PARTITION BY 馬番 ORDER BY 取得日時 DESC) sn FROM dbo.コンピ指数 WHERE 開催日=@d AND 開催場所=@v AND レース番号=@r),
prev AS (SELECT ci.馬名, ci.指数 pidx, ROW_NUMBER() OVER(PARTITION BY ci.馬名 ORDER BY ci.開催日 DESC,ci.レース番号 DESC) rn FROM dbo.コンピ指数 ci WHERE ci.開催日<@d AND ci.馬名 IN (SELECT 馬名 FROM cur) AND EXISTS(SELECT 1 FROM dbo.競走結果 cr WHERE cr.馬名=ci.馬名 AND cr.開催日=ci.開催日 AND cr.開催場所=ci.開催場所 AND cr.レース番号=ci.レース番号 AND cr.着順>0))
SELECT cur.馬番,cur.馬名,cur.指数,cur.指数順位,p.pidx, ri.枠番,ri.騎手,ri.距離,ri.発走時刻,ri.競走名,ri.斤量,ri.馬体重,ri.馬体重増減, kr.枠番 frame2
FROM cur LEFT JOIN prev p ON p.馬名=cur.馬名 AND p.rn=1
OUTER APPLY (SELECT TOP 1 枠番,騎手,距離,発走時刻,競走名,斤量,馬体重,馬体重増減 FROM dbo.レース情報 WHERE 開催場所=@v AND 開催日=@d AND レース番号=@r AND 馬番=cur.馬番) ri
OUTER APPLY (SELECT TOP 1 枠番 FROM dbo.競走結果 WHERE 開催場所=@v AND 開催日=@d AND レース番号=@r AND 馬番=cur.馬番) kr
WHERE cur.sn=1 ORDER BY cur.指数順位
"@ @{'@d'=$date;'@v'=$Venue;'@r'=$Race}
$field=@($hd.Rows | ForEach-Object { [string]$_.馬名 })
$compiRk=@{}; $idxByRk=@{}; foreach($r in $hd.Rows){ $compiRk[[string]$r.馬名]=[int]$r.指数順位; if($r.指数 -isnot [DBNull]){ $idxByRk[[int]$r.指数順位]=[int]$r.指数 } }

# 軸確度ラダー(g12/range16/idx1)+波乱度(テク6)[[jra-chihou-signal-verify]]
if($idxByRk.ContainsKey(1) -and $idxByRk.ContainsKey(2)){
  $g12=$idxByRk[1]-$idxByRk[2]; $r16= if($idxByRk.ContainsKey(6)){$idxByRk[1]-$idxByRk[6]}else{$null}
  $t6= if($idxByRk.ContainsKey(3)){$idxByRk[1]+$idxByRk[2]+$idxByRk[3]}else{$null}
  $meta.conf= if($g12 -ge 10 -or ($null -ne $r16 -and $r16 -ge 33) -or $idxByRk[1] -ge 88){'鉄板'}elseif($g12 -le 4 -and $idxByRk[1] -lt 76){'警戒'}else{'標準'}
  $meta.seg= if($null -ne $t6){ if($t6 -lt 200){'荒'}elseif($t6 -ge 220){'堅'}else{'中'} }else{''}
}

# 3) 現オッズ(最新スナップショット)
$od=@{}
foreach($x in (Q1 "WITH t AS (SELECT 馬番,単勝オッズ,複勝オッズ_MIN,複勝オッズ_MAX,人気,ROW_NUMBER() OVER(PARTITION BY 馬番 ORDER BY 日時 DESC) rn FROM dbo.リアルタイムオッズ WHERE 開催日=@d AND 開催場所=@v AND レース番号=@r) SELECT 馬番,単勝オッズ t,複勝オッズ_MIN fmin,複勝オッズ_MAX fmax,人気 pop FROM t WHERE rn=1" @{'@d'=$date;'@v'=$Venue;'@r'=$Race}).Rows){
  $od[[int]$x.馬番]=[ordered]@{ tan=[double]("0"+"$($x.t)"); fmin=[double]("0"+"$($x.fmin)"); fmax=[double]("0"+"$($x.fmax)"); pop=[int]("0"+"$($x.pop)") } }

# 4) 前走距離
$prevDist=@{}
foreach($x in (Q1 "WITH e AS (SELECT DISTINCT 馬名 FROM レース情報 WHERE 開催日=@d AND 開催場所=@v AND レース番号=@r), pdq AS (SELECT ri.馬名 h,ri.距離 dist,ROW_NUMBER() OVER(PARTITION BY ri.馬名 ORDER BY ri.開催日 DESC,ri.レース番号 DESC) rn FROM レース情報 ri WHERE ri.開催日<@d AND ri.距離>0 AND ri.馬名 IN (SELECT 馬名 FROM e) AND EXISTS(SELECT 1 FROM dbo.競走結果 cr WHERE cr.馬名=ri.馬名 AND cr.開催日=ri.開催日 AND cr.開催場所=ri.開催場所 AND cr.レース番号=ri.レース番号 AND cr.着順>0)) SELECT pdq.h,pdq.dist FROM pdq JOIN e ON e.馬名=pdq.h WHERE pdq.rn=1" @{'@d'=$date;'@v'=$Venue;'@r'=$Race}).Rows){ $prevDist["$($x.h)"]=[int]$x.dist }
# 前走騎手(勝負気配用)
$prevJk=@{}
foreach($x in (Q1 "WITH e AS (SELECT DISTINCT 馬名 FROM レース情報 WHERE 開催日=@d AND 開催場所=@v AND レース番号=@r), pj AS (SELECT ri.馬名 h,ri.騎手 jk,ROW_NUMBER() OVER(PARTITION BY ri.馬名 ORDER BY ri.開催日 DESC,ri.レース番号 DESC) rn FROM レース情報 ri WHERE ri.開催日<@d AND ri.騎手 IS NOT NULL AND ri.騎手<>N'' AND ri.馬名 IN (SELECT 馬名 FROM e) AND EXISTS(SELECT 1 FROM dbo.競走結果 cr WHERE cr.馬名=ri.馬名 AND cr.開催日=ri.開催日 AND cr.開催場所=ri.開催場所 AND cr.レース番号=ri.レース番号 AND cr.着順>0)) SELECT pj.h,pj.jk FROM pj JOIN e ON e.馬名=pj.h WHERE pj.rn=1" @{'@d'=$date;'@v'=$Venue;'@r'=$Race}).Rows){ $prevJk["$($x.h)"]="$($x.jk)" }

# 5) 定性(ツールチップ): 調教(矢印+短評) / 厩舎の話(印+コメント)
$qual=@{}
function AddQual($u,$txt){ if([string]::IsNullOrWhiteSpace($txt)){return}; if(-not $qual.ContainsKey($u)){$qual[$u]=@()}; $qual[$u]+=$txt }
foreach($x in (Q1 "SELECT 馬番,矢印,追い切り短評 FROM dbo.調教 WHERE 開催日=@d AND 開催場所=@v AND レース番号=@r" @{'@d'=$date;'@v'=$Venue;'@r'=$Race}).Rows){ $y=if($x.矢印 -is [DBNull]){''}else{"$($x.矢印)"}; $s=if($x.追い切り短評 -is [DBNull]){''}else{"$($x.追い切り短評)"}; $t=(@($y,$s)|Where-Object{$_ -ne ''}) -join ' '; AddQual ([int]$x.馬番) $(if($t){"調教: $t"}else{''}) }
foreach($x in (Q1 "SELECT 馬番,印,コメント FROM dbo.厩舎の話 WHERE 開催日=@d AND 開催場所=@v AND レース番号=@r" @{'@d'=$date;'@v'=$Venue;'@r'=$Race}).Rows){ $mk=if($x.印 -is [DBNull]){''}else{"$($x.印)"}; $c=if($x.コメント -is [DBNull]){''}else{"$($x.コメント)"}; $t=(@($mk,$c)|Where-Object{$_ -ne ''}) -join ' '; AddQual ([int]$x.馬番) $(if($t){"厩舎: $t"}else{''}) }

# 6) 結果(着順 + 確定単複払戻)
$chOf=@{}; $tanConf=@{}; $fukuConf=@{}
foreach($x in (Q1 "SELECT 馬番,TRY_CONVERT(int,着順) ch FROM dbo.競走結果 WHERE 開催場所=@v AND 開催日=@d AND レース番号=@r" @{'@d'=$date;'@v'=$Venue;'@r'=$Race}).Rows){ if($x.ch -isnot [DBNull] -and $null -ne $x.ch){ $chOf[[int]$x.馬番]=[int]$x.ch } }
foreach($x in (Q1 "SELECT 馬券,組番,金額 FROM dbo.払戻金 WHERE 開催場所=@v AND 開催日=@d AND レース番号=@r AND 馬券 IN (N'単勝',N'複勝')" @{'@d'=$date;'@v'=$Venue;'@r'=$Race}).Rows){ $u=0; if([int]::TryParse(("$($x.組番)").Trim(),[ref]$u)){ if("$($x.馬券)" -eq '単勝'){$tanConf[$u]=[int]$x.金額}else{$fukuConf[$u]=[int]$x.金額} } }
$finished = ($chOf.Count -gt 0)
# A2: 出走取消/除外(dbo.変更情報)。取消馬は全頭表でグレー・h2h/オッズ/人気空欄・断層/投票選択から除外(クライアント側)。
$scratched=@{}
foreach($x in (Q1 "SELECT 馬番 FROM dbo.変更情報 WHERE 開催日=@d AND 開催場所=@v AND レース番号=@r AND (変更内容 LIKE N'%取消%' OR 変更内容 LIKE N'%除外%' OR 変更区分 LIKE N'%取消%' OR 変更区分 LIKE N'%除外%')" @{'@d'=$date;'@v'=$Venue;'@r'=$Race}).Rows){ if($x.馬番 -isnot [DBNull]){ $scratched[[int]$x.馬番]=$true } }

# 7) h2h(全馬)=同条件限定連鎖でランク化(jra-card Compute-H2hと同方式・近走着差±8%クリップ中央値)。matrixは無いのでrank+tag表示。
$tc=Q1 "SELECT TOP 1 コース種別 surf,TRY_CAST(距離 AS int) dist FROM dbo.レース情報 WHERE 開催場所=@v AND 開催日=@d AND レース番号=@r" @{'@d'=$date;'@v'=$Venue;'@r'=$Race}
$tsurf=''; $tdist=0; if($tc.Rows.Count){ $tsurf=[string]$tc.Rows[0].surf; if($tc.Rows[0].dist -isnot [DBNull]){$tdist=[int]$tc.Rows[0].dist} }
$useCond = ($tsurf -ne '' -and $tdist -gt 0)
$dminC=([datetime]$date).AddDays(-365).ToString('yyyy-MM-dd')
$fieldSet=@{}; $field|ForEach-Object{$fieldSet[$_]=$true}
$recentKeys=@{}; $allKeys=@{}
foreach($h in $field){
  $rk= if($useCond){
    Q1 "SELECT TOP 6 k.開催場所,k.開催日,k.レース番号 FROM dbo.競走結果 k JOIN dbo.レース情報 ri ON ri.開催場所=k.開催場所 AND ri.開催日=k.開催日 AND ri.レース番号=k.レース番号 AND ri.馬名=k.馬名 WHERE k.馬名=@h AND k.開催日<@d AND k.開催日>=@m AND k.走破時計>0 AND ri.コース種別=@surf AND ABS(TRY_CAST(ri.距離 AS int)-@dist)<=200 ORDER BY k.開催日 DESC,k.レース番号 DESC" @{'@h'=$h;'@d'=$date;'@m'=$dminC;'@surf'=$tsurf;'@dist'=$tdist}
  }else{
    Q1 "SELECT TOP ($RecentN) 開催場所,開催日,レース番号 FROM dbo.競走結果 WHERE 馬名=@h AND 開催日<@d AND 開催日>=@m AND 走破時計>0 ORDER BY 開催日 DESC,レース番号 DESC" @{'@h'=$h;'@d'=$date;'@m'=$dminC} }
  $keys=@(); foreach($x in $rk.Rows){ $kk=[string]$x.開催場所+'|'+([datetime]$x.開催日).ToString('yyyy-MM-dd')+'|'+[string]([int]$x.レース番号); $keys+=$kk; if(-not $allKeys.ContainsKey($kk)){$allKeys[$kk]=@{v=[string]$x.開催場所;d=([datetime]$x.開催日).ToString('yyyy-MM-dd');r=[int]$x.レース番号}} }
  $recentKeys[$h]=$keys
}
$raceRows=@{}; foreach($kk in $allKeys.Keys){ $info=$allKeys[$kk]; $m2=@{}; foreach($row in (Q1 "SELECT 馬名,走破時計 FROM dbo.競走結果 WHERE 開催場所=@v AND 開催日=@d AND レース番号=@r AND 走破時計>0 AND 着順>0" @{'@v'=$info.v;'@d'=$info.d;'@r'=$info.r}).Rows){ $m2[[string]$row.馬名]=[double]$row.走破時計 }; $raceRows[$kk]=$m2 }
$raceWin=@{}; foreach($kk in $raceRows.Keys){ $vals=@($raceRows[$kk].Values); if($vals.Count){ $raceWin[$kk]=($vals|Measure-Object -Minimum).Minimum } }
$mavg=@{}
foreach($a in $field){ $mavg[$a]=@{}; $tmp=@{}
  foreach($kk in $recentKeys[$a]){ $rr=$raceRows[$kk]; if($null -eq $rr -or -not $rr.ContainsKey($a)){continue}; $ta=$rr[$a]; $wt=$raceWin[$kk]; if(-not $wt){continue}
    foreach($x in $rr.Keys){ if($x -eq $a){continue}; $rel=($rr[$x]-$ta)/$wt*100.0; if($rel -gt 8){$rel=8}elseif($rel -lt -8){$rel=-8}; if(-not $tmp.ContainsKey($x)){$tmp[$x]=New-Object System.Collections.Generic.List[double]}; $tmp[$x].Add([double]$rel) } }
  foreach($x in $tmp.Keys){ $mavg[$a][$x]=Median $tmp[$x] } }
function PairM2($a,$b){ $vv=@(); if($mavg[$a].ContainsKey($b)){$vv+=$mavg[$a][$b]}; if($mavg[$b].ContainsKey($a)){$vv+=(-1.0*$mavg[$b][$a])}; if($vv.Count -gt 0){return (($vv|Measure-Object -Average).Average)}
  $common=@($mavg[$a].Keys|Where-Object{$mavg[$b].ContainsKey($_) -and $_ -ne $a -and $_ -ne $b}); if($common.Count -eq 0){return $null}
  $fc=@($common|Where-Object{$fieldSet.ContainsKey($_)}); $use=if($fc.Count -gt 0){$fc}else{$common}; $est=foreach($cc in $use){$mavg[$a][$cc]-$mavg[$b][$cc]}; return (Median $est) }
$h2hScore=@{}; foreach($a in $field){ $ms=@(); foreach($b in $field){ if($a -ne $b){ $mm=PairM2 $a $b; if($null -ne $mm){$ms+=$mm} } }; if($ms.Count -ge 1){$h2hScore[$a]=($ms|Measure-Object -Average).Average} }
$h2hRkNm=@{}; $hi=1; foreach($kv in ($h2hScore.GetEnumerator()|Sort-Object Value -Descending)){ $h2hRkNm[$kv.Key]=$hi; $hi++ }
function H2hLabel($nm){ $hr= if($h2hRkNm.ContainsKey($nm)){$h2hRkNm[$nm]}else{0}; if($hr -le 0){return ''}; $cr= if($compiRk.ContainsKey($nm)){$compiRk[$nm]}else{99}
  $tag= if($cr -eq 1 -and $hr -eq 1){'両1位'}elseif($cr -eq 1 -and $hr -ge 6){'h2h不支持'}elseif($hr -ge 1 -and $hr -le 2 -and $cr -ge 4){'地力先行'}else{''}
  ('h2h{0}位{1}' -f $hr,$(if($tag){'('+$tag+')'}else{''})) }
$cn.Close()

# 今走騎手・勝負気配
$todayJk=@{}; $todayKin=@{}; $todayBw=@{}; $todayBwd=@{}
foreach($r in $hd.Rows){ $u=[int]$r.馬番
  $todayJk[$u]= if($r.騎手 -is [DBNull]){''}else{"$($r.騎手)"}
  $todayKin[$u]= if($r.斤量 -is [DBNull]){''}else{"$($r.斤量)"}
  $todayBw[$u]= if($r.馬体重 -is [DBNull]){''}else{"$($r.馬体重)"}
  $todayBwd[$u]= if($r.馬体重増減 -is [DBNull]){''}else{"$($r.馬体重増減)"} }
$senpu=@{}
foreach($r in $hd.Rows){ $ja=if($r.騎手 -is [DBNull]){''}else{"$($r.騎手)"}; if($ja -eq ''){continue}
  foreach($r2 in $hd.Rows){ if([int]$r2.馬番 -eq [int]$r.馬番){continue}; $pjb= if($prevJk.ContainsKey("$($r2.馬名)")){$prevJk["$($r2.馬名)"]}else{''}; if($pjb -ne '' -and $pjb -eq $ja){ $senpu[[int]$r.馬番]=[int]$r2.馬番; break } } }

$dist=$tdist; $post=''; $rn2=''
$horses=@()
foreach($r in $hd.Rows){
  $u=[int]$r.馬番; $nm="$($r.馬名)"; $idx=[int]$r.指数; $rk=[int]$r.指数順位
  $pidx= if($r.pidx -is [DBNull]){$null}else{[int]$r.pidx}
  $dz= if($null -ne $pidx){ $idx-$pidx }else{ $null }
  $td= if($r.距離 -is [DBNull]){0}else{[int]$r.距離}; if($td -gt 0){$dist=$td}
  if($r.発走時刻 -isnot [DBNull] -and $post -eq ''){ $post=([datetime]$r.発走時刻).ToString('HH:mm') }
  if($r.競走名 -isnot [DBNull] -and $rn2 -eq ''){ $rn2="$($r.競走名)" }
  $distNote=''
  if($null -ne $dz -and $dz -gt 0 -and $td -gt 0 -and $prevDist.ContainsKey($nm)){ $pdd=$prevDist[$nm]; if($td -lt $pdd){$distNote='↑指数×短縮'}elseif($td -gt $pdd){$distNote='↑指数×延長'} }
  $o=$od[$u]
  $horses+=[ordered]@{
    rk=$rk; mark=$(if($mark.ContainsKey($u)){$mark[$u]}else{''}); uma=$u; name=$nm; idx=$idx
    dz=$(if($null -eq $dz){''}else{$dz}); h2h=(H2hLabel $nm)
    pfuku=$(if($null -ne $bayesA){ $pf=Get-BayesFuku $rk $idx $(if($h2hRkNm.ContainsKey($nm)){[int]$h2hRkNm[$nm]}else{0}); if($null -ne $pf){[math]::Round($pf,3)}else{''} }else{''})
    jk=$todayJk[$u]; kin=$(if($todayKin.ContainsKey($u)){$todayKin[$u]}else{''}); bw=$(if($todayBw.ContainsKey($u)){$todayBw[$u]}else{''}); bwd=$(if($todayBwd.ContainsKey($u)){$todayBwd[$u]}else{''}); senpu=$(if($senpu.ContainsKey($u)){$senpu[$u]}else{0}); distNote=$distNote
    tan=$(if($o){$o.tan}else{0}); fmin=$(if($o){$o.fmin}else{0}); fmax=$(if($o){$o.fmax}else{0}); pop=$(if($o){$o.pop}else{0})
    chaku=$(if($chOf.ContainsKey($u)){$chOf[$u]}else{0}); tanPay=$(if($tanConf.ContainsKey($u)){$tanConf[$u]}else{0}); fukuPay=$(if($fukuConf.ContainsKey($u)){$fukuConf[$u]}else{0})
    qual=$(if($qual.ContainsKey($u)){($qual[$u] -join ' ／ ')}else{''})
    keshi=''
    frame=$(if($r.枠番 -isnot [DBNull] -and [int]("0"+"$($r.枠番)") -gt 0){[int]("0"+"$($r.枠番)")}elseif($r.frame2 -isnot [DBNull] -and [int]("0"+"$($r.frame2)") -gt 0){[int]("0"+"$($r.frame2)")}else{0})
    scratched=$(if($scratched.ContainsKey($u)){$true}else{$false})
  }
}
$horses=@($horses | Sort-Object {[int]$_.rk},{[int]$_.uma})
[ordered]@{ date=$date; venue=$Venue; race=$Race; post=$post; dist=$dist; raceName=$rn2; finished=$finished; cancelled=$cancelled; meta=$meta; horses=$horses } | ConvertTo-Json -Depth 6 -Compress
