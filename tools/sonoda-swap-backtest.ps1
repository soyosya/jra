[CmdletBinding()]
param(
    [string]$Venue='園田',
    [string]$From='2025-04-01',
    [string]$To='2025-06-30',
    [int]$RecentN=5, [int]$RecentDays=183, [int]$MinCompare=3,
    [int]$NumPartner=4,
    [double]$Wh=0.5,[double]$Wk=0.2,[double]$Wj=0.2,[double]$Wd=0.1,
    [double]$TrustWin=0.15,[int]$TrustMinRides=100
)
$ErrorActionPreference='Stop'
$appsettings = Join-Path $PSScriptRoot '..\共通\appsettings.json'
$connStr=(Get-Content $appsettings -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
$conn=New-Object System.Data.SqlClient.SqlConnection($connStr); $conn.Open()
function Median($a){ $s=@($a|Sort-Object); $n=$s.Count; if($n -eq 0){return $null}; if($n%2 -eq 1){return [double]$s[[int](($n-1)/2)]}; return ([double]$s[$n/2-1]+[double]$s[$n/2])/2.0 }
function StyleOf([int]$e,[int]$n){ if($e -le 0 -or $n -le 0){return '?'}; if($e -eq 1){return '逃げ'}; if($e -le $n*0.33){return '先行'}; if($e -le $n*0.66){return '差し'}; return '追込' }
function Zmap($m){ $v=@($m.Values); $z=@{}; if($v.Count -eq 0){return $z}; $mean=($v|Measure-Object -Average).Average; $sd= if($v.Count -gt 1){[Math]::Sqrt((($v|ForEach-Object{($_-$mean)*($_-$mean)})|Measure-Object -Sum).Sum/($v.Count-1))}else{0}; foreach($k in $m.Keys){ $z[$k]= if($sd -gt 0){($m[$k]-$mean)/$sd}else{0.0} }; return $z }
function Invoke-Rows([string]$sql,[hashtable]$p){ $c=$conn.CreateCommand();$c.CommandTimeout=600;$c.CommandText=$sql; foreach($k in $p.Keys){[void]$c.Parameters.AddWithValue($k,$p[$k])}; $rd=$c.ExecuteReader(); $o=@(); while($rd.Read()){ $h=@{}; for($i=0;$i -lt $rd.FieldCount;$i++){ $h[$rd.GetName($i)]= if($rd.IsDBNull($i)){$null}else{$rd.GetValue($i)} }; $o+=[PSCustomObject]$h }; $rd.Close(); return $o }
try {
    $histFrom=([datetime]$From).AddDays(-$RecentDays).ToString('yyyy-MM-dd')
    $races=@{}; $horseRuns=@{}
    $hc=$conn.CreateCommand(); $hc.CommandTimeout=600
    $hc.CommandText=@"
SELECT kk.開催場所, kk.開催日, kk.レース番号, kk.馬名, kk.着順, kk.走破時計, kk.馬番,
  COALESCE(NULLIF(kk.一コーナー,0),NULLIF(kk.二コーナー,0),NULLIF(kk.三コーナー,0),NULLIF(kk.四コーナー,0))
FROM 競走結果 kk WHERE kk.着順>0 AND kk.走破時計>0 AND kk.開催日>=@h AND kk.開催日<=@to AND kk.開催場所 NOT LIKE '%ば'
"@
    [void]$hc.Parameters.AddWithValue('@h',$histFrom); [void]$hc.Parameters.AddWithValue('@to',$To)
    $rd=$hc.ExecuteReader()
    while($rd.Read()){ $v=$rd.GetString(0);$d=$rd.GetDateTime(1);$rno=$rd.GetInt32(2);$nm=$rd.GetString(3);$c=$rd.GetInt32(4);$t=[double]$rd.GetDecimal(5);$uma=$rd.GetInt32(6);$early= if($rd.IsDBNull(7)){0}else{[int]$rd.GetValue(7)}
        $key='{0}|{1:yyyy-MM-dd}|{2}' -f $v,$d,$rno
        if(-not $races.ContainsKey($key)){ $races[$key]=@{rows=(New-Object System.Collections.Generic.List[object]);win=[double]::MaxValue} }
        $races[$key].rows.Add(@{nm=$nm;t=$t;c=$c;uma=$uma;early=$early}); if($t -lt $races[$key].win){$races[$key].win=$t}
        if(-not $horseRuns.ContainsKey($nm)){$horseRuns[$nm]=(New-Object System.Collections.Generic.List[object])}; $horseRuns[$nm].Add(@{date=$d;key=$key})
    }
    $rd.Close()
    function Rate($h){ if($null -eq $h -or $h.n -eq 0){return $null}; return [double]$h.w/$h.n }
    $styleWin=@{}; $drawWin=@{}
    $sb = Invoke-Rows @"
WITH k AS (SELECT kk.開催場所 v, r.距離 dist, kk.着順 c, COALESCE(NULLIF(kk.一コーナー,0),NULLIF(kk.二コーナー,0),NULLIF(kk.三コーナー,0),NULLIF(kk.四コーナー,0)) early, COUNT(*) OVER(PARTITION BY kk.開催場所,kk.開催日,kk.レース番号) tou
  FROM 競走結果 kk JOIN レース情報 r ON r.開催場所=kk.開催場所 AND r.開催日=kk.開催日 AND r.レース番号=kk.レース番号 AND r.馬番=kk.馬番
  WHERE kk.着順>0 AND kk.開催日>='2022-01-01' AND kk.開催日<@f AND kk.開催場所 NOT LIKE '%ば')
SELECT v, dist, 脚質=CASE WHEN early IS NULL OR early=0 THEN N'?' WHEN early=1 THEN N'逃げ' WHEN early<=tou*0.33 THEN N'先行' WHEN early<=tou*0.66 THEN N'差し' ELSE N'追込' END, COUNT(*) n, SUM(CASE WHEN c=1 THEN 1 ELSE 0 END) w
FROM k GROUP BY v, dist, CASE WHEN early IS NULL OR early=0 THEN N'?' WHEN early=1 THEN N'逃げ' WHEN early<=tou*0.33 THEN N'先行' WHEN early<=tou*0.66 THEN N'差し' ELSE N'追込' END
"@ @{'@f'=$From}
    foreach($x in $sb){ if($null -eq $x.dist){continue}; $ck="$($x.v)|$([int]$x.dist)"; if(-not $styleWin.ContainsKey($ck)){$styleWin[$ck]=@{}}; $styleWin[$ck][[string]$x.脚質]=@{n=[int]$x.n;w=[int]$x.w} }
    $db = Invoke-Rows @"
SELECT kk.開催場所 v, r.距離 dist, CASE WHEN kk.馬番<=4 THEN N'内' WHEN kk.馬番<=8 THEN N'中' ELSE N'外' END grp, COUNT(*) n, SUM(CASE WHEN kk.着順=1 THEN 1 ELSE 0 END) w
FROM 競走結果 kk JOIN レース情報 r ON r.開催場所=kk.開催場所 AND r.開催日=kk.開催日 AND r.レース番号=kk.レース番号 AND r.馬番=kk.馬番
WHERE kk.着順>0 AND kk.開催日>='2022-01-01' AND kk.開催日<@f AND kk.開催場所 NOT LIKE '%ば'
GROUP BY kk.開催場所, r.距離, CASE WHEN kk.馬番<=4 THEN N'内' WHEN kk.馬番<=8 THEN N'中' ELSE N'外' END
"@ @{'@f'=$From}
    foreach($x in $db){ if($null -eq $x.dist){continue}; $ck="$($x.v)|$([int]$x.dist)"; if(-not $drawWin.ContainsKey($ck)){$drawWin[$ck]=@{}}; $drawWin[$ck][[string]$x.grp]=@{n=[int]$x.n;w=[int]$x.w} }
    $jr = Invoke-Rows @"
SELECT r.開催場所 v, r.騎手 jk, COUNT(*) n, SUM(CASE WHEN kk.着順=1 THEN 1 ELSE 0 END) w
FROM レース情報 r JOIN 競走結果 kk ON kk.開催場所=r.開催場所 AND kk.開催日=r.開催日 AND kk.レース番号=r.レース番号 AND kk.馬番=r.馬番
WHERE kk.着順>0 AND r.開催日>='2022-01-01' AND r.開催日<@f AND r.開催場所 NOT LIKE '%ば' GROUP BY r.開催場所, r.騎手
"@ @{'@f'=$From}
    $jStat=@{}; $ht=@{}
    foreach($x in $jr){ $n=[int]$x.n; if($n -ge 30){ $jStat["$($x.v)|$($x.jk)"]=[double]$x.w/$n }
        if([string]$x.v -eq $Venue -and $n -ge $TrustMinRides -and ([double]$x.w/$n) -ge $TrustWin){ $ht[[string]$x.jk]=$true } }
    $trioOrder=@{}; $trioPay=@{}
    $tp = Invoke-Rows "SELECT レース番号 rno, 開催日 d, LTRIM(RTRIM(組番)) k, 金額 a FROM 払戻金 WHERE 開催場所=@v AND 馬券=N'三連単' AND 開催日>=@f AND 開催日<=@to" @{'@v'=$Venue;'@f'=$From;'@to'=$To}
    foreach($x in $tp){ $key='{0:yyyy-MM-dd}|{1}' -f ([datetime]$x.d),[int]$x.rno; $o=@(($x.k -split '[-=]')|ForEach-Object{[int]$_})
        if($o.Count -eq 3){ if(-not $trioOrder.ContainsKey($key)){ $trioOrder[$key]=$o; $trioPay[$key]=[double]$x.a } } }
    $fuk=@{}
    $fp = Invoke-Rows "SELECT レース番号 rno, 開催日 d, LTRIM(RTRIM(組番)) k, 金額 a FROM 払戻金 WHERE 開催場所=@v AND 馬券=N'複勝' AND 開催日>=@f AND 開催日<=@to" @{'@v'=$Venue;'@f'=$From;'@to'=$To}
    foreach($x in $fp){ $key='{0:yyyy-MM-dd}|{1}' -f ([datetime]$x.d),[int]$x.rno; if(-not $fuk.ContainsKey($key)){$fuk[$key]=@{}}; $fuk[$key][[int]$x.k]=[double]$x.a }
    $ent = Invoke-Rows "SELECT 開催日 d, レース番号 rno, 馬番 uma, 馬名 nm, 騎手 jk, 距離 dist FROM レース情報 WHERE 開催場所=@v AND 開催日>=@f AND 開催日<=@to ORDER BY 開催日, レース番号, 馬番" @{'@v'=$Venue;'@f'=$From;'@to'=$To}
    if($ent.Count -eq 0){ Write-Host "出馬表なし"; return }
    $byRace = $ent | Group-Object d, rno
    $strats=@('base','rule2','rule2b')
    $ACC=@{}; foreach($s in $strats){ $ACC[$s]=@{formHit=0;formPts=0;formRet=0.0;multiHit=0;multiPts=0;multiRet=0.0;fukHit=0;fukRet=0.0;swap=0} }
    $nRace=0; $skipped=0
    foreach($grp in $byRace){
        $rws=$grp.Group; $d=[datetime]$rws[0].d; $rno=[int]$rws[0].rno; $dist=[int]$rws[0].dist; $ck="$Venue|$dist"; $td=$d
        $key='{0:yyyy-MM-dd}|{1}' -f $td,$rno
        if(-not $trioOrder.ContainsKey($key)){ $skipped++; continue }
        $field=@($rws|ForEach-Object{[string]$_.nm}); $fieldSet=@{}; $field|ForEach-Object{$fieldSet[$_]=$true}
        $mavg=@{}
        foreach($a in $field){ $mavg[$a]=@{}; $tmp=@{}
            if($horseRuns.ContainsKey($a)){ $runs=@($horseRuns[$a]|Where-Object{$_.date -lt $td -and $_.date -ge $td.AddDays(-$RecentDays)}|Sort-Object date -Descending|Select-Object -First $RecentN)
                foreach($run in $runs){ $rr=$races[$run.key]; $wt=$rr.win; if($wt -le 0){continue}; $me=($rr.rows|Where-Object{$_.nm -eq $a}|Select-Object -First 1); if($null -eq $me){continue}; $ta=$me.t
                    foreach($h in $rr.rows){ if($h.nm -eq $a){continue}; $rel=($h.t-$ta)/$wt*100.0; if($rel -gt 8){$rel=8}elseif($rel -lt -8){$rel=-8}; if(-not $tmp.ContainsKey($h.nm)){$tmp[$h.nm]=New-Object System.Collections.Generic.List[double]}; $tmp[$h.nm].Add($rel) } } }
            foreach($x in $tmp.Keys){ $mavg[$a][$x]=Median $tmp[$x] } }
        function PairM2($a,$b){ $vv=@(); if($mavg[$a].ContainsKey($b)){$vv+=$mavg[$a][$b]}; if($mavg[$b].ContainsKey($a)){$vv+=(-1.0*$mavg[$b][$a])}; if($vv.Count -gt 0){return (($vv|Measure-Object -Average).Average)}
            $common=@($mavg[$a].Keys|Where-Object{$mavg[$b].ContainsKey($_) -and $_ -ne $a -and $_ -ne $b}); if($common.Count -eq 0){return $null}
            $fc=@($common|Where-Object{$fieldSet.ContainsKey($_)}); $use= if($fc.Count -gt 0){$fc}else{$common}; $est=foreach($c in $use){$mavg[$a][$c]-$mavg[$b][$c]}; return (Median $est) }
        $h2h=@{};$cmp=@{}
        foreach($a in $field){ $ms=@(); foreach($b in $field){ if($a -ne $b){$m=PairM2 $a $b; if($null -ne $m){$ms+=$m}} }; $cmp[$a]=$ms.Count; if($ms.Count -ge 1){$h2h[$a]=($ms|Measure-Object -Average).Average} }
        $kyaku=@{};$draw=@{};$jock=@{};$styleOf=@{};$jkOf=@{}
        foreach($row in $rws){ $a=[string]$row.nm; $cnt=@{}
            if($horseRuns.ContainsKey($a)){ $runs=@($horseRuns[$a]|Where-Object{$_.date -lt $td -and $_.date -ge $td.AddDays(-$RecentDays)}|Sort-Object date -Descending|Select-Object -First $RecentN)
                foreach($run in $runs){ $rr=$races[$run.key]; $me=($rr.rows|Where-Object{$_.nm -eq $a}|Select-Object -First 1); if($null -eq $me){continue}; $s=StyleOf $me.early $rr.rows.Count; if($s -ne '?'){$cnt[$s]=$cnt[$s]+1} } }
            $st= if($cnt.Count -gt 0){($cnt.GetEnumerator()|Sort-Object Value -Descending|Select-Object -First 1).Key}else{'?'}
            $styleOf[$a]=$st; $jkOf[$a]=[string]$row.jk
            $kr= if($st -ne '?' -and $styleWin.ContainsKey($ck)){Rate $styleWin[$ck][$st]}else{$null}; $kyaku[$a]= if($null -ne $kr){$kr}else{0.0}
            $g= if([int]$row.uma -le 4){'内'}elseif([int]$row.uma -le 8){'中'}else{'外'}; $dr= if($drawWin.ContainsKey($ck)){Rate $drawWin[$ck][$g]}else{$null}; $draw[$a]= if($null -ne $dr){$dr}else{0.0}
            $jk=[string]$row.jk; $jw= if($jStat.ContainsKey("$Venue|$jk")){$jStat["$Venue|$jk"]}else{$null}; $jock[$a]= if($null -ne $jw){$jw}else{0.0} }
        $zh=Zmap $h2h;$zk=Zmap $kyaku;$zj=Zmap $jock;$zd=Zmap $draw
        $scored=foreach($row in $rws){ $a=[string]$row.nm; $ok=($h2h.ContainsKey($a) -and $cmp[$a] -ge $MinCompare)
            $axv=($Wh*[double]($zh[$a])+$Wk*[double]($zk[$a])+$Wj*[double]($zj[$a])+$Wd*[double]($zd[$a]))
            [PSCustomObject]@{ uma=[int]$row.uma; ax=$axv; ok=$ok; st=$styleOf[$a]; jk=$jkOf[$a] } }
        $cand=@($scored|Where-Object{$_.ok}|Sort-Object ax -Descending)
        if($cand.Count -lt ($NumPartner+1)){ $skipped++; continue }
        $o=$trioOrder[$key]; $payTri=$trioPay[$key]; $fr= if($fuk.ContainsKey($key)){$fuk[$key]}else{@{}}
        $oset=@{}; $o|ForEach-Object{$oset[$_]=$true}
        foreach($s in $strats){
            $a0=$cand[0]; $axisUma=$a0.uma; $doSwap=$false
            if($s -eq 'rule2'){ if((-not $ht.ContainsKey($a0.jk)) -and ($a0.st -eq '差し' -or $a0.st -eq '追込')){ $doSwap=$true } }
            elseif($s -eq 'rule2b'){ if($a0.st -eq '追込'){ $doSwap=$true } elseif($a0.st -eq '差し' -and (-not $ht.ContainsKey($a0.jk))){ $doSwap=$true } }
            if($doSwap){ $axisUma=$cand[1].uma; $ACC[$s].swap++ }
            $partners=@($cand|ForEach-Object{$_.uma}|Where-Object{$_ -ne $axisUma}|Select-Object -First $NumPartner)
            $pset=@{}; $partners|ForEach-Object{$pset[$_]=$true}
            $ACC[$s].formPts += ($NumPartner*($NumPartner-1))
            if($o[0] -eq $axisUma -and $pset.ContainsKey($o[1]) -and $pset.ContainsKey($o[2])){ $ACC[$s].formHit++; $ACC[$s].formRet += $payTri/100.0 }
            $ACC[$s].multiPts += (3*$NumPartner*($NumPartner-1))
            if($oset.ContainsKey($axisUma)){ $others=@($o|Where-Object{$_ -ne $axisUma}); if($others.Count -eq 2 -and $pset.ContainsKey($others[0]) -and $pset.ContainsKey($others[1])){ $ACC[$s].multiHit++; $ACC[$s].multiRet += $payTri/100.0 } }
            if($oset.ContainsKey($axisUma) -and $fr.ContainsKey($axisUma)){ $ACC[$s].fukHit++; $ACC[$s].fukRet += $fr[$axisUma]/100.0 }
        }
        $nRace++
    }
    Write-Host ("WINDOW {0} {1}..{2}  races={3} skipped={4}  highTrust={5}" -f $Venue,$From,$To,$nRace,$skipped,(($ht.Keys|Sort-Object) -join ','))
    foreach($s in $strats){ $r=$ACC[$s]
        Write-Host ("RESULT|{0}|{1}|races={2}|swap={3}|formHit={4}|formPts={5}|formRet={6}|multiHit={7}|multiPts={8}|multiRet={9}|fukHit={10}|fukRet={11}" -f $From,$s,$nRace,$r.swap,$r.formHit,$r.formPts,[int]$r.formRet,$r.multiHit,$r.multiPts,[int]$r.multiRet,$r.fukHit,[int]$r.fukRet)
    }
}
finally { $conn.Close() }
