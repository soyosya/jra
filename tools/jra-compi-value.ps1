<#
.SYNOPSIS
  コンピ指数「そのもの(絶対値)」と今走の馬券圏内・回収率の関係を調査(変化Δでなく値で)。
.DESCRIPTION
  今走指数(idx)/前走指数(p1)/前々走指数(p2)を値のバンドで層別し、今走の 勝率/複勝率/単回収 を集計。
    ・今走指数値バンド ・前走指数値バンド(=前走の評価が今走を予測するか)
    ・3走平均指数バンド ・今走指数値×今走順位(値は順位の上に情報を足すか)
  回収妙味(市場の過小評価)が特定の指数帯に出るかを単回収で確認。前走≤MaxGapDays日。結果は実質2023中心。
.PARAMETER MaxGapDays 前走最大日数。既定120。
#>
[CmdletBinding()] param([int]$MaxGapDays=120)
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
SELECT s.v,s.d,s.r,s.h,s.idx,s.rk,s.p1,s.p2, k.着順 fin, o.tan
INTO #t
FROM seq s
JOIN 競走結果 k ON k.開催場所=s.v AND k.開催日=s.d AND k.レース番号=s.r AND k.馬名=s.h
OUTER APPLY (SELECT TOP 1 単勝オッズ tan FROM リアルタイムオッズ ro WHERE ro.開催場所=s.v AND ro.開催日=s.d AND ro.レース番号=s.r AND ro.馬名=s.h ORDER BY ro.日時 DESC) o
WHERE s.p1 IS NOT NULL AND s.p2 IS NOT NULL AND k.着順>0 AND DATEDIFF(day,s.pd1,s.d)<=$MaxGapDays;
"@
$c=$conn.CreateCommand();$c.CommandTimeout=300;$c.CommandText=$build;[void]$c.ExecuteNonQuery()

function Agg([string]$where,[string]$groupcol){
  $sel= if($groupcol){"$groupcol grp"}else{"N'-' grp"}; $grp= if($groupcol){"GROUP BY $groupcol"}else{""}
  $ord= if($groupcol){'grp'}else{'1'}
  $sql=@"
SELECT $sel, COUNT(*) n,
  CAST(100.0*SUM(CASE WHEN fin=1 THEN 1.0 ELSE 0 END)/COUNT(*) AS decimal(5,1)) 勝率,
  CAST(100.0*SUM(CASE WHEN fin<=3 THEN 1.0 ELSE 0 END)/COUNT(*) AS decimal(5,1)) 複勝率,
  CAST(100.0*SUM(CASE WHEN fin=1 AND tan IS NOT NULL THEN tan ELSE 0 END)/NULLIF(SUM(CASE WHEN tan IS NOT NULL THEN 1 ELSE 0 END),0) AS decimal(6,1)) 単回収
FROM #t WHERE $where $grp ORDER BY $ord
"@
  $cmd=$conn.CreateCommand();$cmd.CommandText=$sql;$r=$cmd.ExecuteReader()
  $o=@();while($r.Read()){$row=[ordered]@{};for($i=0;$i -lt $r.FieldCount;$i++){$row[$r.GetName($i)]=$r.GetValue($i)};$o+=[pscustomobject]$row};$r.Close();,$o
}
function Show($rows,$label){ "{0,-12}{1,7}{2,8}{3,8}{4,9}" -f $label,'n','勝率%','複勝%','単回収%'; foreach($x in $rows){ "{0,-12}{1,7}{2,8}{3,8}{4,9}" -f $x.grp,$x.n,$x.勝率,$x.複勝率,$x.単回収 } }

$band="CASE WHEN {0}>=80 THEN N'1_80+' WHEN {0}>=70 THEN N'2_70-79' WHEN {0}>=60 THEN N'3_60-69' WHEN {0}>=50 THEN N'4_50-59' WHEN {0}>=40 THEN N'5_40-49' ELSE N'6_<40' END"
$idxb=$band -f 'idx'; $p1b=$band -f 'p1'; $avgb=$band -f '((idx+p1+p2)/3)'

$base=Agg "1=1" $null
"════ コンピ指数そのもの(絶対値)× 今走馬券圏内/回収(前走≤${MaxGapDays}日) ════"
"基準: n{0} 勝率{1}% 複勝{2}% 単回収{3}%`n" -f $base[0].n,$base[0].勝率,$base[0].複勝率,$base[0].単回収

"■ 今走の指数値バンド別"
Show (Agg "1=1" $idxb) '今走指数'
"`n■ 前走の指数値バンド別(前走の評価で今走を予測)"
Show (Agg "1=1" $p1b) '前走指数'
"`n■ 3走平均指数バンド別(地力水準)"
Show (Agg "1=1" $avgb) '平均指数'
"`n■ 今走指数値 × 今走順位(値は順位に情報を足すか / 回収妙味の所在)"
foreach($rk in @(@{n='1位';w='rk=1'},@{n='2-3位';w='rk BETWEEN 2 AND 3'},@{n='4-6位';w='rk BETWEEN 4 AND 6'})){
  "  [$($rk.n)]"; Show (Agg $rk.w $idxb) '  今走指数'
}
$conn.Close()
