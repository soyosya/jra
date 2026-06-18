<#
.SYNOPSIS
  指定日(既定:今日)の全レースを軸有力度で分析し、レースごとの推奨馬券を提示します。

.DESCRIPTION
  軸有力度 = h2h(共通対戦相手の着差) + 脚質適性 + 騎手 + 枠 を Z加重(検証済み 0.5/0.2/0.2/0.1)。
  各レースで 軸◎=#1 / 相手○▲=#2,#3 を選定し、検証結果に基づく推奨券種を出力。
   - 複勝 ◎     … 最も的中率が高い(高知62%/大井56%)
   - ワイド ◎-○▲ … 相手を軸有力度で自動選定した2点流し
  出馬表(レース情報)が必要。ばんえい除外。回収率は全戦略<100%(市場効率的)=利益保証ではなく
  「最も来やすい組み立て」を示すもの。
#>
[CmdletBinding()]
param(
    [string]$Date = (Get-Date).ToString('yyyy-MM-dd'),
    [string]$Venue = '',
    [int]$RecentN = 5, [int]$RecentDays = 183, [int]$MinCompare = 3, [int]$TopN = 6,
    [double]$Wh = 0.5, [double]$Wk = 0.2, [double]$Wj = 0.2, [double]$Wd = 0.1,
    # 危険ローテ減点(前走6着以下×中3週以内続戦)。検証で軸への影響は小さいが主用途は▼警告表示。
    [double]$RotePenalty = 0.2,
    # 買い目CSV出力。RakutenVote の入力(危険ローテ除外つき軸+上位相手)。
    [string]$ExportBets = '',
    [int]$PartnerCount = 4,
    # 診断: 指定レース番号のファクター分解(h2h/脚質/騎手/枠のZ・cmp数)と、h2hゲート除外時の代替軸を表示。
    [int]$DebugRno = 0,
    # 先行可能性アップグレード(前残り場): 今走より短い直近レースで前目+前付け型騎手への乗替なら脚質を先行と読み替え。
    [switch]$FrontUpgrade,
    [double]$FrontJkThresh = 0.38,
    # 前残り場(脚質ノート・FrontUpgrade対象)。明示指定(カンマ区切り)なければ逃げIV≥閾値で自動判定。
    [string]$FrontVenuesArg = '',
    [double]$FrontIVThresh = 2.0
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
    $histFrom=([datetime]$Date).AddDays(-$RecentDays).ToString('yyyy-MM-dd')
    Write-Host "履歴ロード中..."
    # 履歴(着順確定済み)— リーダー直読みで高速に構築
    $races=@{}; $horseRuns=@{}
    $hc=$conn.CreateCommand(); $hc.CommandTimeout=600
    $hc.CommandText=@"
SELECT kk.開催場所, kk.開催日, kk.レース番号, kk.馬名, kk.着順, kk.走破時計, kk.馬番,
  COALESCE(NULLIF(kk.一コーナー,0),NULLIF(kk.二コーナー,0),NULLIF(kk.三コーナー,0),NULLIF(kk.四コーナー,0))
FROM 競走結果 kk
WHERE kk.着順>0 AND kk.走破時計>0 AND kk.開催日>=@h AND kk.開催日<@d AND kk.開催場所 NOT LIKE '%ば'
"@
    [void]$hc.Parameters.AddWithValue('@h',$histFrom); [void]$hc.Parameters.AddWithValue('@d',$Date)
    $rd=$hc.ExecuteReader()
    while($rd.Read()){ $v=$rd.GetString(0);$d=$rd.GetDateTime(1);$rno=$rd.GetInt32(2);$nm=$rd.GetString(3);$c=$rd.GetInt32(4);$t=[double]$rd.GetDecimal(5);$uma=$rd.GetInt32(6);$early= if($rd.IsDBNull(7)){0}else{[int]$rd.GetValue(7)}
        $key='{0}|{1:yyyy-MM-dd}|{2}' -f $v,$d,$rno
        if(-not $races.ContainsKey($key)){ $races[$key]=@{rows=(New-Object System.Collections.Generic.List[object]);win=[double]::MaxValue;v=$v} }
        $races[$key].rows.Add(@{nm=$nm;t=$t;c=$c;uma=$uma;early=$early}); if($t -lt $races[$key].win){$races[$key].win=$t}
        if(-not $horseRuns.ContainsKey($nm)){$horseRuns[$nm]=(New-Object System.Collections.Generic.List[object])}; $horseRuns[$nm].Add(@{date=$d;key=$key})
    }
    $rd.Close()
    Write-Host ("  履歴 {0:N0}レース / {1:N0}頭" -f $races.Count,$horseRuns.Count)
    # データ鮮度チェック: 直近開催日の結果(着順・走破時計)が未充足だと h2h/脚質が不安定になりレーティングがぶれる
    $frFilter= if($Venue -ne ''){'AND 開催場所=@fv'}else{"AND 開催場所 NOT LIKE '%ば'"}
    $frP=@{'@d'=$Date}; if($Venue -ne ''){$frP['@fv']=$Venue}
    $fr = Invoke-Rows @"
WITH le AS (SELECT MAX(開催日) d FROM レース情報 WHERE 開催日<@d $frFilter)
SELECT CONVERT(varchar,le.d,23) ld,
  (SELECT COUNT(*) FROM レース情報 ri WHERE ri.開催日=le.d $frFilter) ent,
  (SELECT COUNT(*) FROM 競走結果 kk WHERE kk.開催日=le.d $frFilter AND kk.着順>0 AND kk.走破時計>0) fin
FROM le
"@ $frP
    $frA=@($fr)
    if($frA.Count -ge 1 -and $null -ne $frA[0].ld){
        $ld=[string]$frA[0].ld; $en=[int]$frA[0].ent; $fn=[int]$frA[0].fin
        $ratio= if($en -gt 0){[int][Math]::Round(100.0*$fn/$en,0)}else{0}
        if($ratio -lt 90){ Write-Host ("  [!] データ鮮度注意: 直近開催 {0} の結果充足 {1}% (出馬{2}/結果{3}) — バックフィル未完の可能性。レーティングが不安定なので再取得後の再実行を推奨" -f $ld,$ratio,$en,$fn) }
        else { Write-Host ("  データ鮮度OK: 直近開催 {0} 結果充足 {1}% ({2}/{3})" -f $ld,$ratio,$fn,$en) }
    }

    # コース傾向(場×距離)— SQL側で集計(脚質別/枠別の勝率)
    $styleWin=@{}; $drawWin=@{}
    function Rate($h){ if($null -eq $h -or $h.n -eq 0){return $null}; return [double]$h.w/$h.n }
    $sb = Invoke-Rows @"
WITH k AS (
  SELECT kk.開催場所 v, r.距離 dist, kk.着順 c,
    COALESCE(NULLIF(kk.一コーナー,0),NULLIF(kk.二コーナー,0),NULLIF(kk.三コーナー,0),NULLIF(kk.四コーナー,0)) early,
    COUNT(*) OVER(PARTITION BY kk.開催場所,kk.開催日,kk.レース番号) tou
  FROM 競走結果 kk JOIN レース情報 r ON r.開催場所=kk.開催場所 AND r.開催日=kk.開催日 AND r.レース番号=kk.レース番号 AND r.馬番=kk.馬番
  WHERE kk.着順>0 AND kk.開催日>='2024-01-01' AND kk.開催日<@d AND kk.開催場所 NOT LIKE '%ば'
)
SELECT v, dist, 脚質=CASE WHEN early IS NULL OR early=0 THEN N'?' WHEN early=1 THEN N'逃げ' WHEN early<=tou*0.33 THEN N'先行' WHEN early<=tou*0.66 THEN N'差し' ELSE N'追込' END,
  COUNT(*) n, SUM(CASE WHEN c=1 THEN 1 ELSE 0 END) w
FROM k GROUP BY v, dist, CASE WHEN early IS NULL OR early=0 THEN N'?' WHEN early=1 THEN N'逃げ' WHEN early<=tou*0.33 THEN N'先行' WHEN early<=tou*0.66 THEN N'差し' ELSE N'追込' END
"@ @{'@d'=$Date}
    foreach($x in $sb){ if($null -eq $x.dist){continue}; $ck="$($x.v)|$([int]$x.dist)"; if(-not $styleWin.ContainsKey($ck)){$styleWin[$ck]=@{}}; $styleWin[$ck][[string]$x.脚質]=@{n=[int]$x.n;w=[int]$x.w} }
    $db = Invoke-Rows @"
SELECT kk.開催場所 v, r.距離 dist, CASE WHEN kk.馬番<=4 THEN N'内' WHEN kk.馬番<=8 THEN N'中' ELSE N'外' END grp,
  COUNT(*) n, SUM(CASE WHEN kk.着順=1 THEN 1 ELSE 0 END) w
FROM 競走結果 kk JOIN レース情報 r ON r.開催場所=kk.開催場所 AND r.開催日=kk.開催日 AND r.レース番号=kk.レース番号 AND r.馬番=kk.馬番
WHERE kk.着順>0 AND kk.開催日>='2024-01-01' AND kk.開催日<@d AND kk.開催場所 NOT LIKE '%ば'
GROUP BY kk.開催場所, r.距離, CASE WHEN kk.馬番<=4 THEN N'内' WHEN kk.馬番<=8 THEN N'中' ELSE N'外' END
"@ @{'@d'=$Date}
    foreach($x in $db){ if($null -eq $x.dist){continue}; $ck="$($x.v)|$([int]$x.dist)"; if(-not $drawWin.ContainsKey($ck)){$drawWin[$ck]=@{}}; $drawWin[$ck][[string]$x.grp]=@{n=[int]$x.n;w=[int]$x.w} }
    # 騎手勝率(場・2024+)
    $jr = Invoke-Rows @"
SELECT r.開催場所 v, r.騎手 jk, COUNT(*) n, SUM(CASE WHEN kk.着順=1 THEN 1 ELSE 0 END) w
FROM レース情報 r JOIN 競走結果 kk ON kk.開催場所=r.開催場所 AND kk.開催日=r.開催日 AND kk.レース番号=r.レース番号 AND kk.馬番=r.馬番
WHERE kk.着順>0 AND r.開催日>='2024-01-01' AND r.開催日<@d AND r.開催場所 NOT LIKE '%ば'
GROUP BY r.開催場所, r.騎手
"@ @{'@d'=$Date}
    $jStat=@{}; foreach($x in $jr){ if([int]$x.n -ge 30){ $jStat["$($x.v)|$($x.jk)"]=[double]$x.w/[int]$x.n } }

    # 馬体重の履歴(馬名 -> 日付降順の{date,馬体重}リスト)。前々走馬体重の取得に使う。
    $bwHist=@{}
    $bwr = Invoke-Rows "SELECT 開催日 d, 馬名 nm, 馬体重 bw FROM レース情報 WHERE 開催日<=@d AND 開催日>=@h AND 馬体重>0 AND 開催場所 NOT LIKE '%ば'" @{'@d'=$Date;'@h'=$histFrom}
    foreach($x in $bwr){ $nm=[string]$x.nm; if(-not $bwHist.ContainsKey($nm)){$bwHist[$nm]=(New-Object System.Collections.Generic.List[object])}; $bwHist[$nm].Add(@{date=[datetime]$x.d; bw=[int]$x.bw}) }
    # -10kg妙味が有効な場(検証で勝率・回収率が高い)。川崎は別検証で妙味なしと判明し除外(kawasaki-bet-value)。
    $valueVenues=@{'高知'=$true;'佐賀'=$true}

    # 園田: 前走の距離・クラス(一着賞金) -> 距離替わり/昇降級フラグ用(直近走を採用)。騎手は乗替検出用。
    $prevInfo=@{}
    $pv = Invoke-Rows "SELECT 馬名 nm, 距離 dist, 一着賞金 prize, 開催日 d, 騎手 jk FROM レース情報 WHERE 開催日<@d AND 開催日>=@h AND 開催場所 NOT LIKE '%ば'" @{'@d'=$Date;'@h'=$histFrom}
    foreach($x in $pv){ $nm=[string]$x.nm; $dt=[datetime]$x.d; if(-not $prevInfo.ContainsKey($nm) -or $dt -gt $prevInfo[$nm].d){ $prevInfo[$nm]=@{d=$dt; dist= if($null -ne $x.dist){[int]$x.dist}else{0}; prize= if($null -ne $x.prize){[double]$x.prize}else{0.0}; jk= if($null -ne $x.jk){[string]$x.jk}else{''}} } }
    # 前残り場の判定: -FrontVenues 明示指定があればそれを使用、なければ逃げIV(=逃げ勝率/全体平均勝率)≥閾値の場を自動採用。
    $frontVenues=@{}
    if($FrontVenuesArg -ne ''){ foreach($vn in ($FrontVenuesArg -split ',')){ $vn=$vn.Trim(); if($vn -ne ''){$frontVenues[$vn]=$true} } }
    else {
        $vAgg=@{}
        foreach($ck in $styleWin.Keys){ $vv=$ck.Split('|')[0]; if(-not $vAgg.ContainsKey($vv)){$vAgg[$vv]=@{rw=0;rn=0;w=0;n=0}}
            foreach($st in $styleWin[$ck].Keys){ $h=$styleWin[$ck][$st]; $vAgg[$vv].w+=$h.w; $vAgg[$vv].n+=$h.n; if($st -eq '逃げ'){$vAgg[$vv].rw+=$h.w; $vAgg[$vv].rn+=$h.n} } }
        $fvList=@()
        foreach($vv in $vAgg.Keys){ $a=$vAgg[$vv]; if($a.n -ge 2000 -and $a.rn -ge 100 -and $a.w -gt 0){ $avg=[double]$a.w/$a.n; $liv= if($avg -gt 0){([double]$a.rw/$a.rn)/$avg}else{0}
            if($liv -ge $FrontIVThresh){ $frontVenues[$vv]=$true; $fvList+=("{0}(逃IV{1:N1})" -f $vv,$liv) } } }
        if($fvList.Count -gt 0){ Write-Host ("  前残り場(逃げIV≥{0}自動判定): {1}" -f $FrontIVThresh,($fvList -join ' ')) }
    }
    # 先行可能性ロジック用: レース距離マップ + 騎手前付率。
    $raceDist=@{}; $jFront=@{}
    if($FrontUpgrade){
        $rdq = Invoke-Rows "SELECT DISTINCT 開催場所 v, 開催日 d, レース番号 rno, 距離 dist FROM レース情報 WHERE 開催日>=@h AND 開催日<@d AND 開催場所 NOT LIKE '%ば' AND 距離>0" @{'@d'=$Date;'@h'=$histFrom}
        foreach($x in $rdq){ $k='{0}|{1:yyyy-MM-dd}|{2}' -f [string]$x.v,[datetime]$x.d,[int]$x.rno; $raceDist[$k]=[int]$x.dist }
        $jfq = Invoke-Rows @"
WITH pos AS (
  SELECT r.開催場所 v, r.騎手 jk,
    COALESCE(NULLIF(kk.一コーナー,0),NULLIF(kk.二コーナー,0),NULLIF(kk.三コーナー,0),NULLIF(kk.四コーナー,0)) early,
    COUNT(*) OVER(PARTITION BY kk.開催場所,kk.開催日,kk.レース番号) n
  FROM 競走結果 kk JOIN レース情報 r ON r.開催場所=kk.開催場所 AND r.開催日=kk.開催日 AND r.レース番号=kk.レース番号 AND r.馬番=kk.馬番
  WHERE kk.着順>0 AND r.開催日>='2024-01-01' AND r.開催日<@d AND r.開催場所 NOT LIKE '%ば'
)
SELECT v, jk, COUNT(*) cnt, SUM(CASE WHEN early IS NOT NULL AND early<=n*0.33 THEN 1 ELSE 0 END) fr
FROM pos GROUP BY v, jk
"@ @{'@d'=$Date}
        foreach($x in $jfq){ $c=[int]$x.cnt; if($c -ge 30){ $jFront["$($x.v)|$($x.jk)"]=[double]$x.fr/$c } }
    }
    # 園田の信頼厩舎(検証: 永島太=勝率20%安定/吉見真=直近2年で回収100%超)。前残り妙味の表示用。
    $trustStable=@{'園田|永島太'='◎厩';'園田|吉見真'='注厩'}
    # 川崎の堅い騎手×厩舎コンビ・厩舎(kawasaki-bet-value: 3年とも勝率/複勝が安定して高い軸補強)。
    #   野畑凌×鈴木義/甲田悟=毎年勝率~30%、矢野貴×高月賢=毎年複勝~57%(n204)、秋山直厩舎=回収3年連続>1.1(要監視)
    $kawaCombo=@{'野畑凌|鈴木義'='◎堅コンビ';'野畑凌|甲田悟'='◎堅コンビ';'矢野貴|高月賢'='○複勝堅'}
    $kawaStable=@{'秋山直'='注厩'}

    # 今日の出走馬
    $vfilter= if($Venue -ne ''){ "AND 開催場所=@v" } else { "AND 開催場所 NOT LIKE '%ば'" }
    $entParams=@{'@d'=$Date}; if($Venue -ne ''){ $entParams['@v']=$Venue }
    $ent = Invoke-Rows @"
SELECT 開催場所 v, レース番号 rno, 馬番 uma, 馬名 nm, 騎手 jk, 距離 dist, 馬体重 zw, 調教師 tr, 馬場 baba, 一着賞金 prize
FROM レース情報 WHERE 開催日=@d $vfilter ORDER BY 開催場所, レース番号, 馬番
"@ $entParams
    if($ent.Count -eq 0){ Write-Host "出馬表が見つかりません: $Date"; return }

    # レースごとに処理
    $byRace = $ent | Group-Object v, rno
    Write-Host ("対象: {0} 全{1}レース`n" -f $Date, $byRace.Count)
    $betRows = @()   # 買い目CSV(ExportBets指定時)

    foreach($grp in $byRace){
        $rws=$grp.Group; $v=[string]$rws[0].v; $rno=[int]$rws[0].rno; $dist=[int]$rws[0].dist; $ck="$v|$dist"
        $baba= if($null -ne $rws[0].baba){[string]$rws[0].baba}else{''}; $racePrize= if($null -ne $rws[0].prize){[double]$rws[0].prize}else{0.0}
        $heavy=($baba -eq '重' -or $baba -eq '不良')
        $field=@($rws|ForEach-Object{[string]$_.nm}); $fieldSet=@{}; $field|ForEach-Object{$fieldSet[$_]=$true}; $td=[datetime]$Date
        # h2h
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
        # 脚質/枠/騎手
        $kyaku=@{};$draw=@{};$jock=@{};$styleOf=@{};$frontUpFlag=@{}
        foreach($row in $rws){ $a=[string]$row.nm; $cnt=@{}
            if($horseRuns.ContainsKey($a)){ $runs=@($horseRuns[$a]|Where-Object{$_.date -lt $td -and $_.date -ge $td.AddDays(-$RecentDays)}|Sort-Object date -Descending|Select-Object -First $RecentN)
                foreach($run in $runs){ $rr=$races[$run.key]; $me=($rr.rows|Where-Object{$_.nm -eq $a}|Select-Object -First 1); if($null -eq $me){continue}; $s=StyleOf $me.early $rr.rows.Count; if($s -ne '?'){$cnt[$s]=$cnt[$s]+1} } }
            $st= if($cnt.Count -gt 0){($cnt.GetEnumerator()|Sort-Object Value -Descending|Select-Object -First 1).Key}else{'?'}
            # 先行可能性アップグレード: 前残り場で、今走より短い直近レースで前目(序盤top33%)に付け、かつ前付け型騎手への乗替なら 先行 と読み替え
            $fUp=$false
            if($FrontUpgrade -and $frontVenues.ContainsKey($v) -and ($st -eq '差し' -or $st -eq '追込' -or $st -eq '?')){
                $condA=$false
                if($horseRuns.ContainsKey($a)){
                    foreach($run in @($horseRuns[$a]|Where-Object{$_.date -lt $td -and $_.date -ge $td.AddDays(-$RecentDays)})){
                        $rd2= if($raceDist.ContainsKey($run.key)){[int]$raceDist[$run.key]}else{0}
                        if($rd2 -gt 0 -and $rd2 -lt $dist){ $rr=$races[$run.key]; $me=($rr.rows|Where-Object{$_.nm -eq $a}|Select-Object -First 1)
                            if($me -and [int]$me.early -gt 0 -and [int]$me.early -le $rr.rows.Count*0.33){ $condA=$true; break } } }
                }
                $tj=[string]$row.jk; $pj= if($prevInfo.ContainsKey($a)){[string]$prevInfo[$a].jk}else{''}
                $jf= if($jFront.ContainsKey("$v|$tj")){[double]$jFront["$v|$tj"]}else{0.0}
                if($condA -and $tj -ne '' -and $tj -ne $pj -and $jf -ge $FrontJkThresh){ $st='先行'; $fUp=$true }
            }
            $styleOf[$a]=$st; $frontUpFlag[$a]=$fUp
            $kr= if($st -ne '?' -and $styleWin.ContainsKey($ck)){Rate $styleWin[$ck][$st]}else{$null}; $kyaku[$a]= if($null -ne $kr){$kr}else{0.0}
            $g= if([int]$row.uma -le 4){'内'}elseif([int]$row.uma -le 8){'中'}else{'外'}; $dr= if($drawWin.ContainsKey($ck)){Rate $drawWin[$ck][$g]}else{$null}; $draw[$a]= if($null -ne $dr){$dr}else{0.0}
            $jk=[string]$row.jk; $jw= if($jStat.ContainsKey("$v|$jk")){$jStat["$v|$jk"]}else{$null}; $jock[$a]= if($null -ne $jw){$jw}else{0.0} }
        $zh=Zmap $h2h;$zk=Zmap $kyaku;$zj=Zmap $jock;$zd=Zmap $draw
        $scored=foreach($row in $rws){ $a=[string]$row.nm
            $ok=($h2h.ContainsKey($a) -and $cmp[$a] -ge $MinCompare)
            $ax= $Wh*[double]($zh[$a])+$Wk*[double]($zk[$a])+$Wj*[double]($zj[$a])+$Wd*[double]($zd[$a])
            # 危険ローテ: 前走6着以下×中3週以内(≤27日)の続戦。休明け(履歴外/間隔大)は非該当。減点+▼表示。
            $rote=$false
            if($horseRuns.ContainsKey($a)){
                $pr=@($horseRuns[$a]|Where-Object{$_.date -lt $td}|Sort-Object date -Descending|Select-Object -First 1)
                if($pr.Count -ge 1){ $prr=$races[$pr[0].key]; $me=($prr.rows|Where-Object{$_.nm -eq $a}|Select-Object -First 1)
                    if($me){ $kan=($td - $pr[0].date).Days; if([int]$me.c -ge 6 -and $kan -le 27){ $rote=$true } } }
            }
            if($rote){ $ax = $ax - $RotePenalty }
            # 妙味(-10kg): 今走馬体重 - 前々走馬体重 <= -10、かつ有効な場のみ点灯
            $myo=''
            if($valueVenues.ContainsKey($v) -and $null -ne $row.zw -and [int]$row.zw -gt 0 -and $bwHist.ContainsKey($a)){
                $prev2=@($bwHist[$a]|Where-Object{$_.date -lt $td}|Sort-Object date -Descending|Select-Object -First 2)
                if($prev2.Count -ge 2 -and ([int]$row.zw - [int]$prev2[1].bw) -le -10){ $myo='妙味' }
            }
            # 園田: 距離替わり/昇降級(★短縮降級=堅い妙味 / 短縮=買い / ↓延長=軽視)・信頼厩舎
            $rota=''
            if($v -eq '園田' -and $prevInfo.ContainsKey($a) -and $prevInfo[$a].dist -gt 0){
                $pd=$prevInfo[$a].dist; $pp=$prevInfo[$a].prize
                if($dist -lt $pd){ $rota= if($pp -gt 0 -and $racePrize -gt 0 -and $racePrize -lt $pp){'★短縮降級'}else{'短縮'} }
                elseif($dist -gt $pd){ $rota='↓延長' }
            }
            $stb= if($trustStable.ContainsKey("$v|$([string]$row.tr)")){$trustStable["$v|$([string]$row.tr)"]}else{''}
            # 川崎: 堅さフラグ(kawasaki-bet-value)。同距離/中5-13週=堅い、大幅短縮(≥200m)=軽視、堅い騎手×厩舎コンビ・厩舎。
            $kawa=''
            if($v -eq '川崎'){
                $tags=@()
                if($prevInfo.ContainsKey($a)){
                    if($prevInfo[$a].dist -gt 0){
                        $pd=$prevInfo[$a].dist
                        if($dist -eq $pd){ $tags+='堅同距' }
                        elseif(($pd - $dist) -ge 200){ $tags+='▽大短縮' }
                    }
                    $gap=([datetime]$Date - $prevInfo[$a].d).Days
                    if($gap -ge 28 -and $gap -le 90){ $tags+='堅間隔' } elseif($gap -le 13){ $tags+='△詰' }
                }
                $cmbo="$([string]$row.jk)|$([string]$row.tr)"
                if($kawaCombo.ContainsKey($cmbo)){ $tags+=$kawaCombo[$cmbo] }
                elseif($kawaStable.ContainsKey([string]$row.tr)){ $tags+=$kawaStable[[string]$row.tr] }
                if($frontUpFlag[$a]){ $tags+='▲前替' }
                if($tags.Count -gt 0){ $kawa=($tags -join ' ') }
            }
            [PSCustomObject]@{ uma=[int]$row.uma; nm=$a; jk=[string]$row.jk; 脚質=$styleOf[$a]; ax=[Math]::Round($ax,2); ok=$ok; myo=$myo; rote=$rote; rota=$rota; stb=$stb; kawa=$kawa; frontUp=[bool]$frontUpFlag[$a] }
        }
        $ranked=@($scored|Sort-Object ax -Descending)
        # 軸候補: h2h確証(ok)に加え、▲前替(前残り場の先行可能性アップグレード)馬も薄h2hを上書きして候補に含める
        $cand=@($scored|Where-Object{$_.ok -or $_.frontUp}|Sort-Object ax -Descending)
        # 診断ダンプ: ファクター分解 + h2hゲート除外(共通相手無し馬はh2hを使わず脚質/騎手/枠を再正規化)の代替軸
        if($DebugRno -gt 0 -and $rno -eq $DebugRno){
            Write-Host ("`n--- [DEBUG] {0} {1}R ファクター分解 (MinCompare={2}, 重みWh{3}/Wk{4}/Wj{5}/Wd{6}) ---" -f $v,$rno,$MinCompare,$Wh,$Wk,$Wj,$Wd)
            Write-Host "  馬番 馬名           cmp  h2h   zh    脚質   zk(脚) zj(騎) zd(枠)  ax    ax代替 ok"
            $wsum=$Wk+$Wj+$Wd
            foreach($row in ($rws|Sort-Object {[double]($zh[[string]$_.nm])} -Descending)){ $a=[string]$row.nm
                $c=[int]$cmp[$a]; $hh= if($h2h.ContainsKey($a)){[Math]::Round([double]$h2h[$a],2)}else{$null}
                $okx=($h2h.ContainsKey($a) -and $c -ge $MinCompare)
                # 代替: cmp>=MinCompare はh2h込み、未満は脚質/騎手/枠のみ再正規化(h2h無視)
                $axAlt= if($okx){ $Wh*[double]($zh[$a])+$Wk*[double]($zk[$a])+$Wj*[double]($zj[$a])+$Wd*[double]($zd[$a]) } else { ($Wk*[double]($zk[$a])+$Wj*[double]($zj[$a])+$Wd*[double]($zd[$a]))/$wsum }
                Write-Host ("  {0,3} {1,-12} {2,3} {3,6} {4,6} {5,-5} {6,6} {7,6} {8,6} {9,6} {10,6} {11}" -f `
                    [int]$row.uma,$a,$c,$hh,[Math]::Round([double]$zh[$a],2),$styleOf[$a],[Math]::Round([double]$zk[$a],2),[Math]::Round([double]$zj[$a],2),[Math]::Round([double]$zd[$a],2),[Math]::Round([double]($Wh*$zh[$a]+$Wk*$zk[$a]+$Wj*$zj[$a]+$Wd*$zd[$a]),2),[Math]::Round($axAlt,2),$(if($okx){'○'}else{'*'})) }
            Write-Host "  (ax代替 = 共通相手無し[cmp<MinCompare]馬はh2hを使わず脚質/騎手/枠のみで再正規化した想定スコア)`n"
        }
        $babaNote= if($heavy){"  【{0}馬場=前残り強化:逃げ重視】" -f $baba}else{''}
        Write-Host ("=== {0} {1}R ({2}m) ===  レーティング上位{3}頭 (*=実績薄で低信頼){4}" -f $v,$rno,$dist,$TopN,$babaNote)
        $rank=0
        foreach($e in ($ranked|Select-Object -First $TopN)){ $rank++
            $mark= if(-not $e.ok){'*'}else{''}
            $mb= if($e.myo -ne ''){' ★'+$e.myo}else{''}
            $rb= if($e.rote){' ▼ローテ'}else{''}
            $sb2= if($e.stb -ne ''){' '+$e.stb}else{''}
            $ro= if($e.rota -ne ''){' '+$e.rota}else{''}
            $kw= if($e.kawa -ne ''){' '+$e.kawa}else{''}
            Write-Host ("  {0}位 {1,2}番 {2,-14} Rtg{3,6} 脚質{4} {5}{6}{7}{8}{9}{10}{11}" -f $rank,$e.uma,$e.nm,$e.ax,$e.脚質,$e.jk,$mark,$mb,$rb,$sb2,$ro,$kw) }
        # 軸の脚質ノート(前残り場): 検証(axis-backtest)で軸の勝率は 逃げ>先行>差し>追込。
        #   逃げ軸=最有力(直近勝率35.7%/複勝63%)で正フラグ、先行=堅め、差し/追込は前残り場で不利の警告(8Rアリハッピーの教訓)。
        function AxWarn($e){ if($null -eq $e){return ''}; if(-not $frontVenues.ContainsKey($v)){return ''}
            if($e.脚質 -eq '逃げ'){return '  ◎逃げ軸(前残り場で最有力・勝率/複勝/回収とも最上位)'}
            elseif($e.脚質 -eq '先行'){return '  ○先行軸(前残り場で堅め)'}
            elseif($e.脚質 -eq '差し'){return '  ⚠軸が差し(前残り場でやや不利)'}
            elseif($e.脚質 -eq '追込'){return '  ⚠軸が追込(前残り場で大不利・出し切れず凡走リスク)'}else{return ''} }
        if($cand.Count -ge 2){
            $gap=[Math]::Round($cand[0].ax-$cand[1].ax,2)
            $conf= if($gap -ge 0.8){'高(◎抜け)'}elseif($gap -ge 0.3){'中'}else{'低(混戦)'}
            Write-Host ("  → 軸◎{0}番 {1}  信頼度:{2}(差{3}){4}" -f $cand[0].uma,$cand[0].nm,$conf,$gap,(AxWarn $cand[0]))
        } elseif($ranked.Count -ge 1) {
            # 実績不足(h2h成立<2頭)。検証: レート最上位の暫定軸は勝率28%/複勝58%でランダム超→複勝向きの暫定軸△として提示(全面スキップしない)
            $tg= if($ranked.Count -ge 2){[Math]::Round($ranked[0].ax-$ranked[1].ax,2)}else{0}
            Write-Host ("  → 暫定軸△{0}番 {1}  実績薄・低信頼(検証 複勝58%/勝率28%・複勝向き)差{2}{3}" -f $ranked[0].uma,$ranked[0].nm,$tg,(AxWarn $ranked[0]))
        } else { Write-Host "  → 軸判定不可(出走馬の履歴なし)" }
        # 買い目CSV: 危険ローテ除外つき軸 + 上位相手PartnerCount頭
        if($ExportBets -ne ''){
            $axisCand=@($cand|Where-Object{ -not $_.rote })
            if($axisCand.Count -ge 1){
                $axis=$axisCand[0]
                $partners=@($cand|Where-Object{ $_.uma -ne $axis.uma }|Select-Object -First $PartnerCount)
                if($partners.Count -ge 2){
                    $rowObj=[ordered]@{ date=$Date; venue=$v; race=$rno; axis_uma=$axis.uma; axis_name=$axis.nm }
                    for($pi=0;$pi -lt $PartnerCount;$pi++){ $rowObj["p$($pi+1)"]= if($pi -lt $partners.Count){$partners[$pi].uma}else{''} }
                    $betRows += [PSCustomObject]$rowObj
                }
            }
        }
        Write-Host ""
    }
    if($ExportBets -ne ''){
        if($betRows.Count -gt 0){
            $betRows | Export-Csv -Path $ExportBets -NoTypeInformation -Encoding UTF8
            Write-Host ("買い目CSVを出力: {0} ({1}レース)" -f $ExportBets,$betRows.Count)
        } else { Write-Host "買い目CSV: 出力対象レースなし" }
    }
}
finally { $conn.Close() }
