<#
.SYNOPSIS
  指定レースの軸馬有力度を、h2h地力 + 脚質適性 + 騎手 + 枠適性 で総合評価します。

.DESCRIPTION
  核は race-h2h と同じ「共通対戦相手の着差比較(勝ち時計比%で距離正規化)」=地力。
  そこへ状況要因を重ねて軸の確度を上げます。

    脚質適性 : 馬の近走脚質(コーナー通過順/頭数で判定) × その場×距離の脚質別勝率
               (逃げ有利コースで前に行ける馬か)
    騎手     : 当該騎手のその場での勝率 + 継続騎乗/乗り替わり判定
    枠適性   : その場×距離の馬番(内/中/外)別勝率 × 今回の馬番

  各要素をZ標準化し、既定重み h2h0.5/脚質0.2/騎手0.2/枠0.1 で合成 → 軸有力度。
  コース傾向・騎手成績は既定で2024年以降から算出。ばんえいは脚質非対象。

.PARAMETER Date / Venue / Race
  対象レースの 開催日(yyyy-MM-dd)/開催場所/レース番号。
.PARAMETER RecentN / RecentDays
  近走の対象(既定 直近5走/183日)。
.EXAMPLE
  .\race-axis.ps1 -Date 2026-06-12 -Venue 大井 -Race 9
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Date,
    [Parameter(Mandatory)][string]$Venue,
    [Parameter(Mandatory)][int]$Race,
    [int]$RecentN = 5,
    [int]$RecentDays = 183,
    [double]$W_h2h = 0.5, [double]$W_kyaku = 0.2, [double]$W_jockey = 0.2, [double]$W_draw = 0.1,
    # 危険ローテ(前走大敗→短間隔での続戦)の減点幅。0で無効化。
    # 検証(高知/園田 trainer-rotation 2要因): 前走6着以下×中3週以内続戦は好厩舎でも勝率が平均の25〜40%に沈む。
    [double]$RotePenalty = 0.2
)
$ErrorActionPreference = 'Stop'
$appsettings = Join-Path $PSScriptRoot '..\共通\appsettings.json'
$connStr = (Get-Content $appsettings -Raw -Encoding UTF8 | ConvertFrom-Json).ConnectionStrings.DefaultConnection
$conn = New-Object System.Data.SqlClient.SqlConnection($connStr); $conn.Open()
$biasFrom = '2024-01-01'

function Invoke-Rows([string]$sql, [hashtable]$p) {
    $cmd = $conn.CreateCommand(); $cmd.CommandTimeout = 120; $cmd.CommandText = $sql
    foreach ($k in $p.Keys) { [void]$cmd.Parameters.AddWithValue($k, $p[$k]) }
    $r = $cmd.ExecuteReader(); $rows = @()
    while ($r.Read()) { $o = @{}; for ($i = 0; $i -lt $r.FieldCount; $i++) { $o[$r.GetName($i)] = $r.GetValue($i) }; $rows += [PSCustomObject]$o }
    $r.Close(); return ,$rows   # ,で常に配列を返す(1行時のスカラ展開→.Count空 を防止)
}
function Median($arr) { $s=@($arr|Sort-Object); $n=$s.Count; if($n -eq 0){return $null}; if($n%2 -eq 1){return [double]$s[[int](($n-1)/2)]}; return ([double]$s[$n/2-1]+[double]$s[$n/2])/2.0 }
function ZScores($map) {  # hashtable name->value -> name->z
    $vals = @($map.Values); $z = @{}
    if ($vals.Count -eq 0) { return $z }
    $mean = ($vals | Measure-Object -Average).Average
    $sd = if ($vals.Count -gt 1) { [Math]::Sqrt((($vals | ForEach-Object { ($_-$mean)*($_-$mean) }) | Measure-Object -Sum).Sum / ($vals.Count-1)) } else { 0 }
    foreach ($k in $map.Keys) { $z[$k] = if ($sd -gt 0) { ($map[$k]-$mean)/$sd } else { 0.0 } }
    return $z
}
function StyleOf([int]$early,[int]$n) {
    if ($early -le 0 -or $n -le 0) { return '?' }
    if ($early -eq 1) { return '逃げ' }
    if ($early -le $n*0.33) { return '先行' }
    if ($early -le $n*0.66) { return '差し' }
    return '追込'
}

try {
    $dmin = ([datetime]$Date).AddDays(-$RecentDays).ToString('yyyy-MM-dd')
    # 出走馬 + 騎手 + 距離 + 今走馬体重
    $entrants = Invoke-Rows @"
SELECT r.馬番, r.馬名, r.騎手, r.距離, r.馬体重 今走体重, kk.着順 AS 今回着順
FROM レース情報 r
LEFT JOIN 競走結果 kk ON kk.開催場所=@v AND kk.開催日=@d AND kk.レース番号=@rno AND kk.馬番=r.馬番
WHERE r.開催場所=@v AND r.開催日=@d AND r.レース番号=@rno ORDER BY r.馬番
"@ @{'@v'=$Venue;'@d'=$Date;'@rno'=$Race}
    if ($entrants.Count -eq 0) { Write-Host "出走馬が見つかりません(出馬表未取得?)"; return }
    # -10kg妙味が有効な場
    $valueVenues=@{'高知'=$true;'佐賀'=$true;'川崎'=$true}
    # 各馬の前々走馬体重(馬体重がある過去走で2番目に新しい走)
    $bw2=@{}
    foreach($e in $entrants){ $h=[string]$e.馬名
        $br = Invoke-Rows "SELECT TOP 2 馬体重 bw FROM レース情報 WHERE 馬名=@h AND 開催日<@d AND 馬体重>0 ORDER BY 開催日 DESC, レース番号 DESC" @{'@h'=$h;'@d'=$Date}
        if($br.Count -ge 2){ $bw2[$h]=[int]$br[1].bw } }
    $field = @($entrants | ForEach-Object { [string]$_.馬名 })
    $fieldSet = @{}; $field | ForEach-Object { $fieldSet[$_]=$true }
    $dist = [int]($entrants[0].距離)

    # ===== 1) h2h 地力(相対着差) =====
    $recentKeys=@{}; $allKeys=@{}
    foreach($h in $field){
        $rk = Invoke-Rows @"
SELECT TOP ($RecentN) 開催場所,開催日,レース番号 FROM 競走結果
WHERE 馬名=@h AND 開催日<@d AND 開催日>=@dmin AND 走破時計>0 ORDER BY 開催日 DESC,レース番号 DESC
"@ @{'@h'=$h;'@d'=$Date;'@dmin'=$dmin}
        $keys=@(); foreach($x in $rk){ $k='{0}|{1:yyyy-MM-dd}|{2}' -f $x.開催場所,$x.開催日,$x.レース番号; $keys+=$k; if(-not $allKeys.ContainsKey($k)){$allKeys[$k]=@{v=[string]$x.開催場所;d=([datetime]$x.開催日).ToString('yyyy-MM-dd');r=[int]$x.レース番号}} }
        $recentKeys[$h]=$keys
    }
    $raceRows=@{}
    foreach($k in $allKeys.Keys){ $i=$allKeys[$k]
        $rows=Invoke-Rows "SELECT 馬名,走破時計 FROM 競走結果 WHERE 開催場所=@v AND 開催日=@d AND レース番号=@rno AND 走破時計>0 AND 着順>0" @{'@v'=$i.v;'@d'=$i.d;'@rno'=$i.r}
        $m=@{}; foreach($row in $rows){ $m[[string]$row.馬名]=[double]$row.走破時計 }; $raceRows[$k]=$m
    }
    $mavg=@{}
    foreach($a in $field){ $mavg[$a]=@{}; $tmp=@{}
        foreach($k in $recentKeys[$a]){ $rr=$raceRows[$k]; if(-not $rr.ContainsKey($a)){continue}; $ta=$rr[$a]; $wt=($rr.Values|Measure-Object -Minimum).Minimum; if($wt -le 0){continue}
            foreach($x in $rr.Keys){ if($x -eq $a){continue}; $rel=($rr[$x]-$ta)/$wt*100.0; if($rel -gt 8){$rel=8}elseif($rel -lt -8){$rel=-8}; if(-not $tmp.ContainsKey($x)){$tmp[$x]=New-Object System.Collections.Generic.List[double]}; $tmp[$x].Add($rel) } }
        foreach($x in $tmp.Keys){ $mavg[$a][$x]=Median $tmp[$x] }
    }
    function PairM($a,$b){ $v=@(); if($mavg[$a].ContainsKey($b)){$v+=$mavg[$a][$b]}; if($mavg[$b].ContainsKey($a)){$v+=(-1.0*$mavg[$b][$a])}; if($v.Count -gt 0){return (($v|Measure-Object -Average).Average)}
        $common=@($mavg[$a].Keys|Where-Object{$mavg[$b].ContainsKey($_) -and $_ -ne $a -and $_ -ne $b}); if($common.Count -eq 0){return $null}
        $fc=@($common|Where-Object{$fieldSet.ContainsKey($_)}); $use=if($fc.Count -gt 0){$fc}else{$common}
        $est=foreach($c in $use){ $mavg[$a][$c]-$mavg[$b][$c] }; return (Median $est) }
    $h2h=@{}
    foreach($a in $field){ $ms=@(); foreach($b in $field){ if($a -ne $b){ $m=PairM $a $b; if($null -ne $m){$ms+=$m} } }; if($ms.Count -ge 1){ $h2h[$a]=($ms|Measure-Object -Average).Average } }

    # ===== 2) コース傾向(その場×距離, 2024+) =====
    $styleBias=@{}   # 脚質 -> 勝率
    $rows = Invoke-Rows @"
WITH k AS (
  SELECT kk.着順, COALESCE(NULLIF(kk.一コーナー,0),NULLIF(kk.二コーナー,0),NULLIF(kk.三コーナー,0),NULLIF(kk.四コーナー,0)) early,
    COUNT(*) OVER(PARTITION BY kk.開催日,kk.レース番号) 頭数
  FROM 競走結果 kk JOIN レース情報 r ON r.開催場所=kk.開催場所 AND r.開催日=kk.開催日 AND r.レース番号=kk.レース番号 AND r.馬番=kk.馬番
  WHERE kk.開催場所=@v AND r.距離=@dist AND kk.開催日>=@bf AND kk.着順>0
)
SELECT 脚質=CASE WHEN early IS NULL OR early=0 THEN N'?' WHEN early=1 THEN N'逃げ' WHEN early<=頭数*0.33 THEN N'先行' WHEN early<=頭数*0.66 THEN N'差し' ELSE N'追込' END,
  COUNT(*) n, SUM(CASE WHEN 着順=1 THEN 1 ELSE 0 END) w
FROM k GROUP BY CASE WHEN early IS NULL OR early=0 THEN N'?' WHEN early=1 THEN N'逃げ' WHEN early<=頭数*0.33 THEN N'先行' WHEN early<=頭数*0.66 THEN N'差し' ELSE N'追込' END
"@ @{'@v'=$Venue;'@dist'=$dist;'@bf'=$biasFrom}
    foreach($row in $rows){ if([int]$row.n -gt 0){ $styleBias[[string]$row.脚質]=[double]$row.w/[double]$row.n } }

    $drawBias=@{}   # 内/中/外 -> 勝率
    $rows = Invoke-Rows @"
SELECT grp=CASE WHEN kk.馬番<=4 THEN N'内' WHEN kk.馬番<=8 THEN N'中' ELSE N'外' END,
  COUNT(*) n, SUM(CASE WHEN kk.着順=1 THEN 1 ELSE 0 END) w
FROM 競走結果 kk JOIN レース情報 r ON r.開催場所=kk.開催場所 AND r.開催日=kk.開催日 AND r.レース番号=kk.レース番号 AND r.馬番=kk.馬番
WHERE kk.開催場所=@v AND r.距離=@dist AND kk.開催日>=@bf AND kk.着順>0
GROUP BY CASE WHEN kk.馬番<=4 THEN N'内' WHEN kk.馬番<=8 THEN N'中' ELSE N'外' END
"@ @{'@v'=$Venue;'@dist'=$dist;'@bf'=$biasFrom}
    foreach($row in $rows){ if([int]$row.n -gt 0){ $drawBias[[string]$row.grp]=[double]$row.w/[double]$row.n } }

    # ===== 3) 騎手成績(その場, 2024+) + 継続/乗替 =====
    $jstats=@{}
    foreach($e in $entrants){ $jk=[string]$e.騎手
        if(-not $jstats.ContainsKey($jk)){
            $jr = Invoke-Rows @"
SELECT COUNT(*) n, SUM(CASE WHEN kk.着順=1 THEN 1 ELSE 0 END) w
FROM レース情報 r JOIN 競走結果 kk ON kk.開催場所=r.開催場所 AND kk.開催日=r.開催日 AND kk.レース番号=r.レース番号 AND kk.馬番=r.馬番
WHERE r.開催場所=@v AND r.騎手=@j AND r.開催日>=@bf AND kk.着順>0
"@ @{'@v'=$Venue;'@j'=$jk;'@bf'=$biasFrom}
            $n=[int]$jr[0].n; $w=[int]$jr[0].w; $jstats[$jk]= if($n -ge 30){ [double]$w/$n } else { $null }
        }
    }
    # 各馬の前走騎手(継続/乗替判定)と近走脚質、前走着順/間隔(危険ローテ判定)
    $contFlag=@{}; $styleOf=@{}; $prevC=@{}; $prevKan=@{}; $roteFlag=@{}
    foreach($h in $field){
        $last = Invoke-Rows "SELECT TOP 1 騎手 FROM レース情報 WHERE 馬名=@h AND 開催日<@d ORDER BY 開催日 DESC,レース番号 DESC" @{'@h'=$h;'@d'=$Date}
        $today = [string]($entrants | Where-Object {[string]$_.馬名 -eq $h} | Select-Object -First 1).騎手
        $contFlag[$h] = if($last.Count -gt 0){ if([string]$last[0].騎手 -eq $today){'継続'}else{'乗替'} } else {'初'}
        # 前走の着順・開催日(着順は競走結果。レース情報.着順は常に0)
        $pr = Invoke-Rows @"
SELECT TOP 1 k.着順 pc, r.開催日 pd
FROM レース情報 r JOIN 競走結果 k ON k.開催場所=r.開催場所 AND k.開催日=r.開催日 AND k.レース番号=r.レース番号 AND k.馬番=r.馬番
WHERE r.馬名=@h AND r.開催日<@d AND k.着順>0 ORDER BY r.開催日 DESC,r.レース番号 DESC
"@ @{'@h'=$h;'@d'=$Date}
        if($pr.Count -gt 0){
            $pc=[int]$pr[0].pc; $kan=([datetime]$Date - [datetime]$pr[0].pd).Days
            $prevC[$h]=$pc; $prevKan[$h]=$kan
            # 危険ローテ: 前走6着以下 かつ 中3週以内(≤27日)の続戦。休明け方向(間隔大)は除外。
            $roteFlag[$h] = ($pc -ge 6 -and $kan -le 27)
        } else { $prevC[$h]=$null; $prevKan[$h]=$null; $roteFlag[$h]=$false }
        # 近走脚質(最頻)
        $sr = Invoke-Rows @"
SELECT TOP ($RecentN) COALESCE(NULLIF(一コーナー,0),NULLIF(二コーナー,0),NULLIF(三コーナー,0),NULLIF(四コーナー,0)) early,
  (SELECT COUNT(*) FROM 競走結果 k2 WHERE k2.開催場所=k.開催場所 AND k2.開催日=k.開催日 AND k2.レース番号=k.レース番号 AND k2.着順>0) 頭数
FROM 競走結果 k WHERE k.馬名=@h AND k.開催日<@d AND k.開催日>=@dmin ORDER BY k.開催日 DESC,k.レース番号 DESC
"@ @{'@h'=$h;'@d'=$Date;'@dmin'=$dmin}
        $cnt=@{}; foreach($x in $sr){
            $ev = if($x.early -is [DBNull] -or $null -eq $x.early){0}else{[int]$x.early}
            $hv = if($x.頭数 -is [DBNull] -or $null -eq $x.頭数){0}else{[int]$x.頭数}
            $s=StyleOf $ev $hv; if($s -ne '?'){ $cnt[$s]=$cnt[$s]+1 } }
        $styleOf[$h]= if($cnt.Count -gt 0){ ($cnt.GetEnumerator()|Sort-Object Value -Descending|Select-Object -First 1).Key } else {'?'}
    }

    # ===== 合成 =====
    $kyakuScore=@{}; $jockeyScore=@{}; $drawScore=@{}
    foreach($h in $field){
        $st=$styleOf[$h]; $kyakuScore[$h]= if($st -ne '?' -and $styleBias.ContainsKey($st)){ $styleBias[$st] } else { 0.0 }
        $jk=[string]($entrants|Where-Object{[string]$_.馬名 -eq $h}|Select-Object -First 1).騎手
        $jw= $jstats[$jk]; $jockeyScore[$h]= if($null -ne $jw){ $jw } else { 0.0 }
        $grp= $entrants|Where-Object{[string]$_.馬名 -eq $h}|Select-Object -First 1; $u=[int]$grp.馬番
        $g= if($u -le 4){'内'}elseif($u -le 8){'中'}else{'外'}
        $drawScore[$h]= if($drawBias.ContainsKey($g)){ $drawBias[$g] } else { 0.0 }
    }
    $zh=ZScores $h2h; $zk=ZScores $kyakuScore; $zj=ZScores $jockeyScore; $zd=ZScores $drawScore

    $result = foreach($e in $entrants){ $h=[string]$e.馬名
        $hasH2h = $h2h.ContainsKey($h)
        $total = ($W_h2h*([double]($zh[$h])) + $W_kyaku*([double]($zk[$h])) + $W_jockey*([double]($zj[$h])) + $W_draw*([double]($zd[$h])))
        $contBonus = if($contFlag[$h] -eq '継続'){0.05}else{0.0}
        # 危険ローテ減点(前走大敗→短間隔続戦)
        $rotePen = if($roteFlag[$h]){ $RotePenalty }else{ 0.0 }
        # 妙味(-10kg): 今走馬体重 - 前々走馬体重 <= -10、有効な場のみ
        $myo=''
        if($valueVenues.ContainsKey($Venue) -and $null -ne $e.今走体重 -and [int]$e.今走体重 -gt 0 -and $bw2.ContainsKey($h) -and ([int]$e.今走体重 - $bw2[$h]) -le -10){ $myo='★妙味' }
        [PSCustomObject]@{
            馬番=[int]$e.馬番; 馬名=$h
            着=if($e.今回着順 -is [DBNull] -or $null -eq $e.今回着順){''}else{[int]$e.今回着順}
            h2h=if($hasH2h){[Math]::Round($h2h[$h],2)}else{$null}
            脚質=$styleOf[$h]
            脚質適性=[Math]::Round($kyakuScore[$h]*100,1)
            騎手=$contFlag[$h]
            騎手勝率=if($null -ne $jstats[[string]$e.騎手]){[Math]::Round($jstats[[string]$e.騎手]*100,1)}else{''}
            前着=if($null -ne $prevC[$h]){$prevC[$h]}else{''}
            間隔=if($null -ne $prevKan[$h]){$prevKan[$h]}else{''}
            危険=if($roteFlag[$h]){'▼ローテ'}else{''}
            妙味=$myo
            軸有力度=[Math]::Round($total+$contBonus-$rotePen,2)
        }
    }
    Write-Host ("対象: {0} {1} {2}R  距離{3}m  (軸有力度=h2h{4}/脚質{5}/騎手{6}/枠{7} のZ加重, +が有力)" -f $Date,$Venue,$Race,$dist,$W_h2h,$W_kyaku,$W_jockey,$W_draw)
    Write-Host ("コース傾向(脚質別勝率%): " + (($styleBias.GetEnumerator()|Sort-Object Value -Descending|ForEach-Object{ '{0}{1:P0}' -f $_.Name,$_.Value }) -join '  '))
    Write-Host ("枠別勝率%: " + (($drawBias.GetEnumerator()|ForEach-Object{ '{0}{1:P0}' -f $_.Name,$_.Value }) -join '  '))
    if($RotePenalty -gt 0){ Write-Host ("危険ローテ減点: 前走6着以下×中3週以内続戦 に -{0} (休明けは除外)" -f $RotePenalty) }
    $result | Sort-Object 軸有力度 -Descending | Format-Table 馬番,馬名,着,軸有力度,h2h,脚質,脚質適性,騎手,騎手勝率,前着,間隔,危険,妙味 -AutoSize | Out-String -Width 200 | Write-Host
}
finally { $conn.Close() }
