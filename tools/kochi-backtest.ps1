<#
.SYNOPSIS
  高知スコアのバックテスト。前走脚質・同型不在・騎手前付力・馬場差補正後持ち時計を
  統合したスコアで各レースの本命を選び、払戻ベース回収率/的中率を検証期間で評価します。

.DESCRIPTION
  特徴量は全て事前入手可能なもののみ(未来リーク無し)。
    - 前走脚質    : 直近高知前走の脚質(逃げ/先行/差し/追込)
    - 同型頭数    : 当該レースの「前走前々(逃げ+先行)」馬の頭数(少ないほど前残り濃厚)
    - 騎手前付力  : 騎手の前々率。@TrainEnd 以前のみで算出(検証期間はリーク無し)
    - 補正後持時計: 自己ベスト(過去高知・同距離, 365日内)を日次馬場差δで補正し基準と比較
  検証期間(@TestStart 以降)で、レース毎に最高スコア馬を単勝・複勝¥100購入した回収率を、
  全頭買い基準・現行kochi-score相当(前走脚質+持時計のみ)と比較します。

  特徴量は CSV (_kochi_feat_cache.csv) にキャッシュ。-Refresh で再抽出。

.PARAMETER TrainEnd    学習期間の終端(この日まで)。既定 2025-09-30。
.PARAMETER TestStart   検証期間の開始(この日から)。既定 2025-10-01。
.PARAMETER Refresh     指定するとDBから特徴量を再抽出。
.EXAMPLE
  .\kochi-backtest.ps1 -Refresh
#>
[CmdletBinding()]
param(
    [string]$TrainEnd  = '2025-09-30',
    [string]$TestStart = '2025-10-01',
    [switch]$Refresh
)
$ErrorActionPreference = 'Stop'
$cachePath = Join-Path $PSScriptRoot '_kochi_feat_cache.csv'

$appsettings = Join-Path $PSScriptRoot '..\共通\appsettings.json'
if (Test-Path $appsettings) {
    $connStr = (Get-Content $appsettings -Raw -Encoding UTF8 | ConvertFrom-Json).ConnectionStrings.DefaultConnection
}
if ([string]::IsNullOrWhiteSpace($connStr)) {
    $connStr = "Server=192.168.168.81\SQLEXPRESS;Database=中央競馬;User Id=sa;Password=$($env:KEIBA_SA_PASSWORD);TrustServerCertificate=True;Connect Timeout=10"
}

$sql = @"
DECLARE @venue nvarchar(10)=N'高知';

IF OBJECT_ID('tempdb..#r') IS NOT NULL DROP TABLE #r;
SELECT k.開催日, k.レース番号, k.馬番, k.着順, rinfo.馬名, rinfo.距離, rinfo.一着賞金 cls, rinfo.騎手, k.走破時計 t,
  rinfo.調教師 tr, rinfo.馬主 ow, rinfo.馬場 ba,
  COALESCE(NULLIF(k.一コーナー,0),NULLIF(k.二コーナー,0),NULLIF(k.三コーナー,0),NULLIF(k.四コーナー,0)) early_pos,
  cnt.頭数
INTO #r FROM 競走結果 k
JOIN レース情報 rinfo ON rinfo.開催場所=@venue AND rinfo.開催日=k.開催日 AND rinfo.レース番号=k.レース番号 AND rinfo.馬番=k.馬番
CROSS APPLY (SELECT COUNT(*) 頭数 FROM 競走結果 k2 WHERE k2.開催場所=@venue AND k2.開催日=k.開催日 AND k2.レース番号=k.レース番号 AND k2.着順>0) cnt
WHERE k.開催場所=@venue AND k.着順>0;
CREATE INDEX ix1 ON #r(馬名,距離,開催日,レース番号);
CREATE INDEX ix2 ON #r(開催日,レース番号);

-- 距離×クラス 基準(2024+, 妥当時計)
IF OBJECT_ID('tempdb..#cell') IS NOT NULL DROP TABLE #cell;
SELECT 距離, cls, AVG(t) mean, COUNT(*) n INTO #cell FROM #r
WHERE 着順=1 AND 開催日>='2024-01-01' AND t>=距離/18.0 AND t<=距離/11.0 GROUP BY 距離, cls;
-- 距離中央値(代替基準)
IF OBJECT_ID('tempdb..#distmed') IS NOT NULL DROP TABLE #distmed;
SELECT DISTINCT 距離, PERCENTILE_CONT(0.5) WITHIN GROUP(ORDER BY t) OVER(PARTITION BY 距離) med
INTO #distmed FROM #r WHERE 着順=1 AND 開催日>='2024-01-01' AND t>=距離/18.0 AND t<=距離/11.0;

-- 日次馬場差 δ(全開催日; 期待は #cell/#distmed)
IF OBJECT_ID('tempdb..#delta') IS NOT NULL DROP TABLE #delta;
SELECT DISTINCT w.開催日, PERCENTILE_CONT(0.5) WITHIN GROUP(ORDER BY w.dev) OVER(PARTITION BY w.開催日) delta
INTO #delta FROM (
  SELECT r.開催日, r.t - COALESCE(c.mean, dm.med) dev
  FROM #r r
  LEFT JOIN #cell c ON c.距離=r.距離 AND c.cls=r.cls AND c.n>=8
  LEFT JOIN #distmed dm ON dm.距離=r.距離
  WHERE r.着順=1 AND r.t>=r.距離/18.0 AND r.t<=r.距離/11.0 AND (c.mean IS NOT NULL OR dm.med IS NOT NULL)
) w;

-- 特徴量(2024+ の全出走馬)
WITH feat AS (
  SELECT cur.開催日, cur.レース番号, cur.馬番, cur.着順, cur.距離, cur.cls, cur.騎手,
    cur.tr, cur.ow, cur.ba,
    cur.early_pos cur_early, cur.頭数 cur_heads,
    CASE WHEN prv.pe IS NULL THEN N'?' WHEN prv.pe=1 THEN N'逃げ'
         WHEN prv.pe<=prv.ph*0.33 THEN N'先行' WHEN prv.pe<=prv.ph*0.66 THEN N'差し' ELSE N'追込' END prevStyle,
    ab.adjbest, COALESCE(c2.mean, dm2.med) baseline
  FROM #r cur
  OUTER APPLY (SELECT TOP 1 p2.early_pos pe, p2.頭数 ph FROM #r p2
     WHERE p2.馬名=cur.馬名 AND (p2.開催日<cur.開催日 OR (p2.開催日=cur.開催日 AND p2.レース番号<cur.レース番号))
     ORDER BY p2.開催日 DESC, p2.レース番号 DESC) prv
  OUTER APPLY (SELECT MIN(p.t - d.delta) adjbest FROM #r p LEFT JOIN #delta d ON d.開催日=p.開催日
     WHERE p.馬名=cur.馬名 AND p.距離=cur.距離 AND p.t>=p.距離/18.0 AND p.t<=p.距離/11.0
       AND p.開催日<cur.開催日 AND p.開催日>=DATEADD(day,-365,cur.開催日)) ab
  LEFT JOIN #cell c2 ON c2.距離=cur.距離 AND c2.cls=cur.cls AND c2.n>=8
  LEFT JOIN #distmed dm2 ON dm2.距離=cur.距離
  WHERE cur.開催日>='2024-01-01'
),
flagged AS (
  SELECT *,
    SUM(CASE WHEN prevStyle IN(N'逃げ',N'先行') THEN 1 ELSE 0 END) OVER(PARTITION BY 開催日,レース番号) mae_cnt,
    SUM(CASE WHEN prevStyle=N'逃げ' THEN 1 ELSE 0 END) OVER(PARTITION BY 開催日,レース番号) nige_cnt
  FROM feat
)
SELECT f.開催日, f.レース番号, f.馬番, f.着順, f.距離, f.cls, f.騎手, f.tr, f.ow, f.ba, f.cur_early, f.cur_heads,
  f.prevStyle, f.adjbest, f.baseline, f.mae_cnt, f.nige_cnt,
  ptan.金額 win_pay, pfuku.金額 place_pay
FROM flagged f
LEFT JOIN 払戻金 ptan ON ptan.開催場所=@venue AND ptan.開催日=f.開催日 AND ptan.レース番号=f.レース番号 AND ptan.馬券=N'単勝' AND ptan.組番=CAST(f.馬番 AS nvarchar(8))
LEFT JOIN 払戻金 pfuku ON pfuku.開催場所=@venue AND pfuku.開催日=f.開催日 AND pfuku.レース番号=f.レース番号 AND pfuku.馬券=N'複勝' AND pfuku.組番=CAST(f.馬番 AS nvarchar(8))
ORDER BY f.開催日, f.レース番号, f.馬番;
"@

if ($Refresh -or -not (Test-Path $cachePath)) {
    Write-Host "DBから特徴量を抽出中..."
    $conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
    $conn.Open()
    try {
        $cmd = $conn.CreateCommand(); $cmd.CommandTimeout=600; $cmd.CommandText=$sql
        $r = $cmd.ExecuteReader()
        $rows = New-Object System.Collections.Generic.List[object]
        while ($r.Read()) {
            $rows.Add([PSCustomObject]@{
                date=$r['開催日'].ToString('yyyy-MM-dd'); rno=[int]$r['レース番号']; uma=[int]$r['馬番']
                chaku=[int]$r['着順']; dist=[int]$r['距離']; cls=[double]$r['cls']; jockey=[string]$r['騎手']
                tr=[string]$r['tr']; ow=[string]$r['ow']; ba=[string]$r['ba']
                curEarly= if($r['cur_early'] -is [DBNull]){0}else{[int]$r['cur_early']}
                heads=[int]$r['cur_heads']; prevStyle=[string]$r['prevStyle']
                adjbest= if($r['adjbest'] -is [DBNull]){''}else{[double]$r['adjbest']}
                baseline= if($r['baseline'] -is [DBNull]){''}else{[double]$r['baseline']}
                maeCnt=[int]$r['mae_cnt']; nigeCnt=[int]$r['nige_cnt']
                winPay= if($r['win_pay'] -is [DBNull]){0}else{[double]$r['win_pay']}
                placePay= if($r['place_pay'] -is [DBNull]){0}else{[double]$r['place_pay']}
                placed= if($r['place_pay'] -is [DBNull]){0}else{1}
            })
        }
        $r.Close()
        $rows | Export-Csv -Path $cachePath -NoTypeInformation -Encoding UTF8
        Write-Host ("特徴量 {0} 行を {1} にキャッシュ" -f $rows.Count, (Split-Path $cachePath -Leaf))
    } finally { $conn.Close() }
}

$all = Import-Csv $cachePath
Write-Host ("特徴量読込: {0} 行  学習〜{1}  検証{2}〜" -f $all.Count, $TrainEnd, $TestStart)

# 騎手前々率(学習期間のみ)
$jk=@{}
foreach($row in $all){
  if ($row.date -gt $TrainEnd) { continue }
  $e=[int]$row.curEarly; $h=[int]$row.heads
  if ($e -le 0 -or $h -le 0) { continue }
  $front = ($e -eq 1 -or $e -le $h*0.33)
  if (-not $jk.ContainsKey($row.jockey)) { $jk[$row.jockey]=[PSCustomObject]@{n=0;f=0} }
  $jk[$row.jockey].n++; if($front){ $jk[$row.jockey].f++ }
}
$jkRate=@{}
foreach($k in $jk.Keys){ if($jk[$k].n -ge 50){ $jkRate[$k]=100.0*$jk[$k].f/$jk[$k].n } }

# コネクション逃げ率(学習期間のみ): 三者(調教師|馬主|騎手)→ 厩舎|騎手 → 騎手 の順でフォールバック
# 逃げ = curEarly=1。リーク回避のため @TrainEnd 以前のみ集計。
$triple=@{}; $pair=@{}; $solo=@{}
foreach($row in $all){
  if ($row.date -gt $TrainEnd) { continue }
  $isLead = ([int]$row.curEarly -eq 1)
  $kt="$($row.tr)|$($row.ow)|$($row.jockey)"; $kp="$($row.tr)|$($row.jockey)"; $ks=$row.jockey
  foreach($pair2 in @(@($triple,$kt),@($pair,$kp),@($solo,$ks))){
    $h=$pair2[0]; $key=$pair2[1]
    if(-not $h.ContainsKey($key)){ $h[$key]=[PSCustomObject]@{n=0;l=0} }
    $h[$key].n++; if($isLead){ $h[$key].l++ }
  }
}
# row のコネクション逃げ率(0-1)を返す。標本が薄い段から十分なものを採用。
function ConnLead($row){
  $kt="$($row.tr)|$($row.ow)|$($row.jockey)"; $kp="$($row.tr)|$($row.jockey)"; $ks=$row.jockey
  if($triple.ContainsKey($kt) -and $triple[$kt].n -ge 20){ return $triple[$kt].l/$triple[$kt].n }
  if($pair.ContainsKey($kp)   -and $pair[$kp].n   -ge 30){ return $pair[$kp].l/$pair[$kp].n }
  if($solo.ContainsKey($ks)   -and $solo[$ks].n   -ge 50){ return $solo[$ks].l/$solo[$ks].n }
  return $null
}

# スコア関数
function ScoreNew($row){
  $s=0.0
  switch($row.prevStyle){ '逃げ'{$s+=2} '先行'{$s+=1} }
  # 同型不在: 前走前々(mae)頭数が少ないほど加点
  $mae=[int]$row.maeCnt
  if($row.prevStyle -eq '逃げ' -or $row.prevStyle -eq '先行'){
    if($mae -le 1){$s+=1.5} elseif($mae -eq 2){$s+=0.8}
  }
  # 騎手前付力
  $jr = if($jkRate.ContainsKey($row.jockey)){$jkRate[$row.jockey]}else{$null}
  if($jr -ne $null){ if($jr -ge 40){$s+=2} elseif($jr -ge 33){$s+=1} }
  # 補正後持ち時計
  if($row.adjbest -ne '' -and $row.baseline -ne ''){
    $edge=[double]$row.baseline-[double]$row.adjbest
    if($edge -ge 1.0){$s+=2} elseif($edge -gt 0){$s+=1}
  }
  # 距離(前残り妙味帯)
  $d=[int]$row.dist
  if($d -ge 1300 -and $d -le 1600){$s+=0.5}
  return $s
}
# 現行kochi-score相当(前走脚質+騎手+持時計, 同型/距離なし)
function ScoreOld($row){
  $s=0.0
  switch($row.prevStyle){ '逃げ'{$s+=2} '先行'{$s+=1} }
  $jr = if($jkRate.ContainsKey($row.jockey)){$jkRate[$row.jockey]}else{$null}
  if($jr -ne $null){ if($jr -ge 40){$s+=2} elseif($jr -ge 33){$s+=1} }
  if($row.adjbest -ne '' -and $row.baseline -ne ''){
    $edge=[double]$row.baseline-[double]$row.adjbest
    if($edge -ge 1.0){$s+=2} elseif($edge -gt 0){$s+=1}
  }
  return $s
}
# 改良スコアに「価値志向コネクション」と「馬場係数」を追加
# 注意: コネクション逃げ率を素朴に加点すると的中率は上がるが回収率は下がる
# (強コネ=人気の前付けで市場が織込済)。そこで「隠れた前残り」= 前走差し/追込なのに
# 強コネ(市場が逃げを予想しない)にのみ加点し、価値(穴の逃げ)を取りにいく。
function ScoreConn($row){
  $s = ScoreNew $row
  $cl = ConnLead $row
  if($cl -ne $null -and ($row.prevStyle -eq '差し' -or $row.prevStyle -eq '追込')){
    if($cl -ge 0.25){$s+=1.5} elseif($cl -ge 0.18){$s+=0.8}
  }
  # 馬場係数: 不良は前残りが極端化 → 追込をさらに嫌う
  if($row.ba -eq '不良' -and $row.prevStyle -eq '追込'){$s-=0.5}
  return $s
}

# 検証期間のレース毎に本命(最高スコア)を選び回収率を集計
$test = $all | Where-Object { $_.date -ge $TestStart }
$byRace = $test | Group-Object { "$($_.date)_$($_.rno)" }

function Evaluate($scoreFn, $label){
  $bets=0; $win=0; $winPay=0.0; $plc=0; $plcPay=0.0
  foreach($g in $byRace){
    $scored = $g.Group | ForEach-Object { $_ | Add-Member -NotePropertyName _sc -NotePropertyValue (& $scoreFn $_) -Force -PassThru }
    $top = $scored | Sort-Object {[double]$_._sc} -Descending | Select-Object -First 1
    # 同点本命が複数なら最小馬番を選ぶ(決定的)
    $best = ($scored | Sort-Object @{e={[double]$_._sc};Descending=$true}, @{e={[int]$_.uma}} )[0]
    $bets++
    if([int]$best.chaku -eq 1){ $win++; $winPay+=[double]$best.winPay }
    if([int]$best.placed -eq 1){ $plc++; $plcPay+=[double]$best.placePay }
  }
  "{0,-26} 本命{1,4}レース  単勝[的中{2,5:P1} 回収{3,6:P1}]  複勝[的中{4,5:P1} 回収{5,6:P1}]" -f `
    $label,$bets,($win/$bets),($winPay/($bets*100)),($plc/$bets),($plcPay/($bets*100))
}

Write-Host ("`n■ 検証期間 {0}〜 の本命1点買い回収率(騎手率は学習期間のみで算出)" -f $TestStart)
Write-Host ("  対象レース数: {0}" -f $byRace.Count)
Evaluate { param($r) ScoreOld $r } '現行相当(脚質+騎手+持時計)'
Evaluate { param($r) ScoreNew $r } '改良(+同型不在+距離)'
Evaluate { param($r) ScoreConn $r } '改良+価値コネ(隠れ前残り)+馬場'
