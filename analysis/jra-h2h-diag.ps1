<#
  JRA h2h確度の改善診断: なぜh2h1位が弱いか。3方向を比較(全場2022-26 step3サンプルで高速化)。
  ①現行(全近走5/183日) vs ②同条件限定(今走と同コース種別×距離±200mの近走のみで連鎖)
  ③"支持の厚み"(h2h1位が対戦推定を持つ相手数=coverage)別に h2h1位 複勝率を分割 → 薄い時に弱いなら信頼度閾値が効く
  ④h2h1位∩コンピ上位3(合議)の複勝率
#>
[Console]::OutputEncoding=[Text.Encoding]::UTF8
$cs='Server=192.168.168.81\SQLEXPRESS;Database=中央競馬;User Id=sa;Password=Hanasaki#2093;TrustServerCertificate=True;Connect Timeout=30'
$cn=New-Object System.Data.SqlClient.SqlConnection $cs;$cn.Open();$c=$cn.CreateCommand();$c.CommandTimeout=900
function Q($sql){ $c.CommandText=$sql; $r=$c.ExecuteReader(); $t=New-Object System.Data.DataTable; $t.Load($r); ,$t }
$sw=[Diagnostics.Stopwatch]::StartNew()
function Median($a){ $s=@($a|Sort-Object); $n=$s.Count; if($n -eq 0){return $null}; if($n%2 -eq 1){return [double]$s[[int](($n-1)/2)]}; return ([double]$s[$n/2-1]+[double]$s[$n/2])/2.0 }
function DDiff($a,$b){ ([datetime]$a-[datetime]$b).Days }
$RecentN=5; $RecentDays=183

# 競走結果+レース情報(surf/dist)。レース->{馬名->時計}, 馬名->近走[{d,rk,surf,dist}]
$rr=Q "SELECT k.開催場所 v,CONVERT(varchar(10),k.開催日,23) d,k.レース番号 r,k.馬名 nm,k.馬番 no,TRY_CONVERT(int,k.着順) ch,TRY_CONVERT(float,k.走破時計) t,ri.コース種別 s,TRY_CAST(ri.距離 AS int) dist FROM dbo.競走結果 k JOIN dbo.レース情報 ri ON ri.開催場所=k.開催場所 AND ri.開催日=k.開催日 AND ri.レース番号=k.レース番号 AND ri.馬番=k.馬番 WHERE k.開催日>='2021-06-01' AND TRY_CONVERT(int,k.着順)>0 AND TRY_CONVERT(float,k.走破時計)>0"
$raceRes=@{}; $byHorse=@{}; $raceMeta=@{}
foreach($x in $rr.Rows){ $v=[string]$x.v;$d=[string]$x.d;$r=[int]$x.r;$nm=[string]$x.nm;$t=[double]$x.t;$s=[string]$x.s;$dist=[int]$x.dist
  $rk="$v|$d|$r"; if(-not $raceRes.ContainsKey($rk)){ $raceRes[$rk]=@{}; $raceMeta[$rk]=@{s=$s;dist=$dist} }; $raceRes[$rk][$nm]=$t
  if(-not $byHorse.ContainsKey($nm)){ $byHorse[$nm]=New-Object System.Collections.Generic.List[object] }
  $byHorse[$nm].Add([pscustomobject]@{ d=$d; r=$r; rk=$rk; s=$s; dist=$dist }) }
foreach($nm in @($byHorse.Keys)){ $byHorse[$nm]=@($byHorse[$nm]|Sort-Object d,r) }
$raceWin=@{}; foreach($rk in $raceRes.Keys){ $vals=@($raceRes[$rk].Values); if($vals.Count){ $raceWin[$rk]=($vals|Measure-Object -Minimum).Minimum } }
Write-Host ("競走結果 {0}レース  [{1:N0}s]" -f $raceRes.Count,$sw.Elapsed.TotalSeconds)
$crk=@{}; foreach($x in (Q "SELECT 開催場所 v,CONVERT(varchar(10),開催日,23) d,レース番号 r,馬名 nm,指数順位 rk FROM (SELECT 開催場所,開催日,レース番号,馬名,指数順位,ROW_NUMBER() OVER(PARTITION BY 開催場所,開催日,レース番号,馬名 ORDER BY 取得日時 DESC) sn FROM dbo.コンピ指数 WHERE 開催日>='2022-01-01' AND 指数順位 IS NOT NULL) z WHERE sn=1").Rows){ $crk["$($x.v)|$($x.d)|$($x.r)|$($x.nm)"]=[int]$x.rk }
$fukuPay=@{}; foreach($x in (Q "SELECT 開催場所 v,CONVERT(varchar(10),開催日,23) d,レース番号 r,組番 kb,TRY_CAST(金額 AS int) kin FROM dbo.払戻金 WHERE 開催日>='2022-01-01' AND 馬券=N'複勝'").Rows){ $no=0; if([int]::TryParse(("$($x.kb)").Trim(),[ref]$no)){ $fukuPay["$($x.v)|$($x.d)|$($x.r)|$no"]=[int]$x.kin } }
$noOf=@{}; $chOf=@{}; foreach($x in $rr.Rows){ if($x.d -lt '2022-01-01'){continue}; $k="$($x.v)|$($x.d)|$($x.r)|$($x.nm)"; $noOf[$k]=[int]$x.no; $chOf[$k]=[int]$x.ch }
Write-Host ("コンピ{0} 複勝払{1}  [{2:N0}s]" -f $crk.Count,$fukuPay.Count,$sw.Elapsed.TotalSeconds)

$targets=@(); $seen=@{}; foreach($k in $crk.Keys){ $p=$k -split '\|'; $rk="$($p[0])|$($p[1])|$($p[2])"; if(-not $seen.ContainsKey($rk)){ $seen[$rk]=$true; $targets+=$rk } }
$targets=@($targets|Sort-Object); $samp=@(); for($i=0;$i -lt $targets.Count;$i+=3){ $samp+=$targets[$i] }
Write-Host ("対象(step3): {0}  [{1:N0}s]" -f $samp.Count,$sw.Elapsed.TotalSeconds)

$acc=@{}; function Add($key,$top3,$fp){ if(-not $acc.ContainsKey($key)){ $acc[$key]=@{n=0;t3=0;inv=0;fuk=0} }; $a=$acc[$key]; $a.n++; if($top3){$a.t3++}; $a.inv+=100; $a.fuk+=$fp }
function T3($rk,$nm){ $k="$rk|$nm"; $ch= if($chOf.ContainsKey($k)){$chOf[$k]}else{99}; $no= if($noOf.ContainsKey($k)){$noOf[$k]}else{0}; $t3=($ch -le 3); $fp= if($t3){ $kk="$rk|$no"; if($fukuPay.ContainsKey($kk)){$fukuPay[$kk]}else{0} }else{0}; return @($t3,$fp) }
# h2h計算(sameCond=$true で同条件近走のみ)。coverage=相手のうちPairM取得できた数
function H2H($rk,$field,$tS,$tD,$sameCond){
  $mavg=@{}
  foreach($a in $field){ $mavg[$a]=@{}
    $rec=@(); if($byHorse.ContainsKey($a)){ foreach($h in ($byHorse[$a]|Sort-Object d,r -Descending)){ if($h.d -ge $d0){ } ; if($h.rk.Split('|')[1] -lt $d0){}; if($h.d -lt $d0 -and (DDiff $d0 $h.d) -le $RecentDays){ if($sameCond -and -not($h.s -eq $tS -and [math]::Abs($h.dist-$tD) -le 200)){ continue }; $rec+=$h.rk; if($rec.Count -ge $RecentN){break} } } }
    $tmp=@{}
    foreach($kk in $rec){ $res=$raceRes[$kk]; if(-not $res.ContainsKey($a)){continue}; $ta=$res[$kk]; $wt=$raceWin[$kk]; if(-not $wt){continue}
      foreach($x in $res.Keys){ if($x -eq $a){continue}; $rel=($res[$x]-$ta)/$wt*100.0; if($rel -gt 8){$rel=8}elseif($rel -lt -8){$rel=-8}; if(-not $tmp.ContainsKey($x)){$tmp[$x]=New-Object System.Collections.Generic.List[double]}; $tmp[$x].Add([double]$rel) } }
    foreach($x in $tmp.Keys){ $mavg[$a][$x]=Median $tmp[$x] } }
  $fset=@{}; $field|ForEach-Object{$fset[$_]=$true}
  $h2h=@{}; $cov=@{}
  foreach($a in $field){ $ms=@(); $cc=0
    foreach($b in $field){ if($a -eq $b){continue}
      $vv=@(); if($mavg[$a].ContainsKey($b)){$vv+=$mavg[$a][$b]}; if($mavg[$b].ContainsKey($a)){$vv+=(-1.0*$mavg[$b][$a])}
      $m=$null; if($vv.Count){ $m=($vv|Measure-Object -Average).Average }else{ $common=@($mavg[$a].Keys|Where-Object{$mavg[$b].ContainsKey($_) -and $_ -ne $a -and $_ -ne $b}); if($common.Count){ $fc=@($common|Where-Object{$fset.ContainsKey($_)}); $use= if($fc.Count){$fc}else{$common}; $est=foreach($q in $use){$mavg[$a][$q]-$mavg[$b][$q]}; $m=(Median $est) } }
      if($null -ne $m){ $ms+=$m; $cc++ } }
    if($ms.Count){ $h2h[$a]=($ms|Measure-Object -Average).Average; $cov[$a]=$cc } }
  return @($h2h,$cov)
}
$d0=''; $cnt=0
foreach($rk in $samp){ $parts=$rk -split '\|'; $d0=$parts[1]
  if(-not $raceRes.ContainsKey($rk)){ continue }; $field=@($raceRes[$rk].Keys); if($field.Count -lt 6){ continue }
  $tS=$raceMeta[$rk].s; $tD=$raceMeta[$rk].dist
  foreach($mode in 'all','cond'){
    $res=H2H $rk $field $tS $tD ($mode -eq 'cond'); $h2h=$res[0]; $cov=$res[1]
    if($h2h.Count -lt 3){ continue }
    $h1=@($h2h.GetEnumerator()|Sort-Object Value -Descending)[0].Key
    $t=T3 $rk $h1
    Add "h2h1位($mode)" $t[0] $t[1]
    # coverage別(全相手中の被覆率)
    $covPct= if($field.Count -gt 1){ [double]$cov[$h1]/($field.Count-1) }else{0}
    $bucket= if($covPct -ge 0.8){'厚80+'}elseif($covPct -ge 0.5){'中50-79'}else{'薄<50'}
    Add "h2h1位($mode)_$bucket" $t[0] $t[1]
    # コンピ合議
    $ck="$rk|$h1"; $comp= if($crk.ContainsKey($ck)){$crk[$ck]}else{99}
    if($comp -le 3){ Add "h2h1位($mode)∩コンピ3内" $t[0] $t[1] }else{ Add "h2h1位($mode)×コンピ4+" $t[0] $t[1] }
  }
  # ベース: コンピ1位
  $comp1=$null; foreach($a in $field){ if($crk.ContainsKey("$rk|$a") -and $crk["$rk|$a"] -eq 1){ $comp1=$a;break } }
  if($comp1){ $t=T3 $rk $comp1; Add 'BASE_コンピ1位' $t[0] $t[1] }
  $cnt++; if($cnt % 1000 -eq 0){ Write-Host ("  ...{0}/{1}  [{2:N0}s]" -f $cnt,$samp.Count,$sw.Elapsed.TotalSeconds) }
}
$cn.Close()
function Pc($a,$b){ if($b){'{0,6:P1}' -f ($a/$b)}else{'  — '} }
function Line($k){ if(-not $acc.ContainsKey($k)){ Write-Host ("{0,-26} n=0" -f $k); return }; $a=$acc[$k]; Write-Host ("{0,-26} {1,5} 複勝{2} 複回収{3}" -f $k,$a.n,(Pc $a.t3 $a.n),(Pc $a.fuk $a.inv)) }
Write-Host "`n===== h2h確度 診断 (全場2022-26 step3) ====="
foreach($k in 'BASE_コンピ1位','h2h1位(all)','h2h1位(cond)','h2h1位(all)_厚80+','h2h1位(all)_中50-79','h2h1位(all)_薄<50','h2h1位(cond)_厚80+','h2h1位(cond)_薄<50','h2h1位(all)∩コンピ3内','h2h1位(all)×コンピ4+','h2h1位(cond)∩コンピ3内'){ Line $k }
Write-Host ("`n[{0:N0}s]" -f $sw.Elapsed.TotalSeconds)
