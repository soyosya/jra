<#
.SYNOPSIS
  軸有力度の「危険ローテ減点」(前走6着以下×短間隔続戦)の妥当性をバックテストします。

.DESCRIPTION
  重みは既定 h2h0.5/脚質0.2/騎手0.2/枠0.1 で固定し、危険ローテ減点幅(RotePenalty)を
  0,0.1,0.15,0.2,0.3,0.5 とスイープ。各設定で「軸=スコア最大の馬」の 勝率/複勝率/単勝回収率 を比較。
  減点を入れると危険ローテ該当の本命が軸から外れ、別馬が軸になる。これで回収が改善するか検証する。

  危険ローテ = 前走着順>=6 かつ 前走からの間隔<=27日(中3週以内の続戦)。休明け(間隔大/履歴外)は非該当。
  着差(h2h)・コース傾向・騎手勝率は axis-backtest と同方式。ばんえい除外。馬同定は馬名。

.PARAMETER Venues / TestFrom / TestTo / RecentN / RecentDays / MinCompare
#>
[CmdletBinding()]
param(
    [string[]]$Venues = @('高知','園田','大井'),
    [string]$TestFrom = '2025-09-01',
    [string]$TestTo = '2026-06-14',
    [int]$RecentN = 5,
    [int]$RecentDays = 183,
    [int]$MinCompare = 4,
    [int]$Parallel = [Environment]::ProcessorCount   # 1で逐次。既定は全コアでrunspace並列(5.1エンジン=結果不変)
)
$ErrorActionPreference = 'Stop'
$appsettings = Join-Path $PSScriptRoot '..\共通\appsettings.json'
$connStr = (Get-Content $appsettings -Raw -Encoding UTF8 | ConvertFrom-Json).ConnectionStrings.DefaultConnection
$conn = New-Object System.Data.SqlClient.SqlConnection($connStr); $conn.Open()

function Median($a){ $s=@($a|Sort-Object); $n=$s.Count; if($n -eq 0){return $null}; if($n%2 -eq 1){return [double]$s[[int](($n-1)/2)]}; return ([double]$s[$n/2-1]+[double]$s[$n/2])/2.0 }
function StyleOf([int]$e,[int]$n){ if($e -le 0 -or $n -le 0){return '?'}; if($e -eq 1){return '逃げ'}; if($e -le $n*0.33){return '先行'}; if($e -le $n*0.66){return '差し'}; return '追込' }
function Zmap($m){ $v=@($m.Values); $z=@{}; if($v.Count -eq 0){return $z}; $mean=($v|Measure-Object -Average).Average; $sd= if($v.Count -gt 1){[Math]::Sqrt((($v|ForEach-Object{($_-$mean)*($_-$mean)})|Measure-Object -Sum).Sum/($v.Count-1))}else{0}; foreach($k in $m.Keys){ $z[$k]= if($sd -gt 0){($m[$k]-$mean)/$sd}else{0.0} }; return $z }
function Rate($h){ if($null -eq $h -or $h.n -eq 0){return $null}; return [double]$h.w/$h.n }

# 1レース分のZベクトル+前走情報を計算して返す(逐次/並列で共用。読み取り専用の共有データを引数で受ける)
function ProcessRace($rc,$races,$horseRuns,$styleWin,$drawWin,$jWin,$RecentDays,$RecentN,$MinCompare){
    $rows=$rc.rows; if($rows.Count -lt 4){return $null}
    $field=@($rows|ForEach-Object{$_.nm}); $fieldSet=@{}; $field|ForEach-Object{$fieldSet[$_]=$true}
    $td=$rc.d; $ck="$($rc.v)|$($rc.dist)"
    $mavg=@{}
    foreach($a in $field){ $mavg[$a]=@{}; $tmp=@{}
        if($horseRuns.ContainsKey($a)){
            $runs=@($horseRuns[$a]|Where-Object{$_.date -lt $td -and $_.date -ge $td.AddDays(-$RecentDays)}|Sort-Object date,key -Descending|Select-Object -First $RecentN)
            foreach($run in $runs){ $rr=$races[$run.key]; $wt=$rr.win; if($wt -le 0){continue}
                $meA=$rr.byName[$a]; if($null -eq $meA){continue}; $ta=$meA.t
                foreach($h in $rr.rows){ if($h.nm -eq $a){continue}; $rel=($h.t-$ta)/$wt*100.0; if($rel -gt 8){$rel=8}elseif($rel -lt -8){$rel=-8}; if(-not $tmp.ContainsKey($h.nm)){$tmp[$h.nm]=New-Object System.Collections.Generic.List[double]}; $tmp[$h.nm].Add($rel) } }
        }
        foreach($x in $tmp.Keys){ $mavg[$a][$x]=Median $tmp[$x] }
    }
    function PairM2($a,$b){ $v=@(); if($mavg[$a].ContainsKey($b)){$v+=$mavg[$a][$b]}; if($mavg[$b].ContainsKey($a)){$v+=(-1.0*$mavg[$b][$a])}; if($v.Count -gt 0){return (($v|Measure-Object -Average).Average)}
        $common=@($mavg[$a].Keys|Where-Object{$mavg[$b].ContainsKey($_) -and $_ -ne $a -and $_ -ne $b}); if($common.Count -eq 0){return $null}
        $fc=@($common|Where-Object{$fieldSet.ContainsKey($_)}); $use= if($fc.Count -gt 0){$fc}else{$common}
        $est=foreach($c in $use){ $mavg[$a][$c]-$mavg[$b][$c] }; return (Median $est) }
    $h2h=@{}; $cmpCnt=@{}
    foreach($a in $field){ $ms=@(); foreach($b in $field){ if($a -ne $b){ $m=PairM2 $a $b; if($null -ne $m){$ms+=$m} } }; $cmpCnt[$a]=$ms.Count; if($ms.Count -ge 1){$h2h[$a]=($ms|Measure-Object -Average).Average} }
    $kyaku=@{}; $draw=@{}; $jock=@{}; $prevC=@{}; $prevKan=@{}
    foreach($row in $rows){ $a=$row.nm
        $cnt=@{}
        if($horseRuns.ContainsKey($a)){
            $runs=@($horseRuns[$a]|Where-Object{$_.date -lt $td -and $_.date -ge $td.AddDays(-$RecentDays)}|Sort-Object date,key -Descending|Select-Object -First $RecentN)
            foreach($run in $runs){ $rr=$races[$run.key]; $me=$rr.byName[$a]; if($null -eq $me){continue}; $s=StyleOf $me.early $rr.rows.Count; if($s -ne '?'){$cnt[$s]=$cnt[$s]+1} }
        }
        $st= if($cnt.Count -gt 0){($cnt.GetEnumerator()|Sort-Object Value -Descending|Select-Object -First 1).Key}else{'?'}
        $kr= if($st -ne '?' -and $styleWin.ContainsKey($ck)){ Rate $styleWin[$ck][$st] } else { $null }
        $kyaku[$a]= if($null -ne $kr){$kr}else{0.0}
        $g= if($row.uma -le 4){'内'}elseif($row.uma -le 8){'中'}else{'外'}
        $dr= if($drawWin.ContainsKey($ck)){ Rate $drawWin[$ck][$g] } else { $null }
        $draw[$a]= if($null -ne $dr){$dr}else{0.0}
        $jr= if($row.jk -ne '' -and $jWin.ContainsKey("$($rc.v)|$($row.jk)")){ $hh=$jWin["$($rc.v)|$($row.jk)"]; if($hh.n -ge 30){[double]$hh.w/$hh.n}else{$null} } else { $null }
        $jock[$a]= if($null -ne $jr){$jr}else{0.0}
        $pc=$null; $kan=$null
        if($horseRuns.ContainsKey($a)){
            $pruns=@($horseRuns[$a]|Where-Object{$_.date -lt $td}|Sort-Object date,key -Descending|Select-Object -First 1)
            if($pruns.Count -ge 1){ $pr=$pruns[0]; $prr=$races[$pr.key]; $me=$prr.byName[$a]; if($me){$pc=$me.c}; $kan=($td - $pr.date).Days }
        }
        $prevC[$a]=$pc; $prevKan[$a]=$kan
    }
    $zh=Zmap $h2h; $zk=Zmap $kyaku; $zj=Zmap $jock; $zd=Zmap $draw
    $ents=foreach($row in $rows){ $a=$row.nm
        $rote= ($null -ne $prevC[$a] -and $prevC[$a] -ge 6 -and $null -ne $prevKan[$a] -and $prevKan[$a] -le 27)
        @{ nm=$a; uma=$row.uma; c=$row.c; zh=[double]($zh[$a]); zk=[double]($zk[$a]); zj=[double]($zj[$a]); zd=[double]($zd[$a]); rote=$rote; ok=($h2h.ContainsKey($a) -and $cmpCnt[$a] -ge $MinCompare) }
    }
    $fl=0;$te=0; foreach($e in $ents){ if($e.ok){ $te++; if($e.rote){$fl++} } }
    return @{ key=('{0}|{1:yyyy-MM-dd}|{2}' -f $rc.v,$rc.d,$rc.rno); ents=@($ents); flagged=$fl; totEnt=$te }
}

try {
    $histFrom = ([datetime]$TestFrom).AddDays(-$RecentDays).ToString('yyyy-MM-dd')
    Write-Host "ロード中..."
    $cmd = $conn.CreateCommand(); $cmd.CommandTimeout = 600
    $cmd.CommandText = @"
SELECT kk.開催場所 v, kk.開催日 d, kk.レース番号 rno, kk.馬番 uma, kk.馬名 nm, kk.着順 c, kk.走破時計 t,
  COALESCE(NULLIF(kk.一コーナー,0),NULLIF(kk.二コーナー,0),NULLIF(kk.三コーナー,0),NULLIF(kk.四コーナー,0)) early,
  r.距離 dist, r.騎手 jk
FROM 競走結果 kk
LEFT JOIN レース情報 r ON r.開催場所=kk.開催場所 AND r.開催日=kk.開催日 AND r.レース番号=kk.レース番号 AND r.馬番=kk.馬番
WHERE kk.着順>0 AND kk.走破時計>0 AND kk.開催日>=@h AND kk.開催日<=@t AND kk.開催場所 NOT LIKE '%ば'
ORDER BY kk.開催日, kk.レース番号
"@
    [void]$cmd.Parameters.AddWithValue('@h',$histFrom); [void]$cmd.Parameters.AddWithValue('@t',$TestTo)
    $r = $cmd.ExecuteReader()
    $races=@{}; $horseRuns=@{}
    while($r.Read()){
        $v=$r.GetString(0); $d=$r.GetDateTime(1); $rno=$r.GetInt32(2); $uma=$r.GetInt32(3); $nm=$r.GetString(4); $c=$r.GetInt32(5); $t=[double]$r.GetDecimal(6)
        $early= if($r.IsDBNull(7)){0}else{[int]$r.GetValue(7)}
        $dist= if($r.IsDBNull(8)){0}else{[int]$r.GetValue(8)}
        $jk= if($r.IsDBNull(9)){''}else{$r.GetString(9)}
        $key='{0}|{1:yyyy-MM-dd}|{2}' -f $v,$d,$rno
        if(-not $races.ContainsKey($key)){ $races[$key]=@{ rows=(New-Object System.Collections.Generic.List[object]); byName=@{}; win=[double]::MaxValue; v=$v; d=$d; rno=$rno; dist=$dist } }
        $row=@{ uma=$uma; nm=$nm; c=$c; t=$t; early=$early; jk=$jk }
        $races[$key].rows.Add($row); $races[$key].byName[$nm]=$row
        if($t -lt $races[$key].win){ $races[$key].win=$t }
        if($dist -gt 0 -and $races[$key].dist -eq 0){ $races[$key].dist=$dist }
        if(-not $horseRuns.ContainsKey($nm)){ $horseRuns[$nm]=(New-Object System.Collections.Generic.List[object]) }
        $horseRuns[$nm].Add(@{ date=$d; key=$key })
    }
    $r.Close()
    Write-Host ("  {0:N0}レース / {1:N0}頭" -f $races.Count, $horseRuns.Count)

    # コース傾向(場×距離): 脚質別/枠別 勝率
    $styleWin=@{}; $drawWin=@{}
    foreach($key in $races.Keys){ $rc=$races[$key]; if($rc.dist -le 0){continue}; $n=$rc.rows.Count; $ck="$($rc.v)|$($rc.dist)"
        if(-not $styleWin.ContainsKey($ck)){ $styleWin[$ck]=@{}; $drawWin[$ck]=@{} }
        foreach($row in $rc.rows){
            $st=StyleOf $row.early $n
            if($st -ne '?'){ if(-not $styleWin[$ck].ContainsKey($st)){$styleWin[$ck][$st]=@{n=0;w=0}}; $styleWin[$ck][$st].n++; if($row.c -eq 1){$styleWin[$ck][$st].w++} }
            $g= if($row.uma -le 4){'内'}elseif($row.uma -le 8){'中'}else{'外'}
            if(-not $drawWin[$ck].ContainsKey($g)){$drawWin[$ck][$g]=@{n=0;w=0}}; $drawWin[$ck][$g].n++; if($row.c -eq 1){$drawWin[$ck][$g].w++}
        }
    }
    # 騎手勝率(場)
    $jWin=@{}
    foreach($key in $races.Keys){ $rc=$races[$key]
        foreach($row in $rc.rows){ if($row.jk -eq ''){continue}; $jk="$($rc.v)|$($row.jk)"; if(-not $jWin.ContainsKey($jk)){$jWin[$jk]=@{n=0;w=0}}; $jWin[$jk].n++; if($row.c -eq 1){$jWin[$jk].w++} }
    }

    $penalties = @(0.0, 0.1, 0.15, 0.2, 0.3, 0.5)
    $allReport=@()

    foreach($Venue in $Venues){
        # 単勝払戻
        $cmd2=$conn.CreateCommand(); $cmd2.CommandTimeout=300
        $cmd2.CommandText="SELECT 開催日,レース番号,組番,金額 FROM 払戻金 WHERE 開催場所=@v AND 馬券=N'単勝' AND 開催日>=@f AND 開催日<=@t"
        [void]$cmd2.Parameters.AddWithValue('@v',$Venue);[void]$cmd2.Parameters.AddWithValue('@f',$TestFrom);[void]$cmd2.Parameters.AddWithValue('@t',$TestTo)
        $r2=$cmd2.ExecuteReader(); $tansho=@{}
        while($r2.Read()){ $key='{0}|{1:yyyy-MM-dd}|{2}' -f $Venue,$r2.GetDateTime(0),$r2.GetInt32(1); $uma=($r2.GetValue(2)).ToString().Trim(); if(-not $tansho.ContainsKey($key)){$tansho[$key]=@{}}; $tansho[$key][$uma]=[double]$r2.GetValue(3) }
        $r2.Close()

        # ===== Pass1: 各対象レースのZベクトル+前走情報を保存 =====
        $targets = $races.Values | Where-Object { $_.v -eq $Venue -and $_.d -ge [datetime]$TestFrom -and $_.d -le [datetime]$TestTo } | Sort-Object d, rno
        $store=New-Object System.Collections.Generic.List[object]; $flagged=0; $totEnt=0
        if($Parallel -le 1){
            foreach($rc in $targets){ $res=ProcessRace $rc $races $horseRuns $styleWin $drawWin $jWin $RecentDays $RecentN $MinCompare
                if($null -eq $res){continue}; $store.Add(@{ key=$res.key; ents=$res.ents }); $flagged+=$res.flagged; $totEnt+=$res.totEnt }
        } else {
            # 5.1 runspaceプールでレース計算を並列。共有データ($races等)は参照渡し=コピー無し、
            # Pass1中は書込なしの多読のみ→Hashtable/Listの並行読取は安全。結果は逐次と完全一致。
            $iss=[System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            foreach($fn in 'Median','StyleOf','Zmap','Rate','ProcessRace'){
                $iss.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry $fn,((Get-Command $fn).Definition))) }
            $pool=[runspacefactory]::CreateRunspacePool(1,$Parallel,$iss,$Host); $pool.Open()
            $work={ param($chunk,$races,$horseRuns,$styleWin,$drawWin,$jWin,$RecentDays,$RecentN,$MinCompare)
                foreach($rc in $chunk){ $r=ProcessRace $rc $races $horseRuns $styleWin $drawWin $jWin $RecentDays $RecentN $MinCompare; if($null -ne $r){ $r } } }
            $arr=@($targets); $cs=[Math]::Max(1,[Math]::Ceiling($arr.Count/$Parallel)); $jobs=@()
            for($i=0;$i -lt $arr.Count;$i+=$cs){
                $chunk=$arr[$i..([Math]::Min($i+$cs-1,$arr.Count-1))]
                $ps=[powershell]::Create(); $ps.RunspacePool=$pool
                [void]$ps.AddScript($work.ToString()).AddArgument($chunk).AddArgument($races).AddArgument($horseRuns).AddArgument($styleWin).AddArgument($drawWin).AddArgument($jWin).AddArgument($RecentDays).AddArgument($RecentN).AddArgument($MinCompare)
                $jobs += @{ps=$ps; h=$ps.BeginInvoke()} }
            foreach($j in $jobs){ $out=$j.ps.EndInvoke($j.h); foreach($r in $out){ $store.Add(@{ key=$r.key; ents=$r.ents }); $flagged+=$r.flagged; $totEnt+=$r.totEnt }; $j.ps.Dispose() }
            $pool.Close(); $pool.Dispose()
        }

        # ===== Pass2: 減点幅スイープ(重みは0.5/0.2/0.2/0.1固定) =====
        foreach($p in $penalties){
            $n=0;$win=0;$top3=0;$bets=0;$ret=0.0; $changed=0
            foreach($race in $store){
                $cand=@($race.ents|Where-Object{$_.ok}); if($cand.Count -eq 0){continue}
                $best=$null; $bs=[double]::NegativeInfinity; $best0=$null; $bs0=[double]::NegativeInfinity
                foreach($e in $cand){
                    $base=0.5*$e.zh+0.2*$e.zk+0.2*$e.zj+0.1*$e.zd
                    $sc= $base - $(if($e.rote){$p}else{0.0})
                    if($sc -gt $bs){$bs=$sc;$best=$e}
                    if($base -gt $bs0){$bs0=$base;$best0=$e}
                }
                $n++; if($best.c -eq 1){$win++}; if($best.c -le 3){$top3++}
                if($best.nm -ne $best0.nm){$changed++}
                if($tansho.ContainsKey($race.key)){ $bets++; if($best.c -eq 1){ $pp=$tansho[$race.key]["$($best.uma)"]; if($pp){$ret+=$pp/100.0} } }
            }
            $allReport += [PSCustomObject]@{ 場=$Venue; 減点=$p; レース=$n; 軸変更=$changed; 勝率=[Math]::Round(100.0*$win/$n,1); 複勝率=[Math]::Round(100.0*$top3/$n,1); 単回収=if($bets){[Math]::Round(100.0*$ret/$bets,1)}else{$null} }
        }
        Write-Host ("{0}: 対象{1:N0}レース / 危険ローテ該当 {2:N0}/{3:N0}頭({4:P1})" -f $Venue,$store.Count,$flagged,$totEnt,($(if($totEnt){$flagged/$totEnt}else{0})))
    }

    Write-Host ("`n=== 危険ローテ減点スイープ ({0}〜{1}, 重み0.5/0.2/0.2/0.1固定) ===" -f $TestFrom,$TestTo)
    Write-Host "(減点0=減点なし。軸変更=減点で本命が入れ替わったレース数)"
    foreach($Venue in $Venues){
        Write-Host ("`n--- {0} ---" -f $Venue)
        $allReport | Where-Object{$_.場 -eq $Venue} | Format-Table 減点,レース,軸変更,勝率,複勝率,単回収 -AutoSize | Out-String -Width 200 | Write-Host
    }
}
finally { $conn.Close() }
