<#
.SYNOPSIS
  コンピ指数の「前々走→前走→今走」の変化パターンと今走の馬券圏内(着順≤3)の関係を調査。
.DESCRIPTION
  各馬のコンピ指数を時系列LAGで p2(前々走)/p1(前走)/idx(今走) として取得。
    d1 = idx-p1 (直近の変化), d2 = p1-p2 (その前の変化)。閾値Tで 上昇(>=T)/横ばい(|.|<T)/下降(<=-T)。
  今走に結果(競走結果.着順)がある馬で、パターン別に 勝率/複勝率/単回収 を集計。基準と比較。
  ※コンピ指数は各レース内の位置づけのため、格上挑戦等で場が強くなると指数が下がる交絡に注意。
  前走は MaxGapDays 日以内に限定。結果は時計のある年に依存(実質2023中心)。
.PARAMETER T 上昇/下降の閾値(指数ポイント)。既定3。  .PARAMETER MaxGapDays 前走最大日数。既定120。
#>
[CmdletBinding()] param([int]$T=3,[int]$MaxGapDays=120)
$ErrorActionPreference='Stop'
$conn=New-Object System.Data.SqlClient.SqlConnection((Get-Content 'C:\jra\共通\appsettings.json' -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection)
$conn.Open()
$build=@"
IF OBJECT_ID('tempdb..#t') IS NOT NULL DROP TABLE #t;
WITH base AS (
  SELECT 開催場所 v,開催日 d,レース番号 r,馬名 h,CAST(指数 AS int) idx,指数順位 rk
  FROM コンピ指数 WHERE 指数 IS NOT NULL
),
seq AS (
  SELECT v,d,r,h,idx,rk,
    LAG(idx,1) OVER(PARTITION BY h ORDER BY d,r) p1,
    LAG(idx,2) OVER(PARTITION BY h ORDER BY d,r) p2,
    LAG(d,1)   OVER(PARTITION BY h ORDER BY d,r) pd1
  FROM base
)
SELECT s.v,s.d,s.r,s.h,s.idx,s.rk,s.p1,s.p2,(s.idx-s.p1) d1,(s.p1-s.p2) d2,
  k.着順 fin, o.tan
INTO #t
FROM seq s
JOIN 競走結果 k ON k.開催場所=s.v AND k.開催日=s.d AND k.レース番号=s.r AND k.馬名=s.h
OUTER APPLY (SELECT TOP 1 単勝オッズ tan FROM リアルタイムオッズ ro WHERE ro.開催場所=s.v AND ro.開催日=s.d AND ro.レース番号=s.r AND ro.馬名=s.h ORDER BY ro.日時 DESC) o
WHERE s.p1 IS NOT NULL AND s.p2 IS NOT NULL AND k.着順>0 AND DATEDIFF(day,s.pd1,s.d)<=$MaxGapDays;
"@
$c=$conn.CreateCommand();$c.CommandTimeout=300;$c.CommandText=$build;[void]$c.ExecuteNonQuery()

function Agg([string]$where,[string]$groupcol){
  $sel= if($groupcol){"$groupcol grp"}else{"N'-' grp"}; $grp= if($groupcol){"GROUP BY $groupcol"}else{""}
  $sql=@"
SELECT $sel, COUNT(*) n,
  CAST(100.0*SUM(CASE WHEN fin=1 THEN 1.0 ELSE 0 END)/COUNT(*) AS decimal(5,1)) 勝率,
  CAST(100.0*SUM(CASE WHEN fin<=3 THEN 1.0 ELSE 0 END)/COUNT(*) AS decimal(5,1)) 複勝率,
  CAST(100.0*SUM(CASE WHEN fin=1 AND tan IS NOT NULL THEN tan ELSE 0 END)/NULLIF(SUM(CASE WHEN tan IS NOT NULL THEN 1 ELSE 0 END),0) AS decimal(6,1)) 単回収
FROM #t WHERE $where $grp ORDER BY $(if($groupcol){'MIN(sortk)'}else{'1'})
"@
  # ORDER用 sortk を持たせるため、グループSQLは別構築
  if($groupcol){ $sql=$sql -replace 'MIN\(sortk\)','grp' }
  $cmd=$conn.CreateCommand();$cmd.CommandText=$sql;$r=$cmd.ExecuteReader()
  $o=@();while($r.Read()){$row=[ordered]@{};for($i=0;$i -lt $r.FieldCount;$i++){$row[$r.GetName($i)]=$r.GetValue($i)};$o+=[pscustomobject]$row};$r.Close();,$o
}
function Show($rows,$label){ "{0,-14}{1,7}{2,8}{3,8}{4,9}" -f $label,'n','勝率%','複勝%','単回収%'; foreach($x in $rows){ "{0,-14}{1,7}{2,8}{3,8}{4,9}" -f $x.grp,$x.n,$x.勝率,$x.複勝率,$x.単回収 } }

$d1cat="CASE WHEN d1>=10 THEN N'1_大幅上昇(+10〜)' WHEN d1>=$T THEN N'2_上昇(+$T〜)' WHEN d1<=-10 THEN N'5_大幅下降(〜-10)' WHEN d1<=-$T THEN N'4_下降(〜-$T)' ELSE N'3_横ばい' END"
$d2cat="CASE WHEN d2>=$T THEN N'上昇' WHEN d2<=-$T THEN N'下降' ELSE N'横ばい' END"
$d1d2 ="$d2cat+N'→'+$d1cat"
$rkcat="CASE WHEN rk=1 THEN N'1位' WHEN rk<=3 THEN N'2-3位' WHEN rk<=6 THEN N'4-6位' ELSE N'7位-' END"

$base=Agg "1=1" $null
"════ コンピ指数 前々走→前走→今走 の変化パターン × 馬券圏内(閾値±$T, 前走≤${MaxGapDays}日) ════"
"基準(2走前提あり全馬): n{0} 勝率{1}% 複勝{2}% 単回収{3}%`n" -f $base[0].n,$base[0].勝率,$base[0].複勝率,$base[0].単回収

"■ 今走の指数変化(d1=今走-前走)別"
Show (Agg "1=1" $d1cat) '変化'
"`n■ 前走の変化(d2)→今走の変化(d1) の2段パターン(n≥100, 複勝率順)"
$g=Agg "1=1" $d1d2
$g=@($g | Where-Object {[int]$_.n -ge 100} | Sort-Object {[double]$_.複勝率} -Descending)
Show $g 'd2→d1'
"`n■ 今走コンピ順位 × 指数変化(同じ順位でも上昇/下降で差が出るか)"
foreach($rk in @(@{n='1位';w='rk=1'},@{n='2-3位';w='rk BETWEEN 2 AND 3'},@{n='4-6位';w='rk BETWEEN 4 AND 6'})){
  "  [$($rk.n)]"
  Show (Agg $rk.w $d1cat) '  変化'
}
$conn.Close()
