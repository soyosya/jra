<#
.SYNOPSIS
  指定場・期間の全レースで「3連複 軸ながし」の的中率・回収率を検証します。

.DESCRIPTION
  各レースをレーティング(軸有力度: h2h+脚質+騎手+枠, 0.5/0.2/0.2/0.1)で順位付け。
  - NumAxis=1: 軸=1位、相手=2〜(1+NumPartner)位。買い目={軸,相手2頭} の全組合せ C(NumPartner,2)点
  - NumAxis=2: 軸=1・2位、相手=3〜(2+NumPartner)位。買い目={軸1,軸2,相手} の NumPartner点
  実際の三連複払戻に該当組番があれば的中(払戻/100を回収)。コスト=点数×1。
  コース傾向・騎手勝率は検証開始(From)より前の2024+から算出(リーク回避)。ばんえい除外。

.PARAMETER Venue / From / To
  検証場・対象期間(yyyy-MM-dd)。
.PARAMETER NumAxis / NumPartner
  軸頭数(1か2)と相手頭数。既定 軸1・相手5(=10点)。
.EXAMPLE
  .\trio-backtest.ps1 -Venue 高知 -From 2026-04-01 -To 2026-06-14 -NumAxis 1 -NumPartner 5
#>
[CmdletBinding()]
param(
    [string]$Venue = '高知',
    [string]$From = '2026-04-01',
    [string]$To = '2026-06-14',
    [int]$RecentN = 5, [int]$RecentDays = 183, [int]$MinCompare = 3,
    [int]$NumAxis = 1, [int]$NumPartner = 5,
    [switch]$Trifecta,   # 指定で3連単マルチ(軸1頭マルチ・相手N頭=3N(N-1)点)。既定は3連複。
    [double]$WeightPenalty = 0.0,  # 前々走から2走連続で馬体重減(今走・前走とも増減<0)の馬を軸有力度から減点する量(0=無効)
    [double]$Wh = 0.5, [double]$Wk = 0.2, [double]$Wj = 0.2, [double]$Wd = 0.1
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
    Write-Host "履歴ロード中..."
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
    $rd.Close(); Write-Host ("  履歴 {0:N0}レース / {1:N0}頭" -f $races.Count,$horseRuns.Count)

    function Rate($h){ if($null -eq $h -or $h.n -eq 0){return $null}; return [double]$h.w/$h.n }
    $styleWin=@{}; $drawWin=@{}
    $sb = Invoke-Rows @"
WITH k AS (SELECT kk.開催場所 v, r.距離 dist, kk.着順 c, COALESCE(NULLIF(kk.一コーナー,0),NULLIF(kk.二コーナー,0),NULLIF(kk.三コーナー,0),NULLIF(kk.四コーナー,0)) early, COUNT(*) OVER(PARTITION BY kk.開催場所,kk.開催日,kk.レース番号) tou
  FROM 競走結果 kk JOIN レース情報 r ON r.開催場所=kk.開催場所 AND r.開催日=kk.開催日 AND r.レース番号=kk.レース番号 AND r.馬番=kk.馬番
  WHERE kk.着順>0 AND kk.開催日>='2024-01-01' AND kk.開催日<@f AND kk.開催場所 NOT LIKE '%ば')
SELECT v, dist, 脚質=CASE WHEN early IS NULL OR early=0 THEN N'?' WHEN early=1 THEN N'逃げ' WHEN early<=tou*0.33 THEN N'先行' WHEN early<=tou*0.66 THEN N'差し' ELSE N'追込' END, COUNT(*) n, SUM(CASE WHEN c=1 THEN 1 ELSE 0 END) w
FROM k GROUP BY v, dist, CASE WHEN early IS NULL OR early=0 THEN N'?' WHEN early=1 THEN N'逃げ' WHEN early<=tou*0.33 THEN N'先行' WHEN early<=tou*0.66 THEN N'差し' ELSE N'追込' END
"@ @{'@f'=$From}
    foreach($x in $sb){ if($null -eq $x.dist){continue}; $ck="$($x.v)|$([int]$x.dist)"; if(-not $styleWin.ContainsKey($ck)){$styleWin[$ck]=@{}}; $styleWin[$ck][[string]$x.脚質]=@{n=[int]$x.n;w=[int]$x.w} }
    $db = Invoke-Rows @"
SELECT kk.開催場所 v, r.距離 dist, CASE WHEN kk.馬番<=4 THEN N'内' WHEN kk.馬番<=8 THEN N'中' ELSE N'外' END grp, COUNT(*) n, SUM(CASE WHEN kk.着順=1 THEN 1 ELSE 0 END) w
FROM 競走結果 kk JOIN レース情報 r ON r.開催場所=kk.開催場所 AND r.開催日=kk.開催日 AND r.レース番号=kk.レース番号 AND r.馬番=kk.馬番
WHERE kk.着順>0 AND kk.開催日>='2024-01-01' AND kk.開催日<@f AND kk.開催場所 NOT LIKE '%ば'
GROUP BY kk.開催場所, r.距離, CASE WHEN kk.馬番<=4 THEN N'内' WHEN kk.馬番<=8 THEN N'中' ELSE N'外' END
"@ @{'@f'=$From}
    foreach($x in $db){ if($null -eq $x.dist){continue}; $ck="$($x.v)|$([int]$x.dist)"; if(-not $drawWin.ContainsKey($ck)){$drawWin[$ck]=@{}}; $drawWin[$ck][[string]$x.grp]=@{n=[int]$x.n;w=[int]$x.w} }
    $jr = Invoke-Rows @"
SELECT r.開催場所 v, r.騎手 jk, COUNT(*) n, SUM(CASE WHEN kk.着順=1 THEN 1 ELSE 0 END) w
FROM レース情報 r JOIN 競走結果 kk ON kk.開催場所=r.開催場所 AND kk.開催日=r.開催日 AND kk.レース番号=r.レース番号 AND kk.馬番=r.馬番
WHERE kk.着順>0 AND r.開催日>='2024-01-01' AND r.開催日<@f AND r.開催場所 NOT LIKE '%ば' GROUP BY r.開催場所, r.騎手
"@ @{'@f'=$From}
    $jStat=@{}; foreach($x in $jr){ if([int]$x.n -ge 30){ $jStat["$($x.v)|$($x.jk)"]=[double]$x.w/[int]$x.n } }

    # 払戻(3連複 or 3連単)
    $betType= if($Trifecta){'三連単'}else{'三連複'}
    $trio=@{}
    $tp = Invoke-Rows "SELECT レース番号 rno, 開催日 d, 組番 k, 金額 a FROM 払戻金 WHERE 開催場所=@v AND 馬券=@bt AND 開催日>=@f AND 開催日<=@to" @{'@v'=$Venue;'@bt'=$betType;'@f'=$From;'@to'=$To}
    foreach($x in $tp){ $key='{0:yyyy-MM-dd}|{1}' -f ([datetime]$x.d),[int]$x.rno; if(-not $trio.ContainsKey($key)){$trio[$key]=@{}}
        if($Trifecta){ $trio[$key][[string]$x.k.Trim()]=[double]$x.a }   # 三連単は着順そのまま
        else { $p=@(($x.k -split '[-=]')|ForEach-Object{[int]$_}|Sort-Object); $trio[$key]["$($p[0])-$($p[1])-$($p[2])"]=[double]$x.a } }

    # 馬体重増減マップ(レース情報): "場|日|R|馬名" -> 増減
    $zougen=@{}
    $zg = Invoke-Rows "SELECT 開催場所 v, 開催日 d, レース番号 rno, 馬名 nm, 馬体重増減 zd FROM レース情報 WHERE 開催日>=@h AND 開催日<=@to AND 開催場所 NOT LIKE '%ば'" @{'@h'=$histFrom;'@to'=$To}
    foreach($x in $zg){ if($null -eq $x.zd){continue}; $zougen['{0}|{1:yyyy-MM-dd}|{2}|{3}' -f $x.v,([datetime]$x.d),[int]$x.rno,[string]$x.nm]=[int]$x.zd }

    # 対象レース(出馬表)
    $ent = Invoke-Rows "SELECT 開催日 d, レース番号 rno, 馬番 uma, 馬名 nm, 騎手 jk, 距離 dist, 馬体重増減 zd FROM レース情報 WHERE 開催場所=@v AND 開催日>=@f AND 開催日<=@to ORDER BY 開催日, レース番号, 馬番" @{'@v'=$Venue;'@f'=$From;'@to'=$To}
    if($ent.Count -eq 0){ Write-Host "出馬表なし"; return }
    $wlFlag=0
    $byRace = $ent | Group-Object d, rno

    $nRace=0; $nBet=0; $hitRace=0; $ret=0.0; $skipped=0
    foreach($grp in $byRace){
        $rws=$grp.Group; $d=[datetime]$rws[0].d; $rno=[int]$rws[0].rno; $dist=[int]$rws[0].dist; $ck="$Venue|$dist"; $td=$d
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
        $kyaku=@{};$draw=@{};$jock=@{}
        foreach($row in $rws){ $a=[string]$row.nm; $cnt=@{}
            if($horseRuns.ContainsKey($a)){ $runs=@($horseRuns[$a]|Where-Object{$_.date -lt $td -and $_.date -ge $td.AddDays(-$RecentDays)}|Sort-Object date -Descending|Select-Object -First $RecentN)
                foreach($run in $runs){ $rr=$races[$run.key]; $me=($rr.rows|Where-Object{$_.nm -eq $a}|Select-Object -First 1); if($null -eq $me){continue}; $s=StyleOf $me.early $rr.rows.Count; if($s -ne '?'){$cnt[$s]=$cnt[$s]+1} } }
            $st= if($cnt.Count -gt 0){($cnt.GetEnumerator()|Sort-Object Value -Descending|Select-Object -First 1).Key}else{'?'}
            $kr= if($st -ne '?' -and $styleWin.ContainsKey($ck)){Rate $styleWin[$ck][$st]}else{$null}; $kyaku[$a]= if($null -ne $kr){$kr}else{0.0}
            $g= if([int]$row.uma -le 4){'内'}elseif([int]$row.uma -le 8){'中'}else{'外'}; $dr= if($drawWin.ContainsKey($ck)){Rate $drawWin[$ck][$g]}else{$null}; $draw[$a]= if($null -ne $dr){$dr}else{0.0}
            $jk=[string]$row.jk; $jw= if($jStat.ContainsKey("$Venue|$jk")){$jStat["$Venue|$jk"]}else{$null}; $jock[$a]= if($null -ne $jw){$jw}else{0.0} }
        $zh=Zmap $h2h;$zk=Zmap $kyaku;$zj=Zmap $jock;$zd=Zmap $draw
        $scored=foreach($row in $rws){ $a=[string]$row.nm; $ok=($h2h.ContainsKey($a) -and $cmp[$a] -ge $MinCompare)
            # 前々走から2走連続で馬体重減: 今走増減<0 かつ 前走増減<0(両方とも確認できる場合のみ)
            $curZ= if($null -ne $row.zd){[int]$row.zd}else{0}
            $prevZ=0
            if($horseRuns.ContainsKey($a)){ $pr=@($horseRuns[$a]|Where-Object{$_.date -lt $td}|Sort-Object date -Descending|Select-Object -First 1)
                if($pr.Count -gt 0 -and $zougen.ContainsKey("$($pr[0].key)|$a")){ $prevZ=$zougen["$($pr[0].key)|$a"] } }
            $wl= ($curZ -lt 0 -and $prevZ -lt 0)
            if($wl){ $script:wlFlag++ }
            $axv=($Wh*[double]($zh[$a])+$Wk*[double]($zk[$a])+$Wj*[double]($zj[$a])+$Wd*[double]($zd[$a]))
            if($wl){ $axv -= $WeightPenalty }
            [PSCustomObject]@{ uma=[int]$row.uma; ax=$axv; ok=$ok; wl=$wl } }
        $cand=@($scored|Where-Object{$_.ok}|Sort-Object ax -Descending)
        $need=$NumAxis+([Math]::Max(2-$NumAxis+1,1))   # 3連複に必要な最小頭数
        if($cand.Count -lt ($NumAxis+ (3-$NumAxis)) ){ $skipped++; continue }
        $axis=@($cand[0..($NumAxis-1)]|ForEach-Object{$_.uma})
        $partners=@($cand[$NumAxis..([Math]::Min($cand.Count-1,$NumAxis+$NumPartner-1))]|ForEach-Object{$_.uma})
        $key='{0:yyyy-MM-dd}|{1}' -f $td,$rno
        $won=$false; $pay=0.0; $bets=0

        if($Trifecta){
            # 3連単 軸1頭マルチ・相手N頭: 点数=3*P*(P-1)。的中条件=軸が3着内かつ他2着が相手内(順序不問)
            $P=$partners.Count; if($P -lt 2){ $skipped++; continue }
            $bets=3*$P*($P-1)
            $pset=@{}; $partners|ForEach-Object{$pset[$_]=$true}
            if($trio.ContainsKey($key)){
                $okey=@($trio[$key].Keys)[0]   # 実際の着順 a-b-c
                $o=@(($okey -split '[-=]')|ForEach-Object{[int]$_})
                if($o.Count -eq 3 -and ($o -contains $axis[0])){
                    $others=@($o|Where-Object{$_ -ne $axis[0]})
                    if($others.Count -eq 2 -and $pset.ContainsKey($others[0]) -and $pset.ContainsKey($others[1])){ $won=$true; $pay=$trio[$key][$okey] }
                }
            }
        } else {
            $combos=@()
            if($NumAxis -eq 1){ for($i=0;$i -lt $partners.Count;$i++){ for($j=$i+1;$j -lt $partners.Count;$j++){ $combos+=,@($axis[0],$partners[$i],$partners[$j]) } } }
            else { foreach($p in $partners){ $combos+=,@($axis[0],$axis[1],$p) } }
            if($combos.Count -eq 0){ $skipped++; continue }
            $bets=$combos.Count
            foreach($cmb in $combos){ $s=@($cmb|Sort-Object); $tk="$($s[0])-$($s[1])-$($s[2])"; if($trio.ContainsKey($key) -and $trio[$key].ContainsKey($tk)){ $won=$true; $pay+=$trio[$key][$tk] } }
        }
        $nRace++; $nBet+=$bets; if($won){$hitRace++}; $ret+=($pay/100.0)
    }

    $modeName= if($Trifecta){'3連単 軸1頭マルチ'}else{"3連複 軸${NumAxis}頭流し"}
    $ptsPerR= if($Trifecta){3*$NumPartner*($NumPartner-1)}elseif($NumAxis -eq 1){[int]($NumPartner*($NumPartner-1)/2)}else{$NumPartner}
    Write-Host ("`n=== {0}・相手{1}頭({2}点/レース) {3} {4}〜{5} ===" -f $modeName,$NumPartner,$ptsPerR,$Venue,$From,$To)
    Write-Host ("対象レース: {0}  (実績不足で除外: {1})  体重連続減フラグ: {2}頭 / 減点{3}" -f $nRace,$skipped,$wlFlag,$WeightPenalty)
    if($nRace -gt 0){
        Write-Host ("的中: {0}レース  的中率(レース): {1:P1}" -f $hitRace, ($hitRace/$nRace))
        Write-Host ("総購入: {0}点 ({1:N0}円)  総払戻: {2:N0}円  回収率: {3:P1}" -f $nBet, ($nBet*100), [int]($ret*100), ($ret*100/($nBet*100)))
    }
}
finally { $conn.Close() }
