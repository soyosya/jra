<#
.SYNOPSIS
  勝ち馬プロファイル(race-profile-screen.ps1 と同一ロジック)で過去レースを採点し、
  払戻金テーブルから単勝・複勝の払戻ベース回収率をバックテストします。

.DESCRIPTION
  オッズ/人気はDB未保存のため、払戻金(馬券=単勝/複勝, 組番=馬番, 金額=100円あたり払戻)を
  各出走馬に結合し「機械的に単勝/複勝を100円ずつ買った場合」の回収率を近似します。

  出力は3部:
    (1) 基準     … 対象レースの全頭を買った場合の単複回収(=控除後の期待値ライン)
    (2) スコア別 … プロファイル本線スコア(0〜4)ごとの 頭数/勝率/複勝率/単回収/複回収
    (3) サブ条件 … スコア4の中での 格下げ/休明け/決め脚 別の成績(年次分解つき)

  本線4条件(各1点) … 前走が当該場 / 前走が当該距離 / 前走3着以内 / 前走の脚質が逃げ・先行
  サブ条件 … 格下げ(前走の一着賞金>今回) / 休明け(前走から43日以上) / 決め脚(前走差し追込かつ上り3F3位内)

  接続文字列は 共通/appsettings.json の ConnectionStrings:DefaultConnection を読み込みます。

.PARAMETER From / To
  バックテスト対象の開催日範囲(yyyy-MM-dd)。既定 2024-01-01 〜 2026-06-14。

.PARAMETER Venue / Distance / Prize / CondLike
  照合条件。既定は 大井 / 1200 / 1000000 / '%一般 別定%'。

.NOTES
  ※サブ条件の部分集合は n=40〜60 と小さく、多重検定・年次偏りに注意。
    単年の高回収率は高配当一発や特定年への過学習であることが多い。年次分解を必ず確認すること。

.EXAMPLE
  .\oi-roi-backtest.ps1
  .\oi-roi-backtest.ps1 -Venue 大井 -Distance 1400 -Prize 1700000 -CondLike '%一般 別定%'
#>
[CmdletBinding()]
param(
    [string]$From = '2024-01-01',
    [string]$To   = '2026-06-14',
    [string]$Venue = '大井',
    [int]$Distance = 1200,
    [int]$Prize = 1000000,
    [string]$CondLike = '%一般 別定%'
)

$ErrorActionPreference = 'Stop'

$appsettings = Join-Path $PSScriptRoot '..\共通\appsettings.json'
if (-not (Test-Path $appsettings)) { throw "appsettings.json が見つかりません: $appsettings" }
$connStr = (Get-Content $appsettings -Raw -Encoding UTF8 | ConvertFrom-Json).ConnectionStrings.DefaultConnection
if ([string]::IsNullOrWhiteSpace($connStr)) { throw 'ConnectionStrings:DefaultConnection を取得できませんでした。' }

# 共通CTE: 対象レース→出走馬→前走→前走脚質→スコア→単複払戻 を1行/頭で算出
$cte = @"
WITH tgt AS (
  SELECT DISTINCT 開催日, レース番号 FROM レース情報
  WHERE 開催場所=@venue AND 距離=@dist AND 一着賞金=@prize AND 条件 LIKE @cond
    AND 開催日 BETWEEN @from AND @to),
ent AS (
  SELECT r.開催日,r.レース番号,r.馬番,r.馬名,kk.着順 今回着順
  FROM レース情報 r JOIN tgt t ON t.開催日=r.開催日 AND t.レース番号=r.レース番号
  LEFT JOIN 競走結果 kk ON kk.開催場所=@venue AND kk.開催日=r.開催日 AND kk.レース番号=r.レース番号 AND kk.馬番=r.馬番
  WHERE r.開催場所=@venue),
prev AS (
  SELECT e.開催日,e.レース番号,e.馬番,
    pr.開催日 p_date,pr.開催場所 p_venue,pr.レース番号 p_no,pr.馬番 p_uma,pr.距離 p_dist,pr.一着賞金 p_prize,
    ROW_NUMBER() OVER (PARTITION BY e.開催日,e.レース番号,e.馬番 ORDER BY pr.開催日 DESC,pr.レース番号 DESC) seq
  FROM ent e JOIN レース情報 pr ON pr.馬名=e.馬名 AND pr.開催日 < e.開催日),
prevraces AS (SELECT DISTINCT p_venue 開催場所,p_date 開催日,p_no レース番号 FROM prev WHERE seq=1),
kr AS (
  SELECT k.開催場所,k.開催日,k.レース番号,k.馬番,k.着順,
    COALESCE(NULLIF(k.一コーナー,0),NULLIF(k.二コーナー,0),NULLIF(k.三コーナー,0),NULLIF(k.四コーナー,0)) early_pos,
    COUNT(*) OVER(PARTITION BY k.開催場所,k.開催日,k.レース番号) 頭数,
    CASE WHEN k.上り3F>0 THEN RANK() OVER(PARTITION BY k.開催場所,k.開催日,k.レース番号 ORDER BY CASE WHEN k.上り3F>0 THEN k.上り3F ELSE 9999 END) END agari_rank
  FROM 競走結果 k JOIN prevraces prn ON prn.開催場所=k.開催場所 AND prn.開催日=k.開催日 AND prn.レース番号=k.レース番号),
scored AS (
  SELECT e.開催日,e.レース番号,e.馬番,e.馬名,e.今回着順,
   ( (CASE WHEN p.p_venue=@venue THEN 1 ELSE 0 END)+(CASE WHEN p.p_dist=@dist THEN 1 ELSE 0 END)
   + (CASE WHEN kr.着順<=3 THEN 1 ELSE 0 END)
   + (CASE WHEN kr.early_pos=1 OR (kr.頭数 IS NOT NULL AND kr.early_pos<=kr.頭数*0.33) THEN 1 ELSE 0 END) ) スコア,
   CASE WHEN p.p_prize>@prize THEN 1 ELSE 0 END 格下げ,
   CASE WHEN DATEDIFF(day,p.p_date,e.開催日)>=43 THEN 1 ELSE 0 END 休明け,
   CASE WHEN kr.agari_rank<=3 AND kr.early_pos>kr.頭数*0.33 AND kr.early_pos IS NOT NULL THEN 1 ELSE 0 END 決め脚,
   tan.金額 単払, fuk.金額 複払
  FROM ent e
  LEFT JOIN prev p ON p.開催日=e.開催日 AND p.レース番号=e.レース番号 AND p.馬番=e.馬番 AND p.seq=1
  LEFT JOIN kr ON kr.開催場所=p.p_venue AND kr.開催日=p.p_date AND kr.レース番号=p.p_no AND kr.馬番=p.p_uma
  LEFT JOIN 払戻金 tan ON tan.開催場所=@venue AND tan.開催日=e.開催日 AND tan.レース番号=e.レース番号 AND tan.馬券=N'単勝' AND LTRIM(RTRIM(tan.組番))=CAST(e.馬番 AS nvarchar)
  LEFT JOIN 払戻金 fuk ON fuk.開催場所=@venue AND fuk.開催日=e.開催日 AND fuk.レース番号=e.レース番号 AND fuk.馬券=N'複勝' AND LTRIM(RTRIM(fuk.組番))=CAST(e.馬番 AS nvarchar)
  WHERE e.今回着順 IS NOT NULL AND e.今回着順>0)
"@

function Invoke-Sql([string]$tail) {
    $conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
    $conn.Open()
    try {
        $cmd = $conn.CreateCommand(); $cmd.CommandTimeout = 180
        $cmd.CommandText = $cte + $tail
        [void]$cmd.Parameters.AddWithValue('@from', $From)
        [void]$cmd.Parameters.AddWithValue('@to', $To)
        [void]$cmd.Parameters.AddWithValue('@venue', $Venue)
        [void]$cmd.Parameters.AddWithValue('@dist', $Distance)
        [void]$cmd.Parameters.AddWithValue('@prize', $Prize)
        [void]$cmd.Parameters.AddWithValue('@cond', $CondLike)
        $r = $cmd.ExecuteReader()
        $rows = @()
        while ($r.Read()) {
            $o = [ordered]@{}
            for ($i = 0; $i -lt $r.FieldCount; $i++) { $o[$r.GetName($i)] = $r.GetValue($i) }
            $rows += [PSCustomObject]$o
        }
        $r.Close()
        return $rows
    } finally { $conn.Close() }
}

function Pct($num, $den) { if ($den -eq 0) { '   -  ' } else { '{0,6:P1}' -f ($num / $den) } }

Write-Host ("照合条件: {0}  {1}m  1着賞金{2:N0}円  条件LIKE '{3}'  期間 {4}〜{5}" -f $Venue, $Distance, $Prize, $CondLike, $From, $To)

# (1) 基準: 全頭買い
$base = Invoke-Sql @"
SELECT COUNT(*) 全頭, COUNT(DISTINCT CAST(開催日 AS nvarchar)+'_'+CAST(レース番号 AS nvarchar)) レース数,
  SUM(COALESCE(単払,0)) 単, SUM(COALESCE(複払,0)) 複 FROM scored
"@
$b = $base[0]; $bn = [int]$b.全頭
if ($bn -eq 0) { Write-Host '→ 該当レースが見つかりません(出馬表/競走結果/払戻金が未取得の可能性)。'; return }
Write-Host ("`n【1】基準(全頭買い)  対象 {0}レース / 延べ {1}頭" -f $b.レース数, $bn)
Write-Host ("    単回収 {0}   複回収 {1}   ← これが控除後の期待値ライン" -f (Pct ([double]$b.単) (100*$bn)), (Pct ([double]$b.複) (100*$bn)))

# (2) スコア別
$bg = Invoke-Sql @"
SELECT スコア, COUNT(*) 頭, SUM(CASE WHEN 今回着順=1 THEN 1 ELSE 0 END) 勝,
  SUM(CASE WHEN 今回着順<=3 THEN 1 ELSE 0 END) 複圏, SUM(COALESCE(単払,0)) 単, SUM(COALESCE(複払,0)) 複
FROM scored GROUP BY スコア ORDER BY スコア DESC
"@
Write-Host "`n【2】スコア別  (スコア=本線4条件の合致数)"
Write-Host 'スコア  頭数   勝率    複勝率   単回収   複回収'
foreach ($x in $bg) {
    $n = [int]$x.頭
    Write-Host ("{0,3}   {1,5}  {2}  {3}  {4}  {5}" -f $x.スコア, $n, (Pct ([int]$x.勝) $n), (Pct ([int]$x.複圏) $n), (Pct ([double]$x.単) (100*$n)), (Pct ([double]$x.複) (100*$n)))
}

# (3) スコア4のサブ条件別(年次分解つき)
$sub = Invoke-Sql @"
SELECT 区分, 年, COUNT(*) 頭, SUM(CASE WHEN 今回着順=1 THEN 1 ELSE 0 END) 勝, SUM(COALESCE(単払,0)) 単, MAX(単払) 最高単 FROM (
  SELECT YEAR(開催日) 年, 今回着順, 単払, N'格下げ' 区分 FROM scored WHERE スコア=4 AND 格下げ=1
  UNION ALL SELECT YEAR(開催日), 今回着順, 単払, N'休明け' FROM scored WHERE スコア=4 AND 休明け=1
  UNION ALL SELECT YEAR(開催日), 今回着順, 単払, N'決め脚' FROM scored WHERE スコア=4 AND 決め脚=1
  UNION ALL SELECT YEAR(開催日), 今回着順, 単払, N'格下げ(休明け除く)' FROM scored WHERE スコア=4 AND 格下げ=1 AND 休明け=0
) t GROUP BY 区分, 年 ORDER BY 区分, 年
"@
Write-Host "`n【3】スコア4のサブ条件別 × 年次  (※n小・多重検定に注意。単年の高回収は過学習を疑う)"
Write-Host '区分                  年    頭数 勝  単回収   最高単勝'
foreach ($x in $sub) {
    $n = [int]$x.頭
    Write-Host ("{0,-20} {1}  {2,4} {3,3}  {4}   {5}" -f $x.区分, $x.年, $n, $x.勝, (Pct ([double]$x.単) (100*$n)), $x.最高単)
}
