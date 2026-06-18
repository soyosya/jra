<#
.SYNOPSIS
  軸有力度に基づく馬券(単勝/複勝/ワイド)の回収率を検証。ワイドの相手は軸有力度で自動選定。
  あわせて「相手のh2h強さで加重した精緻版h2h」が軸の的中を上げるかも比較します。

.DESCRIPTION
  軸有力度 = h2h(共通対戦相手の着差) + 脚質適性 + 騎手 + 枠 を Z加重(既定 0.5/0.2/0.2/0.1)。
  - 軸 = 軸有力度#1
  - ワイド相手 = 軸有力度#2,#3,#4 を自動選定(軸-相手の流し)
  ベット戦略の回収率(払戻金ベース)を集計:
    単勝#1 / 複勝#1 / ワイド軸-#2(1点) / 軸-#2#3(2点) / 軸-#2#3#4(3点)
  精緻版h2h: 各馬のh2hを「相手のh2h強さ(plainのZ)で加重平均」し直したもの。通常版と軸#1の
  勝率/複勝率を比較し、相手強度加重が効くかを判定。

  コース傾向/騎手勝率は全期間、ばんえい除外、馬の同定は馬名。
#>
[CmdletBinding()]
param(
    [string]$Venue = '大井',
    [string]$TestFrom = '2025-09-01',
    [string]$TestTo = '2026-06-14',
    [int]$RecentN = 5, [int]$RecentDays = 183, [int]$MinCompare = 4,
    [double]$Wh = 0.5, [double]$Wk = 0.2, [double]$Wj = 0.2, [double]$Wd = 0.1
)
$ErrorActionPreference = 'Stop'
$appsettings = Join-Path $PSScriptRoot '..\共通\appsettings.json'
$connStr = (Get-Content $appsettings -Raw -Encoding UTF8 | ConvertFrom-Json).ConnectionStrings.DefaultConnection
$conn = New-Object System.Data.SqlClient.SqlConnection($connStr); $conn.Open()
function Median($a){ $s=@($a|Sort-Object); $n=$s.Count; if($n -eq 0){return $null}; if($n%2 -eq 1){return [double]$s[[int](($n-1)/2)]}; return ([double]$s[$n/2-1]+[double]$s[$n/2])/2.0 }
function StyleOf([int]$e,[int]$n){ if($e -le 0 -or $n -le 0){return '?'}; if($e -eq 1){return '逃げ'}; if($e -le $n*0.33){return '先行'}; if($e -le $n*0.66){return '差し'}; return '追込' }
function Zmap($m){ $v=@($m.Values); $z=@{}; if($v.Count -eq 0){return $z}; $mean=($v|Measure-Object -Average).Average; $sd= if($v.Count -gt 1){[Math]::Sqrt((($v|ForEach-Object{($_-$mean)*($_-$mean)})|Measure-Object -Sum).Sum/($v.Count-1))}else{0}; foreach($k in $m.Keys){ $z[$k]= if($sd -gt 0){($m[$k]-$mean)/$sd}else{0.0} }; return $z }

try {
    $histFrom=([datetime]$TestFrom).AddDays(-$RecentDays).ToString('yyyy-MM-dd')
    Write-Host "ロード中..."
    $cmd=$conn.CreateCommand(); $cmd.CommandTimeout=600
    $cmd.CommandText=@"
SELECT kk.開催場所 v, kk.開催日 d, kk.レース番号 rno, kk.馬番 uma, kk.馬名 nm, kk.着順 c, kk.走破時計 t,
  COALESCE(NULLIF(kk.一コーナー,0),NULLIF(kk.二コーナー,0),NULLIF(kk.三コーナー,0),NULLIF(kk.四コーナー,0)) early, r.距離 dist, r.騎手 jk
FROM 競走結果 kk LEFT JOIN レース情報 r ON r.開催場所=kk.開催場所 AND r.開催日=kk.開催日 AND r.レース番号=kk.レース番号 AND r.馬番=kk.馬番
WHERE kk.着順>0 AND kk.走破時計>0 AND kk.開催日>=@h AND kk.開催日<=@t AND kk.開催場所 NOT LIKE '%ば'
ORDER BY kk.開催日, kk.レース番号
"@
    [void]$cmd.Parameters.AddWithValue('@h',$histFrom);[void]$cmd.Parameters.AddWithValue('@t',$TestTo)
    $r=$cmd.ExecuteReader(); $races=@{}; $horseRuns=@{}
    while($r.Read()){
        $v=$r.GetString(0);$d=$r.GetDateTime(1);$rno=$r.GetInt32(2);$uma=$r.GetInt32(3);$nm=$r.GetString(4);$c=$r.GetInt32(5);$t=[double]$r.GetDecimal(6)
        $early= if($r.IsDBNull(7)){0}else{[int]$r.GetValue(7)}; $dist= if($r.IsDBNull(8)){0}else{[int]$r.GetValue(8)}; $jk= if($r.IsDBNull(9)){''}else{$r.GetString(9)}
        $key='{0}|{1:yyyy-MM-dd}|{2}' -f $v,$d,$rno
        if(-not $races.ContainsKey($key)){ $races[$key]=@{rows=(New-Object System.Collections.Generic.List[object]);win=[double]::MaxValue;v=$v;d=$d;rno=$rno;dist=$dist} }
        $races[$key].rows.Add(@{uma=$uma;nm=$nm;c=$c;t=$t;early=$early;jk=$jk}); if($t -lt $races[$key].win){$races[$key].win=$t}
        if($dist -gt 0 -and $races[$key].dist -eq 0){$races[$key].dist=$dist}
        if(-not $horseRuns.ContainsKey($nm)){$horseRuns[$nm]=(New-Object System.Collections.Generic.List[object])}; $horseRuns[$nm].Add(@{date=$d;key=$key})
    }
    $r.Close(); Write-Host ("  {0:N0}レース / {1:N0}頭" -f $races.Count,$horseRuns.Count)

    $styleWin=@{}; $drawWin=@{}
    foreach($key in $races.Keys){ $rc=$races[$key]; if($rc.dist -le 0){continue}; $n=$rc.rows.Count; $ck="$($rc.v)|$($rc.dist)"
        if(-not $styleWin.ContainsKey($ck)){$styleWin[$ck]=@{};$drawWin[$ck]=@{}}
        foreach($row in $rc.rows){ $st=StyleOf $row.early $n
            if($st -ne '?'){ if(-not $styleWin[$ck].ContainsKey($st)){$styleWin[$ck][$st]=@{n=0;w=0}}; $styleWin[$ck][$st].n++; if($row.c -eq 1){$styleWin[$ck][$st].w++} }
            $g= if($row.uma -le 4){'内'}elseif($row.uma -le 8){'中'}else{'外'}; if(-not $drawWin[$ck].ContainsKey($g)){$drawWin[$ck][$g]=@{n=0;w=0}}; $drawWin[$ck][$g].n++; if($row.c -eq 1){$drawWin[$ck][$g].w++} }
    }
    function Rate($h){ if($null -eq $h -or $h.n -eq 0){return $null}; return [double]$h.w/$h.n }
    $jWin=@{}
    foreach($key in $races.Keys){ $rc=$races[$key]; foreach($row in $rc.rows){ if($row.jk -eq ''){continue}; $jk="$($rc.v)|$($row.jk)"; if(-not $jWin.ContainsKey($jk)){$jWin[$jk]=@{n=0;w=0}}; $jWin[$jk].n++; if($row.c -eq 1){$jWin[$jk].w++} } }

    # 払戻(単勝/複勝/ワイド)
    $tansho=@{}; $fuku=@{}; $wide=@{}
    $cmd2=$conn.CreateCommand(); $cmd2.CommandTimeout=300
    $cmd2.CommandText="SELECT 開催日,レース番号,馬券,組番,金額 FROM 払戻金 WHERE 開催場所=@v AND 開催日>=@f AND 開催日<=@t AND 馬券 IN (N'単勝',N'複勝',N'ワイド')"
    [void]$cmd2.Parameters.AddWithValue('@v',$Venue);[void]$cmd2.Parameters.AddWithValue('@f',$TestFrom);[void]$cmd2.Parameters.AddWithValue('@t',$TestTo)
    $r2=$cmd2.ExecuteReader()
    while($r2.Read()){ $key='{0}|{1:yyyy-MM-dd}|{2}' -f $Venue,$r2.GetDateTime(0),$r2.GetInt32(1); $bk=$r2.GetString(2); $kumi=($r2.GetValue(3)).ToString().Trim(); $amt=[double]$r2.GetValue(4)
        if($bk -eq '単勝'){ if(-not $tansho.ContainsKey($key)){$tansho[$key]=@{}}; $tansho[$key][$kumi]=$amt }
        elseif($bk -eq '複勝'){ if(-not $fuku.ContainsKey($key)){$fuku[$key]=@{}}; $fuku[$key][$kumi]=$amt }
        else { $parts=$kumi -split '[-=]'; if($parts.Count -eq 2){ $p=@([int]$parts[0],[int]$parts[1]|Sort-Object); $pk="$($p[0])-$($p[1])"; if(-not $wide.ContainsKey($key)){$wide[$key]=@{}}; $wide[$key][$pk]=$amt } }
    }
    $r2.Close()

    # ===== 各対象レースの軸順(通常/精緻) =====
    $targets=$races.Values|Where-Object{$_.v -eq $Venue -and $_.d -ge [datetime]$TestFrom -and $_.d -le [datetime]$TestTo}|Sort-Object d,rno
    $store=@()
    foreach($rc in $targets){ $rows=$rc.rows; if($rows.Count -lt 4){continue}
        $field=@($rows|ForEach-Object{$_.nm}); $fieldSet=@{}; $field|ForEach-Object{$fieldSet[$_]=$true}; $td=$rc.d; $ck="$($rc.v)|$($rc.dist)"
        $mavg=@{}
        foreach($a in $field){ $mavg[$a]=@{}; $tmp=@{}
            if($horseRuns.ContainsKey($a)){ $runs=@($horseRuns[$a]|Where-Object{$_.date -lt $td -and $_.date -ge $td.AddDays(-$RecentDays)}|Sort-Object date -Descending|Select-Object -First $RecentN)
                foreach($run in $runs){ $rr=$races[$run.key]; $wt=$rr.win; if($wt -le 0){continue}; $ta=($rr.rows|Where-Object{$_.nm -eq $a}|Select-Object -First 1).t
                    foreach($h in $rr.rows){ if($h.nm -eq $a){continue}; $rel=($h.t-$ta)/$wt*100.0; if($rel -gt 8){$rel=8}elseif($rel -lt -8){$rel=-8}; if(-not $tmp.ContainsKey($h.nm)){$tmp[$h.nm]=New-Object System.Collections.Generic.List[double]}; $tmp[$h.nm].Add($rel) } } }
            foreach($x in $tmp.Keys){ $mavg[$a][$x]=Median $tmp[$x] } }
        function PairM2($a,$b){ $v=@(); if($mavg[$a].ContainsKey($b)){$v+=$mavg[$a][$b]}; if($mavg[$b].ContainsKey($a)){$v+=(-1.0*$mavg[$b][$a])}; if($v.Count -gt 0){return (($v|Measure-Object -Average).Average)}
            $common=@($mavg[$a].Keys|Where-Object{$mavg[$b].ContainsKey($_) -and $_ -ne $a -and $_ -ne $b}); if($common.Count -eq 0){return $null}
            $fc=@($common|Where-Object{$fieldSet.ContainsKey($_)}); $use= if($fc.Count -gt 0){$fc}else{$common}; $est=foreach($c in $use){$mavg[$a][$c]-$mavg[$b][$c]}; return (Median $est) }
        # ペア行列
        $pm=@{}; foreach($a in $field){ $pm[$a]=@{}; foreach($b in $field){ if($a -ne $b){ $m=PairM2 $a $b; if($null -ne $m){$pm[$a][$b]=$m} } } }
        $h2h=@{}; $cmpCnt=@{}
        foreach($a in $field){ $vals=@($pm[$a].Values); $cmpCnt[$a]=$vals.Count; if($vals.Count -ge 1){$h2h[$a]=($vals|Measure-Object -Average).Average} }
        $zhPlain=Zmap $h2h
        # 精緻版: 相手のh2h強さ(plain Z)で加重平均(beating strong = more credit)
        $h2hW=@{}
        foreach($a in $field){ if(-not $h2h.ContainsKey($a)){continue}; $num=0.0;$den=0.0
            foreach($b in $pm[$a].Keys){ $wz= if($zhPlain.ContainsKey($b)){[Math]::Exp([double]$zhPlain[$b])}else{1.0}; $num+=$wz*$pm[$a][$b]; $den+=$wz }
            if($den -gt 0){$h2hW[$a]=$num/$den} }
        # 他要素
        $kyaku=@{};$draw=@{};$jock=@{}
        foreach($row in $rows){ $a=$row.nm; $cnt=@{}
            if($horseRuns.ContainsKey($a)){ $runs=@($horseRuns[$a]|Where-Object{$_.date -lt $td -and $_.date -ge $td.AddDays(-$RecentDays)}|Sort-Object date -Descending|Select-Object -First $RecentN)
                foreach($run in $runs){ $rr=$races[$run.key]; $me=($rr.rows|Where-Object{$_.nm -eq $a}|Select-Object -First 1); if($null -eq $me){continue}; $s=StyleOf $me.early $rr.rows.Count; if($s -ne '?'){$cnt[$s]=$cnt[$s]+1} } }
            $st= if($cnt.Count -gt 0){($cnt.GetEnumerator()|Sort-Object Value -Descending|Select-Object -First 1).Key}else{'?'}
            $kr= if($st -ne '?' -and $styleWin.ContainsKey($ck)){Rate $styleWin[$ck][$st]}else{$null}; $kyaku[$a]= if($null -ne $kr){$kr}else{0.0}
            $g= if($row.uma -le 4){'内'}elseif($row.uma -le 8){'中'}else{'外'}; $dr= if($drawWin.ContainsKey($ck)){Rate $drawWin[$ck][$g]}else{$null}; $draw[$a]= if($null -ne $dr){$dr}else{0.0}
            $jr= if($row.jk -ne '' -and $jWin.ContainsKey("$($rc.v)|$($row.jk)")){$hh=$jWin["$($rc.v)|$($row.jk)"]; if($hh.n -ge 30){[double]$hh.w/$hh.n}else{$null}}else{$null}; $jock[$a]= if($null -ne $jr){$jr}else{0.0} }
        $zk=Zmap $kyaku; $zj=Zmap $jock; $zd=Zmap $draw; $zhW=Zmap $h2hW
        $ents=foreach($row in $rows){ $a=$row.nm
            $ok=($h2h.ContainsKey($a) -and $cmpCnt[$a] -ge $MinCompare)
            $axisP= $Wh*[double]($zhPlain[$a])+$Wk*[double]($zk[$a])+$Wj*[double]($zj[$a])+$Wd*[double]($zd[$a])
            $axisW= $Wh*[double]($zhW[$a])+$Wk*[double]($zk[$a])+$Wj*[double]($zj[$a])+$Wd*[double]($zd[$a])
            @{ uma=$row.uma; c=$row.c; ok=$ok; axisP=$axisP; axisW=$axisW }
        }
        $store += @{ key=('{0}|{1:yyyy-MM-dd}|{2}' -f $rc.v,$rc.d,$rc.rno); ents=$ents }
    }
    Write-Host ("対象レース: {0:N0}`n" -f $store.Count)

    # ===== 軸的中: 通常 vs 精緻 =====
    foreach($mode in @('axisP','axisW')){
        $n=0;$w=0;$t3=0
        foreach($race in $store){ $cand=@($race.ents|Where-Object{$_.ok}); if($cand.Count -eq 0){continue}
            $top=($cand|Sort-Object {$_.$mode} -Descending|Select-Object -First 1); $n++; if($top.c -eq 1){$w++}; if($top.c -le 3){$t3++} }
        $label= if($mode -eq 'axisP'){'通常h2h'}else{'精緻h2h(相手強度加重)'}
        Write-Host ("[軸#1的中] {0,-22} 勝率{1,5:P1} 複勝率{2,5:P1}  ({3}レース)" -f $label,($w/$n),($t3/$n),$n)
    }

    # ===== ベット回収率(通常軸 axisP を使用) =====
    function BetReport($ents,$key){ return }
    $strat=@{}
    foreach($nm in @('単勝#1','複勝#1','ワイド軸-#2','ワイド軸-#2#3','ワイド軸-#2#3#4')){ $strat[$nm]=@{bets=0;ret=0.0;hitRaces=0;races=0} }
    foreach($race in $store){
        $cand=@($race.ents|Where-Object{$_.ok}|Sort-Object {$_.axisP} -Descending); if($cand.Count -lt 1){continue}
        $key=$race.key; $a1=$cand[0]
        # 単勝
        $s=$strat['単勝#1']; $s.races++; $s.bets++; if($a1.c -eq 1 -and $tansho.ContainsKey($key) -and $tansho[$key].ContainsKey("$($a1.uma)")){ $s.ret+=$tansho[$key]["$($a1.uma)"]/100.0; $s.hitRaces++ }
        # 複勝
        $s=$strat['複勝#1']; $s.races++; $s.bets++; if($a1.c -le 3 -and $fuku.ContainsKey($key) -and $fuku[$key].ContainsKey("$($a1.uma)")){ $s.ret+=$fuku[$key]["$($a1.uma)"]/100.0; $s.hitRaces++ }
        # ワイド 軸-相手流し
        $partnersList=@(@('ワイド軸-#2',1),@('ワイド軸-#2#3',2),@('ワイド軸-#2#3#4',3))
        foreach($pl in $partnersList){ $nmS=$pl[0]; $K=$pl[1]; if($cand.Count -lt ($K+1)){continue}
            $s=$strat[$nmS]; $s.races++; $hit=$false
            for($i=1;$i -le $K;$i++){ $p=$cand[$i]; $s.bets++
                $pp=@([int]$a1.uma,[int]$p.uma|Sort-Object); $pk="$($pp[0])-$($pp[1])"
                if($wide.ContainsKey($key) -and $wide[$key].ContainsKey($pk)){ $s.ret+=$wide[$key][$pk]/100.0; $hit=$true } }
            if($hit){$s.hitRaces++} }
    }
    Write-Host ("`n=== ベット回収率 (軸=通常h2hブレンド, 相手=軸有力度で自動選定) {0} {1}〜{2} ===" -f $Venue,$TestFrom,$TestTo)
    $rep=foreach($nm in @('単勝#1','複勝#1','ワイド軸-#2','ワイド軸-#2#3','ワイド軸-#2#3#4')){ $s=$strat[$nm]
        [PSCustomObject]@{ 戦略=$nm; レース=$s.races; 購入点=$s.bets; 的中レース率=if($s.races){'{0:P1}' -f ($s.hitRaces/$s.races)}else{''}; 回収率=if($s.bets){'{0:P1}' -f ($s.ret/$s.bets)}else{''} } }
    $rep | Format-Table 戦略,レース,購入点,的中レース率,回収率 -AutoSize | Out-String -Width 200 | Write-Host
}
finally { $conn.Close() }
