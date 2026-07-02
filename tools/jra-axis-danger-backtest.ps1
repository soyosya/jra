<#
.SYNOPSIS
  軸馬の危険フィルタ検証: 前走で1着と2秒以上の着差で負けている軸(格上挑戦の前走は除く)の成績をバックテスト。
.DESCRIPTION
  軸=1番人気 / コンピ1位 / モデル本命(予測p_win最上位) の3定義。各馬の前走(直近の過去走, MaxGapDays日内)を取得:
    前走着差 = 競走結果.一着馬着差タイム。クラスは レース情報.条件 から序列化
    (未勝利/新馬0 <1勝1 <2勝2 <3勝3 <オープン4)。※一着賞金は2023未取込のため条件で判定。
  危険(DANGER) = 前走着差 ≥ MaxBeat秒 かつ 前走が格上挑戦でない(前走クラス ≤ 今走クラス)。
  比較群(前走あり馬): 全体 / DANGER / 参考:格上挑戦の大敗 / 通常(2秒未満負け)。指標 勝率/複勝率/単回収。
.PARAMETER MaxBeat 大敗の着差閾値(秒)。既定2.0  .PARAMETER MaxGapDays 前走最大日数。既定365
#>
[CmdletBinding()] param([double]$MaxBeat=2.0,[int]$MaxGapDays=365)
$ErrorActionPreference='Stop'
$conn=New-Object System.Data.SqlClient.SqlConnection((Get-Content 'C:\jra\共通\appsettings.json' -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection)
$conn.Open()
$build=@"
IF OBJECT_ID('tempdb..#a') IS NOT NULL DROP TABLE #a;
WITH base AS (
  SELECT k.開催場所 v,k.開催日 d,k.レース番号 r,k.馬番 no,k.馬名 h, k.一着馬着差タイム mgn,
    CASE WHEN ri.条件 LIKE N'%3勝クラス%' THEN 3 WHEN ri.条件 LIKE N'%2勝クラス%' THEN 2
         WHEN ri.条件 LIKE N'%1勝クラス%' THEN 1 WHEN ri.条件 LIKE N'%オープン%' THEN 4
         WHEN ri.条件 LIKE N'%未勝利%' OR ri.条件 LIKE N'%新馬%' THEN 0 ELSE NULL END cls
  FROM 競走結果 k JOIN レース情報 ri ON ri.開催場所=k.開催場所 AND ri.開催日=k.開催日 AND ri.レース番号=k.レース番号 AND ri.馬番=k.馬番
  WHERE k.着順>0 AND ri.コース種別 IN (N'芝',N'ダ')
),
seq AS (
  SELECT v,d,r,no,h,cls,
    LAG(mgn,1) OVER(PARTITION BY h ORDER BY d,r) prev_mgn,
    LAG(cls,1) OVER(PARTITION BY h ORDER BY d,r) prev_cls,
    LAG(d,1)   OVER(PARTITION BY h ORDER BY d,r) pd1
  FROM base
),
mdl AS (
  SELECT f.開催場所 v,f.開催日 d,f.レース番号 r,f.馬番 no,f.win,f.plc,f.tan_odds tan,f.ninki,f.compi_rank,
    ROW_NUMBER() OVER(PARTITION BY f.開催場所,f.開催日,f.レース番号 ORDER BY p.p_win DESC) mrank
  FROM 特徴量 f LEFT JOIN 予測 p ON p.開催場所=f.開催場所 AND p.開催日=f.開催日 AND p.レース番号=f.レース番号 AND p.馬番=f.馬番
  WHERE YEAR(f.開催日)=2023 AND f.tan_odds>0
)
SELECT m.win,m.plc,m.tan,m.ninki,m.compi_rank,m.mrank,
  CASE WHEN s.prev_mgn IS NOT NULL AND DATEDIFF(day,s.pd1,s.d)<=$MaxGapDays THEN 1 ELSE 0 END hasprev,
  s.prev_mgn, s.prev_cls, s.cls today_cls
INTO #a
FROM mdl m JOIN seq s ON s.v=m.v AND s.d=m.d AND s.r=m.r AND s.no=m.no;
"@
$c=$conn.CreateCommand();$c.CommandTimeout=300;$c.CommandText=$build;[void]$c.ExecuteNonQuery()

function Agg([string]$where){
  $sql=@"
SELECT COUNT(*) n,
  CAST(100.0*SUM(CASE WHEN win=1 THEN 1.0 ELSE 0 END)/NULLIF(COUNT(*),0) AS decimal(5,1)) 勝率,
  CAST(100.0*SUM(CASE WHEN plc=1 THEN 1.0 ELSE 0 END)/NULLIF(COUNT(*),0) AS decimal(5,1)) 複勝率,
  CAST(100.0*SUM(CASE WHEN win=1 AND tan IS NOT NULL THEN tan ELSE 0 END)/NULLIF(SUM(CASE WHEN tan IS NOT NULL THEN 1 ELSE 0 END),0) AS decimal(6,1)) 単回収
FROM #a WHERE $where
"@
  $cmd=$conn.CreateCommand();$cmd.CommandText=$sql;$r=$cmd.ExecuteReader();$r.Read()|Out-Null
  $o=[ordered]@{}; for($i=0;$i -lt $r.FieldCount;$i++){$o[$r.GetName($i)]=$r.GetValue($i)}; $r.Close(); [pscustomobject]$o
}
function Row($lbl,$where){ $x=Agg $where; "{0,-28}{1,7}{2,8}{3,8}{4,9}" -f $lbl,$x.n,$x.勝率,$x.複勝率,$x.単回収 }

$DANGER = "hasprev=1 AND prev_mgn>=$MaxBeat AND prev_cls IS NOT NULL AND today_cls IS NOT NULL AND prev_cls<=today_cls"
$EXCUSE = "hasprev=1 AND prev_mgn>=$MaxBeat AND prev_cls>today_cls"
$NORMAL = "hasprev=1 AND prev_mgn<$MaxBeat"

"════ 軸馬の危険フィルタ: 前走で{0}秒以上負け(格上挑戦=前走クラス>今走クラス は除外) ════" -f $MaxBeat
foreach($axis in @(@{n='1番人気';w='ninki=1'},@{n='コンピ1位';w='compi_rank=1'},@{n='モデル本命';w='mrank=1'})){
  "`n■ 軸={0}" -f $axis.n
  "{0,-28}{1,7}{2,8}{3,8}{4,9}" -f '区分','n','勝率%','複勝%','単回収%'
  Row '全体(前走あり)' "$($axis.w) AND hasprev=1"
  Row "★危険:前走≥${MaxBeat}秒負け・非格上" "$($axis.w) AND $DANGER"
  Row "  参考:前走≥${MaxBeat}秒負け・格上挑戦" "$($axis.w) AND $EXCUSE"
  Row "  通常:前走<${MaxBeat}秒負け" "$($axis.w) AND $NORMAL"
}
$conn.Close()
