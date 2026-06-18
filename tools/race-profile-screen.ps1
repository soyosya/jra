<#
.SYNOPSIS
  指定日・指定条件のレースの出走馬を、勝ち馬プロファイル(前走の傾向)で採点して一覧します。

.DESCRIPTION
  既定は「大井・1200m・一般別定・1着賞金100万」。2024年以降の同条件の勝ち馬分析から導いた
  本線4条件を各馬の前走で判定し、スコア(満点4)とサブ条件フラグを付けて出力します。

  本線4条件(各1点):
    1. 前走が大井
    2. 前走が1200m
    3. 前走3着以内
    4. 前走の脚質が逃げ・先行(コーナー通過順を頭数で相対化)
  サブ条件フラグ:
    決め脚 … 前走が差し/追込 かつ 前走上がり3F順位が3位以内(後方からでも買える型)
    格下げ … 前走の1着賞金が今回より高い(上のクラスからの降級)
    休明け … 前走からの間隔が43日以上(中6週超)

  接続文字列は 共通/appsettings.json の ConnectionStrings:DefaultConnection を読み込みます。

.PARAMETER Date
  対象開催日(yyyy-MM-dd)。既定は今日。

.PARAMETER Venue / Distance / Prize / CondLike
  照合する条件。既定は 大井 / 1200 / 1000000 / '%一般 別定%'。別条件のプロファイル照合にも流用できます。

.EXAMPLE
  .\race-profile-screen.ps1
  .\race-profile-screen.ps1 -Date 2026-06-26
  .\race-profile-screen.ps1 -Date 2026-07-01 -Venue 高知 -Distance 1300 -Prize 600000 -CondLike '%一般 定量%'
#>
[CmdletBinding()]
param(
    [string]$Date = (Get-Date).ToString('yyyy-MM-dd'),
    [string]$Venue = '大井',
    [int]$Distance = 1200,
    [int]$Prize = 1000000,
    [string]$CondLike = '%一般 別定%',
    # 脚質判定を「四角位置」基準にする(既定は序盤位置)。
    # 大井の検証では四角ベースが strictly better(同精度で該当馬+9%、単回収+3pt)。まくり成功馬を取りこぼさない。
    [switch]$LateCorner
)

$ErrorActionPreference = 'Stop'

# 脚質分類に使う通過順位置: 序盤=最初の非ゼロコーナー / 四角=最後の非ゼロコーナー(C4→C3→…にフォールバック)
$posExpr = if ($LateCorner) {
    'COALESCE(NULLIF(k.四コーナー,0),NULLIF(k.三コーナー,0),NULLIF(k.二コーナー,0),NULLIF(k.一コーナー,0))'
} else {
    'COALESCE(NULLIF(k.一コーナー,0),NULLIF(k.二コーナー,0),NULLIF(k.三コーナー,0),NULLIF(k.四コーナー,0))'
}

# --- 接続文字列を appsettings.json から取得 ---
$appsettings = Join-Path $PSScriptRoot '..\共通\appsettings.json'
if (-not (Test-Path $appsettings)) {
    throw "appsettings.json が見つかりません: $appsettings"
}
$connStr = (Get-Content $appsettings -Raw -Encoding UTF8 | ConvertFrom-Json).ConnectionStrings.DefaultConnection
if ([string]::IsNullOrWhiteSpace($connStr)) {
    throw 'ConnectionStrings:DefaultConnection を取得できませんでした。'
}

$sql = @"
WITH tgt AS (
  SELECT DISTINCT レース番号 FROM レース情報
  WHERE 開催日=@date AND 開催場所=@venue AND 距離=@dist AND 一着賞金=@prize AND 条件 LIKE @cond
),
ent AS (
  SELECT r.レース番号, r.馬番, r.馬名, r.馬体重 今走体重, kk.着順 AS 今回着順
  FROM レース情報 r JOIN tgt t ON t.レース番号=r.レース番号
  LEFT JOIN 競走結果 kk ON kk.開催場所=@venue AND kk.開催日=@date AND kk.レース番号=r.レース番号 AND kk.馬番=r.馬番
  WHERE r.開催場所=@venue AND r.開催日=@date
),
-- 前々走の馬体重(馬体重がある過去走のうち、今回より前で2番目に新しい走)。今走-前々走で2走分の増減を見る。
bw AS (
  SELECT e.レース番号, e.馬番, pr.馬体重 bweight,
    ROW_NUMBER() OVER (PARTITION BY e.レース番号, e.馬番 ORDER BY pr.開催日 DESC, pr.レース番号 DESC) rn
  FROM ent e JOIN レース情報 pr ON pr.馬名=e.馬名 AND pr.開催日 < @date AND pr.馬体重 > 0
),
prev AS (
  SELECT e.レース番号, e.馬番,
    pr.開催日 p_date, pr.開催場所 p_venue, pr.レース番号 p_no, pr.馬番 p_uma, pr.距離 p_dist, pr.一着賞金 p_prize,
    ROW_NUMBER() OVER (PARTITION BY e.レース番号, e.馬番 ORDER BY pr.開催日 DESC, pr.レース番号 DESC) seq
  FROM ent e JOIN レース情報 pr ON pr.馬名=e.馬名 AND pr.開催日 < @date
),
prevraces AS (SELECT DISTINCT p_venue 開催場所, p_date 開催日, p_no レース番号 FROM prev WHERE seq=1),
kr AS (
  SELECT k.開催場所, k.開催日, k.レース番号, k.馬番, k.着順,
    COALESCE(NULLIF(k.一コーナー,0),NULLIF(k.二コーナー,0),NULLIF(k.三コーナー,0),NULLIF(k.四コーナー,0)) early_pos,
    $posExpr pos_use,
    COUNT(*) OVER(PARTITION BY k.開催場所,k.開催日,k.レース番号) 頭数,
    CASE WHEN k.上り3F>0 THEN RANK() OVER(PARTITION BY k.開催場所,k.開催日,k.レース番号 ORDER BY CASE WHEN k.上り3F>0 THEN k.上り3F ELSE 9999 END) END agari_rank
  FROM 競走結果 k JOIN prevraces prn ON prn.開催場所=k.開催場所 AND prn.開催日=k.開催日 AND prn.レース番号=k.レース番号
)
SELECT e.レース番号, e.馬番, e.馬名, e.今回着順,
  p.p_venue 前走場所, p.p_dist 前走距離, kr.着順 前走着順,
  CASE WHEN kr.pos_use IS NULL OR kr.頭数 IS NULL THEN N'?'
       WHEN kr.pos_use=1 THEN N'逃げ'
       WHEN kr.pos_use<=kr.頭数*0.33 THEN N'先行'
       WHEN kr.pos_use<=kr.頭数*0.66 THEN N'差し'
       ELSE N'追込' END 前走脚質,
  kr.agari_rank 前走上り順,
  DATEDIFF(day, p.p_date, @date) 間隔,
  ( (CASE WHEN p.p_venue=@venue THEN 1 ELSE 0 END)
  + (CASE WHEN p.p_dist=@dist THEN 1 ELSE 0 END)
  + (CASE WHEN kr.着順<=3 THEN 1 ELSE 0 END)
  + (CASE WHEN kr.pos_use=1 OR (kr.頭数 IS NOT NULL AND kr.pos_use<=kr.頭数*0.33) THEN 1 ELSE 0 END) ) スコア,
  CASE WHEN kr.agari_rank<=3 AND kr.early_pos>kr.頭数*0.33 AND kr.early_pos IS NOT NULL THEN N'Y' ELSE N'' END 決め脚,
  CASE WHEN p.p_prize>@prize THEN N'Y' ELSE N'' END 格下げ,
  CASE WHEN DATEDIFF(day, p.p_date, @date)>=43 THEN N'Y' ELSE N'' END 休明け,
  -- 妙味: 今走が前々走から-10kg以下。検証で勝率・回収率が高いのは高知・佐賀・川崎のみ→その3場でのみ点灯。
  CASE WHEN @venue IN (N'高知',N'佐賀',N'川崎') AND e.今走体重>0 AND bw2.bweight>0 AND (e.今走体重 - bw2.bweight) <= -10 THEN N'Y' ELSE N'' END 妙味減
FROM ent e
LEFT JOIN prev p ON p.レース番号=e.レース番号 AND p.馬番=e.馬番 AND p.seq=1
LEFT JOIN kr ON kr.開催場所=p.p_venue AND kr.開催日=p.p_date AND kr.レース番号=p.p_no AND kr.馬番=p.p_uma
LEFT JOIN (SELECT レース番号, 馬番, bweight FROM bw WHERE rn=2) bw2 ON bw2.レース番号=e.レース番号 AND bw2.馬番=e.馬番
ORDER BY e.レース番号, スコア DESC, e.今回着順
"@

$conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
$conn.Open()
try {
    $cmd = $conn.CreateCommand()
    $cmd.CommandTimeout = 120
    $cmd.CommandText = $sql
    [void]$cmd.Parameters.AddWithValue('@date', $Date)
    [void]$cmd.Parameters.AddWithValue('@venue', $Venue)
    [void]$cmd.Parameters.AddWithValue('@dist', $Distance)
    [void]$cmd.Parameters.AddWithValue('@prize', $Prize)
    [void]$cmd.Parameters.AddWithValue('@cond', $CondLike)

    $r = $cmd.ExecuteReader()
    $rows = @()
    while ($r.Read()) {
        $rows += [PSCustomObject]@{
            R       = $r['レース番号']
            馬番    = $r['馬番']
            馬名    = $r['馬名']
            着      = if ($r['今回着順'] -is [DBNull]) { '' } else { $r['今回着順'] }
            前走場  = if ($r['前走場所'] -is [DBNull]) { '-' } else { $r['前走場所'] }
            前距    = if ($r['前走距離'] -is [DBNull]) { '' } else { $r['前走距離'] }
            前着    = if ($r['前走着順'] -is [DBNull]) { '' } else { $r['前走着順'] }
            脚質    = $r['前走脚質']
            上り    = if ($r['前走上り順'] -is [DBNull]) { '' } else { $r['前走上り順'] }
            間隔    = if ($r['間隔'] -is [DBNull]) { '' } else { $r['間隔'] }
            スコア  = $r['スコア']
            決め脚  = $r['決め脚']
            格下げ  = $r['格下げ']
            休明け  = $r['休明け']
            妙味減  = $r['妙味減']
        }
    }
    $r.Close()

    Write-Host ("照合条件: {0}  {1}  {2}m  1着賞金{3:N0}円  条件LIKE '{4}'" -f $Date, $Venue, $Distance, $Prize, $CondLike)
    if ($rows.Count -eq 0) {
        Write-Host '→ 該当レースが見つからないか、出馬表(レース情報)が未取得です。'
        Write-Host '  (出馬表が未取得の場合は ConsoleApp の fetch-range 等で当該日を取得してから再実行してください)'
        return
    }

    foreach ($g in ($rows | Group-Object R)) {
        Write-Host ("`n=== {0}R ===" -f $g.Name)
        $g.Group | Format-Table 着,馬番,馬名,前走場,前距,前着,脚質,上り,間隔,スコア,決め脚,格下げ,休明け,妙味減 -AutoSize | Out-String -Width 200 | Write-Host
        $best = ($g.Group | Sort-Object スコア -Descending | Select-Object -First 1).スコア
        $honmei = $g.Group | Where-Object { $_.スコア -eq 4 } | ForEach-Object { $_.馬名 }
        $kimete = $g.Group | Where-Object { $_.決め脚 -eq 'Y' } | ForEach-Object { $_.馬名 }
        if ($honmei) { Write-Host ('  本線(スコア4): ' + ($honmei -join ', ')) }
        if ($kimete) { Write-Host ('  サブ(決め脚型): ' + ($kimete -join ', ')) }
        if (-not $honmei) { Write-Host ('  本線該当なし(最高スコア {0})' -f $best) }
    }
}
finally {
    $conn.Close()
}
