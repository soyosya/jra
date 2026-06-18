<#
.SYNOPSIS
  高知競馬の総合スコアリング。指定日の各レースの出走馬を「脚質×騎手×持ち時計×継続」で採点します。

.DESCRIPTION
  2024年以降の高知データ分析(前残りバイアス・騎手の前付け力・距離別基準タイム)に基づく採点。
  各馬を以下で加点し、レースごとにスコア順で一覧します。

    脚質(前走)   : 逃げ +2 / 先行 +1   … 高知は前残り超有利
    継続         : 前走も高知 +1        … 現級リピーター重視
    騎手の前付力 : 前々率(逃げ+先行)>=40% +2 / >=33% +1
    持ち時計     : 高知・同距離の自己ベストが その距離/クラスの基準より
                   1.0秒以上速い +2 / 基準以内 +1

  基準タイム・騎手前々率は、対象日より前の高知2024年以降データから動的に算出します。
  接続文字列は 共通/appsettings.json から読み込みます。

.PARAMETER Date
  対象開催日(yyyy-MM-dd)。既定は今日。

.EXAMPLE
  .\kochi-score.ps1 -Date 2026-06-26
#>
[CmdletBinding()]
param(
    [string]$Date = (Get-Date).ToString('yyyy-MM-dd')
)
$ErrorActionPreference = 'Stop'

$appsettings = Join-Path $PSScriptRoot '..\共通\appsettings.json'
if (-not (Test-Path $appsettings)) { throw "appsettings.json が見つかりません: $appsettings" }
$connStr = (Get-Content $appsettings -Raw -Encoding UTF8 | ConvertFrom-Json).ConnectionStrings.DefaultConnection
if ([string]::IsNullOrWhiteSpace($connStr)) { throw 'DefaultConnection を取得できませんでした。' }

$sql = @"
DECLARE @venue nvarchar(10)=N'高知';

-- 基準タイム(距離×クラス, 勝ち馬平均) : 対象日より前の2024+
IF OBJECT_ID('tempdb..#std') IS NOT NULL DROP TABLE #std;
SELECT r.距離, r.一着賞金, AVG(k.走破時計) std_time
INTO #std
FROM 競走結果 k JOIN レース情報 r ON r.開催場所=@venue AND r.開催日=k.開催日 AND r.レース番号=k.レース番号 AND r.馬番=k.馬番
WHERE k.開催場所=@venue AND k.着順=1 AND k.走破時計>0 AND k.開催日>='2024-01-01' AND k.開催日<@date
GROUP BY r.距離, r.一着賞金;

-- 騎手の前々率(逃げ+先行率) : 高知2024+, 対象日より前
IF OBJECT_ID('tempdb..#jock') IS NOT NULL DROP TABLE #jock;
WITH rides AS (
  SELECT r.騎手,
    CASE WHEN ce.early_pos=1 OR (ce.頭数 IS NOT NULL AND ce.early_pos<=ce.頭数*0.33) THEN 1 ELSE 0 END frontflag
  FROM レース情報 r
  JOIN 競走結果 k ON k.開催場所=@venue AND k.開催日=r.開催日 AND k.レース番号=r.レース番号 AND k.馬番=r.馬番
  CROSS APPLY (SELECT COALESCE(NULLIF(k.一コーナー,0),NULLIF(k.二コーナー,0),NULLIF(k.三コーナー,0),NULLIF(k.四コーナー,0)) early_pos,
    (SELECT COUNT(*) FROM 競走結果 k2 WHERE k2.開催場所=@venue AND k2.開催日=k.開催日 AND k2.レース番号=k.レース番号 AND k2.着順>0) 頭数) ce
  WHERE r.開催場所=@venue AND r.開催日>='2024-01-01' AND r.開催日<@date AND k.着順>0
)
SELECT 騎手, COUNT(*) n, 100.0*SUM(frontflag)/COUNT(*) front_rate
INTO #jock FROM rides GROUP BY 騎手;

-- 距離別の妥当な走破時計の下限(過去勝ち時計の最速×0.96)。破損データ(極端に小さい値)を除外するため。
IF OBJECT_ID('tempdb..#floor') IS NOT NULL DROP TABLE #floor;
SELECT r.距離, 0.96*MIN(k.走破時計) floor_time
INTO #floor
FROM 競走結果 k JOIN レース情報 r ON r.開催場所=@venue AND r.開催日=k.開催日 AND r.レース番号=k.レース番号 AND r.馬番=k.馬番
WHERE k.開催場所=@venue AND k.着順=1 AND k.走破時計>0 AND k.開催日>='2024-01-01' AND k.開催日<@date
GROUP BY r.距離;

-- 出走馬
IF OBJECT_ID('tempdb..#ent') IS NOT NULL DROP TABLE #ent;
SELECT r.レース番号, r.馬番, r.馬名, r.騎手, r.距離, r.一着賞金, kk.着順 今回着順
INTO #ent
FROM レース情報 r
LEFT JOIN 競走結果 kk ON kk.開催場所=@venue AND kk.開催日=@date AND kk.レース番号=r.レース番号 AND kk.馬番=r.馬番
WHERE r.開催場所=@venue AND r.開催日=@date;

-- 前走(直近1走)
IF OBJECT_ID('tempdb..#prev') IS NOT NULL DROP TABLE #prev;
WITH p AS (
  SELECT e.レース番号, e.馬番, pr.開催日 p_date, pr.開催場所 p_venue, pr.レース番号 p_no, pr.馬番 p_uma,
    ROW_NUMBER() OVER(PARTITION BY e.レース番号,e.馬番 ORDER BY pr.開催日 DESC, pr.レース番号 DESC) seq
  FROM #ent e JOIN レース情報 pr ON pr.馬名=e.馬名 AND pr.開催日<@date
)
SELECT レース番号,馬番,p_date,p_venue,p_no,p_uma INTO #prev FROM p WHERE seq=1;

SELECT
  e.レース番号, e.馬番, e.馬名, e.騎手, e.距離, e.今回着順,
  pv.p_venue 前走場所,
  pk.着順 前走着順,
  脚質 = CASE WHEN pkc.early_pos IS NULL THEN N'?' WHEN pkc.early_pos=1 THEN N'逃げ' WHEN pkc.early_pos<=pkc.頭数*0.33 THEN N'先行' WHEN pkc.early_pos<=pkc.頭数*0.66 THEN N'差し' ELSE N'追込' END,
  j.front_rate 騎手前々率,
  bt.bt 自己ベスト,
  st.std_time 基準,
  スコア =
      (CASE WHEN pkc.early_pos=1 THEN 2 WHEN pkc.early_pos<=pkc.頭数*0.33 THEN 1 ELSE 0 END)
    + (CASE WHEN pv.p_venue=@venue THEN 1 ELSE 0 END)
    + (CASE WHEN j.front_rate>=40 THEN 2 WHEN j.front_rate>=33 THEN 1 ELSE 0 END)
    + (CASE WHEN bt.bt IS NOT NULL AND st.std_time IS NOT NULL AND bt.bt<=st.std_time-1.0 THEN 2
            WHEN bt.bt IS NOT NULL AND st.std_time IS NOT NULL AND bt.bt<=st.std_time THEN 1 ELSE 0 END)
FROM #ent e
LEFT JOIN #prev pv ON pv.レース番号=e.レース番号 AND pv.馬番=e.馬番
LEFT JOIN 競走結果 pk ON pk.開催場所=pv.p_venue AND pk.開催日=pv.p_date AND pk.レース番号=pv.p_no AND pk.馬番=pv.p_uma
OUTER APPLY (SELECT COALESCE(NULLIF(pk.一コーナー,0),NULLIF(pk.二コーナー,0),NULLIF(pk.三コーナー,0),NULLIF(pk.四コーナー,0)) early_pos,
   (SELECT COUNT(*) FROM 競走結果 k2 WHERE k2.開催場所=pv.p_venue AND k2.開催日=pv.p_date AND k2.レース番号=pv.p_no AND k2.着順>0) 頭数) pkc
LEFT JOIN #jock j ON j.騎手=e.騎手
LEFT JOIN #std st ON st.距離=e.距離 AND st.一着賞金=e.一着賞金
OUTER APPLY (SELECT MIN(k3.走破時計) bt FROM 競走結果 k3 JOIN レース情報 r3 ON r3.開催場所=@venue AND r3.開催日=k3.開催日 AND r3.レース番号=k3.レース番号 AND r3.馬番=k3.馬番
   LEFT JOIN #floor fl ON fl.距離=r3.距離
   WHERE r3.馬名=e.馬名 AND r3.距離=e.距離 AND k3.走破時計>0 AND (fl.floor_time IS NULL OR k3.走破時計>=fl.floor_time)
     AND k3.開催日<@date AND k3.開催日>=DATEADD(day,-365,@date)) bt
ORDER BY e.レース番号, スコア DESC, e.今回着順;
"@

$conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
$conn.Open()
try {
    $cmd = $conn.CreateCommand(); $cmd.CommandTimeout = 180; $cmd.CommandText = $sql
    [void]$cmd.Parameters.AddWithValue('@date', $Date)
    $r = $cmd.ExecuteReader()
    $rows = @()
    while ($r.Read()) {
        $rows += [PSCustomObject]@{
            R      = $r['レース番号']; 馬番 = $r['馬番']; 馬名 = $r['馬名']; 騎手 = $r['騎手']
            着     = if ($r['今回着順'] -is [DBNull]) { '' } else { $r['今回着順'] }
            前走場 = if ($r['前走場所'] -is [DBNull]) { '-' } else { $r['前走場所'] }
            前着   = if ($r['前走着順'] -is [DBNull]) { '' } else { $r['前走着順'] }
            脚質   = $r['脚質']
            騎手前 = if ($r['騎手前々率'] -is [DBNull]) { '' } else { [math]::Round([double]$r['騎手前々率'],0) }
            自己ベ = if ($r['自己ベスト'] -is [DBNull]) { '' } else { [math]::Round([double]$r['自己ベスト'],1) }
            基準   = if ($r['基準'] -is [DBNull]) { '' } else { [math]::Round([double]$r['基準'],1) }
            スコア = $r['スコア']
        }
    }
    $r.Close()
    Write-Host ("高知 総合スコアリング  対象日: {0}" -f $Date)
    if ($rows.Count -eq 0) {
        Write-Host '→ 該当レースなし、または出馬表(レース情報)が未取得です。fetch-rangeで当該日を取得してください。'
        return
    }
    foreach ($g in ($rows | Group-Object R)) {
        Write-Host ("`n=== {0}R ===" -f $g.Name)
        $g.Group | Format-Table 着,馬番,馬名,騎手,前走場,前着,脚質,騎手前,自己ベ,基準,スコア -AutoSize | Out-String -Width 200 | Write-Host
        $top = ($g.Group | Sort-Object スコア -Descending | Select-Object -First 1).スコア
        $picks = $g.Group | Where-Object { $_.スコア -eq $top } | ForEach-Object { '{0}({1})' -f $_.馬名,$_.馬番 }
        Write-Host ('  最高スコア{0}: {1}' -f $top, ($picks -join ', '))
    }
}
finally { $conn.Close() }
