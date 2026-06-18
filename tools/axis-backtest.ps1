<#
.SYNOPSIS
  軸有力度(h2h + 脚質適性 + 騎手 + 枠)の重みをバックテストで較正・検証します。

.DESCRIPTION
  各対象レースで4要素のZスコアを一度だけ算出して保持し、重みの組み合わせを一括スイープ。
  「h2h単独」と各ブレンドの 勝率/複勝率/単勝回収率 を比較します。
  これにより脚質・騎手・枠を足して軸の確度が上がるか、最適な重みは何かを判定します。

  - 着差(h2h)は勝ち時計比%・±8%クリップ・共通相手は中央値(race-h2hと同方式)
  - コース傾向(脚質別/枠別勝率)・騎手勝率は全期間から算出(構造的な事前情報として使用)
  - ばんえい除外。馬の同定は馬名。

.PARAMETER Venue / TestFrom / TestTo / RecentN / RecentDays / MinCompare
#>
[CmdletBinding()]
param(
    [string]$Venue = '大井',
    [string]$TestFrom = '2025-09-01',
    [string]$TestTo = '2026-06-14',
    [int]$RecentN = 5,
    [int]$RecentDays = 183,
    [int]$MinCompare = 4,
    # 先行可能性アップグレード(前残り場): 今走より短い直近レースで前目+前付け型騎手への乗替なら脚質を先行と読み替え、薄h2hでも軸候補にする。
    [switch]$FrontUpgrade,
    [double]$FrontJkThresh = 0.38,
    # 前残り場(FrontUpgrade対象)。明示指定(カンマ区切り)なければ逃げIV≥閾値で自動判定。
    [string]$FrontVenuesArg = '',
    [double]$FrontIVThresh = 2.0,
    # コンピ指数(日刊スポーツ 極ウマ)を6番目の因子として加える。指定時のみコンピをロードしZ化し、重みグリッドに追加する。
    [switch]$WithCompi,
    # コンピ×h2h併用で券種別(複勝/ワイド/馬連/三連複)を実払戻バックテスト。「標準+コンピ0.5」と「コンピ単独」を比較する。
    [switch]$BetBacktest,
    # 軸入替検証: 選別(頭数≤BetFieldMax & コンピ期待的中≥BetEhMin)×3連複相手3頭で
    #   コンピ純/独自純(h2h)/併用blend/入替swap(コンピ1位が独自分析でSwapK位より下なら独自1位へ軸入替) を IS/OOS 比較。
    [switch]$AxisSwapBacktest,
    [string]$Split = '2026-02-28',
    [int]$BetFieldMax = 8,
    [double]$BetEhMin = 0.55,
    [int]$SwapK = 3
)
$ErrorActionPreference = 'Stop'
if($BetBacktest -or $AxisSwapBacktest){ $WithCompi = $true }   # 券種別/軸入替BTはコンピZが必要
$appsettings = Join-Path $PSScriptRoot '..\共通\appsettings.json'
$connStr = (Get-Content $appsettings -Raw -Encoding UTF8 | ConvertFrom-Json).ConnectionStrings.DefaultConnection
$conn = New-Object System.Data.SqlClient.SqlConnection($connStr); $conn.Open()

function Median($a){ $s=@($a|Sort-Object); $n=$s.Count; if($n -eq 0){return $null}; if($n%2 -eq 1){return [double]$s[[int](($n-1)/2)]}; return ([double]$s[$n/2-1]+[double]$s[$n/2])/2.0 }
function StyleOf([int]$e,[int]$n){ if($e -le 0 -or $n -le 0){return '?'}; if($e -eq 1){return '逃げ'}; if($e -le $n*0.33){return '先行'}; if($e -le $n*0.66){return '差し'}; return '追込' }
function Zmap($m){ $v=@($m.Values); $z=@{}; if($v.Count -eq 0){return $z}; $mean=($v|Measure-Object -Average).Average; $sd= if($v.Count -gt 1){[Math]::Sqrt((($v|ForEach-Object{($_-$mean)*($_-$mean)})|Measure-Object -Sum).Sum/($v.Count-1))}else{0}; foreach($k in $m.Keys){ $z[$k]= if($sd -gt 0){($m[$k]-$mean)/$sd}else{0.0} }; return $z }

try {
    $histFrom = ([datetime]$TestFrom).AddDays(-$RecentDays).ToString('yyyy-MM-dd')
    Write-Host "ロード中..."
    $cmd = $conn.CreateCommand(); $cmd.CommandTimeout = 600
    $cmd.CommandText = @"
SELECT kk.開催場所 v, kk.開催日 d, kk.レース番号 rno, kk.馬番 uma, kk.馬名 nm, kk.着順 c, kk.走破時計 t,
  COALESCE(NULLIF(kk.一コーナー,0),NULLIF(kk.二コーナー,0),NULLIF(kk.三コーナー,0),NULLIF(kk.四コーナー,0)) early,
  r.距離 dist, r.騎手 jk, r.一着賞金 prize
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
        $prize= if($r.IsDBNull(10)){0.0}else{[double]$r.GetValue(10)}
        $key='{0}|{1:yyyy-MM-dd}|{2}' -f $v,$d,$rno
        if(-not $races.ContainsKey($key)){ $races[$key]=@{ rows=(New-Object System.Collections.Generic.List[object]); win=[double]::MaxValue; v=$v; d=$d; rno=$rno; dist=$dist; prize=0.0 } }
        $races[$key].rows.Add(@{ uma=$uma; nm=$nm; c=$c; t=$t; early=$early; jk=$jk })
        if($t -lt $races[$key].win){ $races[$key].win=$t }
        if($dist -gt 0 -and $races[$key].dist -eq 0){ $races[$key].dist=$dist }
        if($prize -gt 0 -and $races[$key].prize -eq 0){ $races[$key].prize=$prize }
        if(-not $horseRuns.ContainsKey($nm)){ $horseRuns[$nm]=(New-Object System.Collections.Generic.List[object]) }
        $horseRuns[$nm].Add(@{ date=$d; key=$key })
    }
    $r.Close()
    Write-Host ("  {0:N0}レース / {1:N0}頭" -f $races.Count, $horseRuns.Count)

    # コース傾向(場×距離): 脚質別/枠別 勝率
    $styleWin=@{}; $drawWin=@{}   # "v|dist" -> @{style->rate} / @{grp->rate}
    foreach($key in $races.Keys){ $rc=$races[$key]; if($rc.dist -le 0){continue}; $n=$rc.rows.Count; $ck="$($rc.v)|$($rc.dist)"
        if(-not $styleWin.ContainsKey($ck)){ $styleWin[$ck]=@{}; $drawWin[$ck]=@{} }
        foreach($row in $rc.rows){
            $st=StyleOf $row.early $n
            if($st -ne '?'){ if(-not $styleWin[$ck].ContainsKey($st)){$styleWin[$ck][$st]=@{n=0;w=0}}; $styleWin[$ck][$st].n++; if($row.c -eq 1){$styleWin[$ck][$st].w++} }
            $g= if($row.uma -le 4){'内'}elseif($row.uma -le 8){'中'}else{'外'}
            if(-not $drawWin[$ck].ContainsKey($g)){$drawWin[$ck][$g]=@{n=0;w=0}}; $drawWin[$ck][$g].n++; if($row.c -eq 1){$drawWin[$ck][$g].w++}
        }
    }
    function Rate($h){ if($null -eq $h -or $h.n -eq 0){return $null}; return [double]$h.w/$h.n }

    # 騎手勝率(場)
    $jWin=@{}  # "v|jockey" -> @{n;w}
    foreach($key in $races.Keys){ $rc=$races[$key]
        foreach($row in $rc.rows){ if($row.jk -eq ''){continue}; $jk="$($rc.v)|$($row.jk)"; if(-not $jWin.ContainsKey($jk)){$jWin[$jk]=@{n=0;w=0}}; $jWin[$jk].n++; if($row.c -eq 1){$jWin[$jk].w++} }
    }
    # 騎手前付率(場)= 序盤top33%率。先行可能性アップグレード用。
    # 前残り場: -FrontVenues 明示指定があればそれ、なければ逃げIV(=逃げ勝率/全体平均勝率)≥閾値で自動判定。
    $frontVenues=@{}
    if($FrontVenuesArg -ne ''){ foreach($vn in ($FrontVenuesArg -split ',')){ $vn=$vn.Trim(); if($vn -ne ''){$frontVenues[$vn]=$true} } }
    else {
        $vAgg=@{}
        foreach($ck in $styleWin.Keys){ $vv=$ck.Split('|')[0]; if(-not $vAgg.ContainsKey($vv)){$vAgg[$vv]=@{rw=0;rn=0;w=0;n=0}}
            foreach($st in $styleWin[$ck].Keys){ $h=$styleWin[$ck][$st]; $vAgg[$vv].w+=$h.w; $vAgg[$vv].n+=$h.n; if($st -eq '逃げ'){$vAgg[$vv].rw+=$h.w; $vAgg[$vv].rn+=$h.n} } }
        foreach($vv in $vAgg.Keys){ $a=$vAgg[$vv]; if($a.n -ge 2000 -and $a.rn -ge 100 -and $a.w -gt 0){ $avg=[double]$a.w/$a.n; $liv= if($avg -gt 0){([double]$a.rw/$a.rn)/$avg}else{0}; if($liv -ge $FrontIVThresh){$frontVenues[$vv]=$true} } }
    }
    $jFront=@{}  # "v|jockey" -> @{n;fr}
    foreach($key in $races.Keys){ $rc=$races[$key]; $n=$rc.rows.Count; if($n -le 0){continue}
        foreach($row in $rc.rows){ if($row.jk -eq ''){continue}; $jk="$($rc.v)|$($row.jk)"; if(-not $jFront.ContainsKey($jk)){$jFront[$jk]=@{n=0;fr=0}}; $jFront[$jk].n++; if([int]$row.early -gt 0 -and [int]$row.early -le $n*0.33){$jFront[$jk].fr++} }
    }

    # 単勝払戻
    $cmd2=$conn.CreateCommand(); $cmd2.CommandTimeout=300
    $cmd2.CommandText="SELECT 開催日,レース番号,組番,金額 FROM 払戻金 WHERE 開催場所=@v AND 馬券=N'単勝' AND 開催日>=@f AND 開催日<=@t"
    [void]$cmd2.Parameters.AddWithValue('@v',$Venue);[void]$cmd2.Parameters.AddWithValue('@f',$TestFrom);[void]$cmd2.Parameters.AddWithValue('@t',$TestTo)
    $r2=$cmd2.ExecuteReader(); $tansho=@{}
    while($r2.Read()){ $key='{0}|{1:yyyy-MM-dd}|{2}' -f $Venue,$r2.GetDateTime(0),$r2.GetInt32(1); $uma=($r2.GetValue(2)).ToString().Trim(); if(-not $tansho.ContainsKey($key)){$tansho[$key]=@{}}; $tansho[$key][$uma]=[double]$r2.GetValue(3) }
    $r2.Close()

    # コンピ指数(最新スナップショット)を 場×日×R の 馬番→指数 でロード(馬番で結合=表記揺れの影響なし)。
    $compi=@{}
    if($WithCompi){
        $cmd3=$conn.CreateCommand(); $cmd3.CommandTimeout=300
        $cmd3.CommandText=@"
WITH s AS (
  SELECT 開催日,開催場所,レース番号,馬番,指数,
    ROW_NUMBER() OVER(PARTITION BY 開催日,開催場所,レース番号,馬番 ORDER BY 取得日時 DESC) rn
  FROM コンピ指数 WHERE 開催場所=@v AND 開催日>=@f AND 開催日<=@t
)
SELECT 開催日,レース番号,馬番,指数 FROM s WHERE rn=1 AND 指数 IS NOT NULL
"@
        [void]$cmd3.Parameters.AddWithValue('@v',$Venue);[void]$cmd3.Parameters.AddWithValue('@f',$TestFrom);[void]$cmd3.Parameters.AddWithValue('@t',$TestTo)
        $r3=$cmd3.ExecuteReader()
        while($r3.Read()){ $key='{0}|{1:yyyy-MM-dd}|{2}' -f $Venue,$r3.GetDateTime(0),$r3.GetInt32(1); $uma=[int]$r3.GetInt32(2); if(-not $compi.ContainsKey($key)){$compi[$key]=@{}}; $compi[$key][$uma]=[double]$r3.GetInt32(3) }
        $r3.Close()
        Write-Host ("  コンピ指数ロード: {0:N0}レース" -f $compi.Count)
    }

    # 全券種払戻(券種別/軸入替バックテスト用)
    $payAll=@{}
    if($BetBacktest -or $AxisSwapBacktest){
        $cmd4=$conn.CreateCommand(); $cmd4.CommandTimeout=300
        $cmd4.CommandText="SELECT 開催日,レース番号,馬券,組番,金額 FROM 払戻金 WHERE 開催場所=@v AND 開催日>=@f AND 開催日<=@t"
        [void]$cmd4.Parameters.AddWithValue('@v',$Venue);[void]$cmd4.Parameters.AddWithValue('@f',$TestFrom);[void]$cmd4.Parameters.AddWithValue('@t',$TestTo)
        $r4=$cmd4.ExecuteReader()
        while($r4.Read()){ $key='{0}|{1:yyyy-MM-dd}|{2}' -f $Venue,$r4.GetDateTime(0),$r4.GetInt32(1); $bk=$r4.GetString(2); $kumi=([string]$r4.GetValue(3)).Trim(); if($kumi -eq ''){continue}; $amt=[double]$r4.GetValue(4)
            if(-not $payAll.ContainsKey($key)){$payAll[$key]=@{}}; if(-not $payAll[$key].ContainsKey($bk)){$payAll[$key][$bk]=@{}}
            $parts=$kumi -split '-'; $norm= if($bk -eq '三連単' -or $bk -eq '馬連単' -or $bk -eq '枠連単'){($parts -join '-')}else{(($parts|ForEach-Object{[int]$_}|Sort-Object) -join '-')}
            $payAll[$key][$bk][$norm]=$amt }
        $r4.Close()
        Write-Host ("  全券種払戻ロード: {0:N0}レース" -f $payAll.Count)
    }

    # ===== Pass1: 各対象レースのZベクトル+結果を保存 =====
    $targets = $races.Values | Where-Object { $_.v -eq $Venue -and $_.d -ge [datetime]$TestFrom -and $_.d -le [datetime]$TestTo } | Sort-Object d, rno
    $store=@()   # 各レース: @{ ents=@(@{nm;uma;c;zh;zk;zj;zd;ok}); key }
    foreach($rc in $targets){
        $rows=$rc.rows; if($rows.Count -lt 4){continue}
        $field=@($rows|ForEach-Object{$_.nm}); $fieldSet=@{}; $field|ForEach-Object{$fieldSet[$_]=$true}
        $td=$rc.d; $ck="$($rc.v)|$($rc.dist)"; $rkey='{0}|{1:yyyy-MM-dd}|{2}' -f $rc.v,$rc.d,$rc.rno

        # h2h margins
        $mavg=@{}
        foreach($a in $field){ $mavg[$a]=@{}; $tmp=@{}
            if($horseRuns.ContainsKey($a)){
                $runs=@($horseRuns[$a]|Where-Object{$_.date -lt $td -and $_.date -ge $td.AddDays(-$RecentDays)}|Sort-Object date -Descending|Select-Object -First $RecentN)
                foreach($run in $runs){ $rr=$races[$run.key]; $wt=$rr.win; if($wt -le 0){continue}
                    $ta=($rr.rows|Where-Object{$_.nm -eq $a}|Select-Object -First 1).t
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

        # 脚質(近走最頻)・脚質適性・枠適性・騎手・近走クラス(相手の強さ)・コンピ指数
        $kyaku=@{}; $draw=@{}; $jock=@{}; $cls=@{}; $frontUpFlag=@{}; $styleFinal=@{}; $compiVal=@{}
        foreach($row in $rows){ $a=$row.nm
            if($WithCompi -and $compi.ContainsKey($rkey) -and $compi[$rkey].ContainsKey([int]$row.uma)){ $compiVal[$a]=[double]$compi[$rkey][[int]$row.uma] }
            # 近走脚質 + 近走クラス(対戦した賞金水準)
            $cnt=@{}; $prizes=@()
            if($horseRuns.ContainsKey($a)){
                $runs=@($horseRuns[$a]|Where-Object{$_.date -lt $td -and $_.date -ge $td.AddDays(-$RecentDays)}|Sort-Object date -Descending|Select-Object -First $RecentN)
                foreach($run in $runs){ $rr=$races[$run.key]; $me=($rr.rows|Where-Object{$_.nm -eq $a}|Select-Object -First 1); if($null -eq $me){continue}; $s=StyleOf $me.early $rr.rows.Count; if($s -ne '?'){$cnt[$s]=$cnt[$s]+1}; if($rr.prize -gt 0){$prizes+=$rr.prize} }
            }
            $st= if($cnt.Count -gt 0){($cnt.GetEnumerator()|Sort-Object Value -Descending|Select-Object -First 1).Key}else{'?'}
            # 先行可能性アップグレード: 前残り場で 差し/追込/? の馬が「今走より短い直近レースで前目」+「前付率≥閾値の騎手への乗替」なら 先行 に読み替え
            $fUp=$false
            if($FrontUpgrade -and $frontVenues.ContainsKey($rc.v) -and ($st -eq '差し' -or $st -eq '追込' -or $st -eq '?')){
                $condA=$false
                if($horseRuns.ContainsKey($a)){
                    foreach($run in @($horseRuns[$a]|Where-Object{$_.date -lt $td -and $_.date -ge $td.AddDays(-$RecentDays)})){
                        $rr2=$races[$run.key]; if($rr2.dist -gt 0 -and $rr2.dist -lt $rc.dist){ $me2=($rr2.rows|Where-Object{$_.nm -eq $a}|Select-Object -First 1)
                            if($me2 -and [int]$me2.early -gt 0 -and [int]$me2.early -le $rr2.rows.Count*0.33){ $condA=$true; break } } }
                }
                $pj=''; if($horseRuns.ContainsKey($a)){ $prun=@($horseRuns[$a]|Where-Object{$_.date -lt $td}|Sort-Object date -Descending|Select-Object -First 1)
                    if($prun.Count -ge 1){ $pme=($races[$prun[0].key].rows|Where-Object{$_.nm -eq $a}|Select-Object -First 1); if($pme){$pj=[string]$pme.jk} } }
                $tj=[string]$row.jk; $jf= if($jFront.ContainsKey("$($rc.v)|$tj") -and $jFront["$($rc.v)|$tj"].n -ge 30){[double]$jFront["$($rc.v)|$tj"].fr/$jFront["$($rc.v)|$tj"].n}else{0.0}
                if($condA -and $tj -ne '' -and $tj -ne $pj -and $jf -ge $FrontJkThresh){ $st='先行'; $fUp=$true }
            }
            $frontUpFlag[$a]=$fUp; $styleFinal[$a]=$st
            $kr= if($st -ne '?' -and $styleWin.ContainsKey($ck)){ Rate $styleWin[$ck][$st] } else { $null }
            $kyaku[$a]= if($null -ne $kr){$kr}else{0.0}
            $g= if($row.uma -le 4){'内'}elseif($row.uma -le 8){'中'}else{'外'}
            $dr= if($drawWin.ContainsKey($ck)){ Rate $drawWin[$ck][$g] } else { $null }
            $draw[$a]= if($null -ne $dr){$dr}else{0.0}
            $jr= if($row.jk -ne '' -and $jWin.ContainsKey("$($rc.v)|$($row.jk)")){ $hh=$jWin["$($rc.v)|$($row.jk)"]; if($hh.n -ge 30){[double]$hh.w/$hh.n}else{$null} } else { $null }
            $jock[$a]= if($null -ne $jr){$jr}else{0.0}
            $cls[$a]= if($prizes.Count -gt 0){($prizes|Measure-Object -Average).Average}else{0.0}
        }
        $clsMean=(@($cls.Values|Where-Object{$_ -gt 0})|Measure-Object -Average).Average; if(-not $clsMean){$clsMean=0}
        foreach($a in $field){ if($cls[$a] -eq 0){ $cls[$a]=$clsMean } }   # 不明はクラス平均で中立化
        $zh=Zmap $h2h; $zk=Zmap $kyaku; $zj=Zmap $jock; $zd=Zmap $draw; $zc=Zmap $cls; $zp=Zmap $compiVal
        $ents=foreach($row in $rows){ $a=$row.nm
            @{ nm=$a; uma=$row.uma; c=$row.c; zh=[double]($zh[$a]); zk=[double]($zk[$a]); zj=[double]($zj[$a]); zd=[double]($zd[$a]); zc=[double]($zc[$a]); zp=[double]($zp[$a]); hasP=($compiVal.ContainsKey($a)); ok=($h2h.ContainsKey($a) -and $cmpCnt[$a] -ge $MinCompare); fUp=[bool]$frontUpFlag[$a]; kg=[string]$styleFinal[$a] }
        }
        $store += @{ key=('{0}|{1:yyyy-MM-dd}|{2}' -f $rc.v,$rc.d,$rc.rno); ents=$ents }
    }
    Write-Host ("対象レース: {0:N0}" -f $store.Count)

    # ===== Pass2: 重みスイープ =====
    # 重み = h2h/脚質/騎手/枠/クラス
    $grid=@(
        @{n='h2h単独           ';h=1.0;k=0.0;j=0.0;d=0.0;c=0.0},
        @{n='0.5/0.2/0.2/0.1/0  ';h=0.5;k=0.2;j=0.2;d=0.1;c=0.0},
        @{n='0.45/0.2/0.15/0.1/0.1';h=0.45;k=0.2;j=0.15;d=0.1;c=0.1},
        @{n='0.4/0.2/0.2/0.1/0.1 ';h=0.4;k=0.2;j=0.2;d=0.1;c=0.1},
        @{n='0.4/0.15/0.15/0.1/0.2';h=0.4;k=0.15;j=0.15;d=0.1;c=0.2},
        @{n='0.5/0.15/0.15/0.05/0.15';h=0.5;k=0.15;j=0.15;d=0.05;c=0.15},
        @{n='0.35/0.2/0.2/0.1/0.15';h=0.35;k=0.2;j=0.2;d=0.1;c=0.15},
        @{n='0.6/0.1/0.1/0.05/0.15';h=0.6;k=0.1;j=0.1;d=0.05;c=0.15}
    )
    # コンピ指数(p)を加えた比較行。同じ軸候補プール(h2h ok/fUp)内で、コンピ単独/ブレンドが確度・回収を上げるか検証。
    if($WithCompi){
        $grid += @(
            @{n='コンピ単独              ';h=0;k=0;j=0;d=0;c=0;p=1.0},
            @{n='h2h0.5 + コンピ0.5      ';h=0.5;k=0;j=0;d=0;c=0;p=0.5},
            @{n='標準(.5/.2/.2/.1)+コンピ0.3';h=0.5;k=0.2;j=0.2;d=0.1;c=0;p=0.3},
            @{n='標準 + コンピ0.5         ';h=0.5;k=0.2;j=0.2;d=0.1;c=0;p=0.5},
            @{n='.4/.15/.15/.1/ク.1/コ.1   ';h=0.4;k=0.15;j=0.15;d=0.1;c=0.1;p=0.1}
        )
    }
    $report=foreach($g in $grid){
        $n=0;$win=0;$top3=0;$bets=0;$ret=0.0
        foreach($race in $store){
            $cand=@($race.ents|Where-Object{$_.ok -or $_.fUp}); if($cand.Count -eq 0){continue}
            $best=$null; $bs=[double]::NegativeInfinity
            foreach($e in $cand){ $sc=$g.h*$e.zh+$g.k*$e.zk+$g.j*$e.zj+$g.d*$e.zd+$g.c*$e.zc+$g.p*$e.zp; if($sc -gt $bs){$bs=$sc;$best=$e} }
            $n++; if($best.c -eq 1){$win++}; if($best.c -le 3){$top3++}
            if($tansho.ContainsKey($race.key)){ $bets++; if($best.c -eq 1){ $p=$tansho[$race.key]["$($best.uma)"]; if($p){$ret+=$p/100.0} } }
        }
        [PSCustomObject]@{ 重み=$g.n; レース=$n; 勝率=[Math]::Round(100.0*$win/$n,1); 複勝率=[Math]::Round(100.0*$top3/$n,1); 単回収=if($bets){[Math]::Round(100.0*$ret/$bets,1)}else{$null} }
    }
    Write-Host ("`n=== 軸有力度 重み較正バックテスト ({0} {1}〜{2}) ===" -f $Venue,$TestFrom,$TestTo)
    Write-Host "(重み = h2h/脚質/騎手/枠/クラス)"
    $report | Format-Table 重み, レース, 勝率, 複勝率, 単回収 -AutoSize | Out-String -Width 200 | Write-Host

    # 軸の脚質別 成績(標準重み0.5/0.2/0.2/0.1)。「軸が差し/追込のとき不利」警告の妥当性検証。
    $sg=@{h=0.5;k=0.2;j=0.2;d=0.1;c=0.0}; $byKg=@{}
    foreach($race in $store){
        $cand=@($race.ents|Where-Object{$_.ok -or $_.fUp}); if($cand.Count -eq 0){continue}
        $best=$null; $bs=[double]::NegativeInfinity
        foreach($e in $cand){ $sc=$sg.h*$e.zh+$sg.k*$e.zk+$sg.j*$e.zj+$sg.d*$e.zd; if($sc -gt $bs){$bs=$sc;$best=$e} }
        $kg= if($best.kg -and $best.kg -ne ''){$best.kg}else{'?'}
        if(-not $byKg.ContainsKey($kg)){$byKg[$kg]=@{n=0;w=0;t3=0;bets=0;ret=0.0}}
        $byKg[$kg].n++; if($best.c -eq 1){$byKg[$kg].w++}; if($best.c -le 3){$byKg[$kg].t3++}
        if($tansho.ContainsKey($race.key)){ $byKg[$kg].bets++; if($best.c -eq 1){ $p=$tansho[$race.key]["$($best.uma)"]; if($p){$byKg[$kg].ret+=$p/100.0} } }
    }
    Write-Host "`n--- 軸の脚質別 成績(標準重み0.5/0.2/0.2/0.1) 警告妥当性 ---"
    $kgRep=foreach($k in @('逃げ','先行','差し','追込','?')){ if($byKg.ContainsKey($k)){ $h=$byKg[$k]
        [PSCustomObject]@{ 軸脚質=$k; 軸数=$h.n; 構成比=[Math]::Round(100.0*$h.n/$store.Count,1); 勝率=[Math]::Round(100.0*$h.w/$h.n,1); 複勝率=[Math]::Round(100.0*$h.t3/$h.n,1); 単回収=if($h.bets){[Math]::Round(100.0*$h.ret/$h.bets,1)}else{$null} } } }
    $kgRep | Format-Table -AutoSize | Out-String -Width 200 | Write-Host

    # ===== コンピ×h2h併用 券種別バックテスト(-BetBacktest) =====
    if($BetBacktest){
        function KeyOfB([int[]]$arr,[bool]$ord){ if($ord){($arr -join '-')}else{(($arr|Sort-Object) -join '-')} }
        function PairsB($a){ $L=New-Object System.Collections.Generic.List[object]; for($i=0;$i -lt $a.Count;$i++){ for($j=$i+1;$j -lt $a.Count;$j++){ $L.Add(@($a[$i],$a[$j])) } }; return ,$L }
        $betStrats=@(
          @{n='複勝 本命        ';bk='複勝';  ord=$false;need=1;cb={param($R) $L=New-Object System.Collections.Generic.List[object];$L.Add(@($R[0]));,$L}},
          @{n='ワイド 軸-相手2-4 ';bk='ワイド';ord=$false;need=4;cb={param($R) $L=New-Object System.Collections.Generic.List[object];$L.Add(@($R[0],$R[1]));$L.Add(@($R[0],$R[2]));$L.Add(@($R[0],$R[3]));,$L}},
          @{n='馬連 軸-相手2-4   ';bk='馬連複';ord=$false;need=4;cb={param($R) $L=New-Object System.Collections.Generic.List[object];$L.Add(@($R[0],$R[1]));$L.Add(@($R[0],$R[2]));$L.Add(@($R[0],$R[3]));,$L}},
          @{n='三連複 軸-相手2-5 ';bk='三連複';ord=$false;need=5;cb={param($R) $L=New-Object System.Collections.Generic.List[object];foreach($p in (PairsB($R[1..4]))){ $L.Add(@($R[0],$p[0],$p[1])) };,$L}}
        )
        $betW=@(
          @{n='コンピ単独    ';h=0;k=0;j=0;d=0;c=0;p=1.0},
          @{n='標準+コンピ0.5 ';h=0.5;k=0.2;j=0.2;d=0.1;c=0;p=0.5}
        )
        Write-Host ("`n=== コンピ×h2h併用 券種別バックテスト ({0} {1}〜{2}) ===" -f $Venue,$TestFrom,$TestTo)
        foreach($w in $betW){
            $bagg=@{}; foreach($s in $betStrats){ $bagg[$s.n]=@{races=0;hit=0;stake=0.0;ret=0.0;pts=0} }
            foreach($race in $store){
                if(-not $payAll.ContainsKey($race.key)){ continue }
                $ranked=@($race.ents | Sort-Object @{e={$w.h*$_.zh+$w.k*$_.zk+$w.j*$_.zj+$w.d*$_.zd+$w.c*$_.zc+$w.p*$_.zp};Descending=$true},@{e={[int]$_.uma};Descending=$false})
                $R=@($ranked | ForEach-Object{ [int]$_.uma })
                if($R.Count -lt 2){ continue }
                foreach($s in $betStrats){
                    if($R.Count -lt $s.need){ continue }
                    $combos = & $s.cb $R
                    $book= if($payAll[$race.key].ContainsKey($s.bk)){$payAll[$race.key][$s.bk]}else{@{}}
                    $hit=$false;$rr=0.0
                    foreach($cmb in $combos){ $kk=KeyOfB $cmb $s.ord; if($book.ContainsKey($kk)){ $rr+=$book[$kk]; $hit=$true } }
                    $b=$bagg[$s.n];$b.races++;$b.pts+=$combos.Count;$b.stake+=100.0*$combos.Count;$b.ret+=$rr;if($hit){$b.hit++}
                }
            }
            Write-Host ("`n--- ランキング重み: {0} ---" -f $w.n.Trim())
            $brep=foreach($s in $betStrats){ $b=$bagg[$s.n]; if($b.races -eq 0){continue}
                [PSCustomObject]@{ 戦略=$s.n.Trim(); 券種=$s.bk; レース=$b.races; 平均点=[Math]::Round($b.pts/$b.races,1); 的中率=[Math]::Round(100.0*$b.hit/$b.races,1); 回収率=[Math]::Round(100.0*$b.ret/$b.stake,1) } }
            $brep | Format-Table 戦略,券種,レース,平均点,的中率,回収率 -AutoSize | Out-String -Width 160 | Write-Host
        }
    }

    # ===== 軸入替検証(-AxisSwapBacktest): 選別×3連複相手3頭, コンピ純/独自純/併用/入替 を IS/OOS =====
    if($AxisSwapBacktest){
        $splitDt=[datetime]$Split
        function KeyDate($k){ [datetime]($k.Split('|')[1]) }
        # コンピ順位別勝率(IS=Split以前のstoreで較正)
        $MRc=20; $cc=@(0)*($MRc+1); $cw=@(0)*($MRc+1)
        foreach($race in $store){ if((KeyDate $race.key) -gt $splitDt){continue}
            $ce=@($race.ents|Where-Object{$_.hasP}|Sort-Object @{e={$_.zp};Descending=$true})
            for($i=0;$i -lt $ce.Count -and ($i+1) -le $MRc;$i++){ $cc[$i+1]++; if($ce[$i].c -eq 1){$cw[$i+1]++} } }
        $wr=@(0.0)*($MRc+1); for($i=1;$i -le $MRc;$i++){ if($cc[$i] -gt 0){$wr[$i]=[double]$cw[$i]/$cc[$i]} }
        function TP3([double]$pa,[double]$pb,[double]$pc){ $pm=@(@($pa,$pb,$pc),@($pa,$pc,$pb),@($pb,$pa,$pc),@($pb,$pc,$pa),@($pc,$pa,$pb),@($pc,$pb,$pa)); $t=0.0; foreach($q in $pm){ $d1=1.0-$q[0]; if($d1 -le 0){continue}; $d2=1.0-$q[0]-$q[1]; if($d2 -le 0){continue}; $t+=$q[0]*($q[1]/$d1)*($q[2]/$d2)}; $t }
        function Own($e){ 0.5*$e.zh+0.2*$e.zk+0.2*$e.zj+0.1*$e.zd }   # 独自分析(軸有力度 標準重み, コンピ無し)
        $methods=@('コンピ純','独自純','併用blend','入替swap')
        $agg=@{}; foreach($m in $methods){ $agg[$m]=@{IS=@{r=0;h=0;s=0.0;ret=0.0};OOS=@{r=0;h=0;s=0.0;ret=0.0}} }
        $opPairs=@(@(0,1),@(0,2),@(0,3),@(1,2),@(1,3),@(2,3))
        foreach($race in $store){
            if(-not $payAll.ContainsKey($race.key)){continue}
            $ents=$race.ents; $field=$ents.Count
            $ce=@($ents|Where-Object{$_.hasP}|Sort-Object @{e={$_.zp};Descending=$true},@{e={[int]$_.uma};Descending=$false})
            if($ce.Count -lt 5){continue}
            $Rc=@($ce|ForEach-Object{[int]$_.uma})
            # コンピ期待的中(4相手, 全頭正規化)で選別
            $praw=@{}; $sf=0.0
            foreach($e in $ents){ $rk= if($e.hasP){([array]::IndexOf($Rc,[int]$e.uma))+1}else{0}; $pr= if($rk -ge 1 -and $rk -le $MRc){$wr[$rk]}else{0.005}; if($pr -le 0){$pr=0.005}; $praw[[int]$e.uma]=$pr; $sf+=$pr }
            if($sf -le 0){$sf=1}
            $axc=$Rc[0]; $opp4=@($Rc[1..4])
            $eh=0.0; foreach($pr in $opPairs){ $pi=$praw[$opp4[$pr[0]]]/$sf; $pj=$praw[$opp4[$pr[1]]]/$sf; $eh += TP3 ($praw[$axc]/$sf) $pi $pj }
            if(-not($field -le $BetFieldMax -and $eh -ge $BetEhMin)){continue}
            $Ru=@($ents|Sort-Object @{e={Own $_};Descending=$true},@{e={[int]$_.uma};Descending=$false}|ForEach-Object{[int]$_.uma})
            $Rb=@($ents|Sort-Object @{e={(Own $_)+0.5*$_.zp};Descending=$true},@{e={[int]$_.uma};Descending=$false}|ForEach-Object{[int]$_.uma})
            $top=@{}; foreach($e in $ents){ if($e.c -ge 1 -and $e.c -le 3){$top[$e.c]=[int]$e.uma} }
            if(-not($top.ContainsKey(1) -and $top.ContainsKey(2) -and $top.ContainsKey(3))){continue}
            $set=@($top[1],$top[2],$top[3])
            $period= if((KeyDate $race.key) -le $splitDt){'IS'}else{'OOS'}
            $book= if($payAll[$race.key].ContainsKey('三連複')){$payAll[$race.key]['三連複']}else{@{}}
            foreach($m in $methods){
                if($m -eq 'コンピ純'){ $ax=$Rc[0]; $rel=@($Rc[1..3]) }
                elseif($m -eq '独自純'){ $ax=$Ru[0]; $rel=@($Ru[1..3]) }
                elseif($m -eq '併用blend'){ $ax=$Rb[0]; $rel=@($Rb[1..3]) }
                else { $ownRankAxc=([array]::IndexOf($Ru,$axc))+1
                    if($ownRankAxc -ge 1 -and $ownRankAxc -le $SwapK){ $ax=$axc } else { $ax=$Ru[0] }
                    $rel=@($Rc | Where-Object{$_ -ne $ax} | Select-Object -First 3) }
                if($rel.Count -lt 3){continue}
                $oppSet=@{}; $rel|ForEach-Object{$oppSet[$_]=$true}
                $hit= (($set -contains $ax) -and (@($set|Where-Object{$oppSet.ContainsKey($_)}).Count -eq 2))
                $ret=0.0; if($hit){ $sk=(($set|ForEach-Object{[int]$_}|Sort-Object) -join '-'); if($book.ContainsKey($sk)){$ret=$book[$sk]} }
                $a=$agg[$m][$period]; $a.r++; $a.s+=300.0; $a.ret+=$ret; if($hit){$a.h++}
            }
        }
        Write-Host ("`n=== 軸入替検証 選別×3連複相手3頭(3点) {0} (IS〜{1:yyyy-MM-dd}/OOS以降, 頭数≤{2}&コンピ期待≥{3}, SwapK={4}) ===" -f $Venue,$splitDt,$BetFieldMax,$BetEhMin,$SwapK)
        $rep=foreach($m in $methods){ $is=$agg[$m]['IS']; $oos=$agg[$m]['OOS']
            [PSCustomObject]@{ 方式=$m; IS_R=$is.r; IS_的中= if($is.r){[Math]::Round(100.0*$is.h/$is.r,1)}else{0}; IS_回収= if($is.r){[Math]::Round(100.0*$is.ret/$is.s,1)}else{0}
              OOS_R=$oos.r; OOS_的中= if($oos.r){[Math]::Round(100.0*$oos.h/$oos.r,1)}else{0}; OOS_回収= if($oos.r){[Math]::Round(100.0*$oos.ret/$oos.s,1)}else{0} } }
        $rep | Format-Table 方式,IS_R,IS_的中,IS_回収,OOS_R,OOS_的中,OOS_回収 -AutoSize | Out-String -Width 200 | Write-Host
        # 集計用 生値(場をまたいで合算するため)
        foreach($m in $methods){ $is=$agg[$m]['IS']; $oos=$agg[$m]['OOS']
            Write-Host ("RAW|{0}|{1}|{2}|{3}|{4}|{5}|{6}" -f $m,$is.r,$is.h,[int]$is.ret,$oos.r,$oos.h,[int]$oos.ret) }
    }
}
finally { $conn.Close() }
