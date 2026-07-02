<#
.SYNOPSIS
  上り3F★(前走・前々走とも上り3Fベスト3+着差≤1.2秒)の馬が、今走で前走からどうローテを変えるかで
  次走成績(的中率)に特徴が出るかを分析。軸=距離変化/コース替わり/開催場所替わり。
.DESCRIPTION
  #s に 今走の場/距離/コース種別 と 前走(LAG1)の場/距離/コース を持たせ、ローテ区分を算出:
    距離変化: 今走-前走 ≥+100=延長 / ≤-100=短縮 / 他=同距離
    コース替: 同 / ダ→芝 / 芝→ダ
    場替: 同場 / 場替
  ★群を各ローテ区分で層別(勝率/複勝率)。比較に「全馬(基準)」「連続のみ(★前)」も各区分で表示。
  的中率重視(回収は参考)。上り0/着順0除外、前走365日内。
.PARAMETER MaxMargin 着差上限秒(既定1.2)  .PARAMETER MaxGapDays 前走最大日数(既定365)
#>
[CmdletBinding()] param([double]$MaxMargin=1.2,[int]$MaxGapDays=365)
$ErrorActionPreference='Stop'
$conn=New-Object System.Data.SqlClient.SqlConnection((Get-Content 'C:\jra\共通\appsettings.json' -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection)
$conn.Open()
$build=@"
IF OBJECT_ID('tempdb..#s') IS NOT NULL DROP TABLE #s;
WITH base AS (
  SELECT k.開催場所 v,k.開催日 d,k.レース番号 r,k.馬名 h,k.着順 fin,
         ri.コース種別 surf, ri.距離 dist, k.一着馬着差タイム mgn,
         RANK() OVER(PARTITION BY k.開催場所,k.開催日,k.レース番号 ORDER BY k.上り3F ASC) agrank
  FROM 競走結果 k
  JOIN レース情報 ri ON ri.開催場所=k.開催場所 AND ri.開催日=k.開催日 AND ri.レース番号=k.レース番号 AND ri.馬番=k.馬番
  WHERE k.上り3F>0 AND k.着順>0 AND ri.コース種別 IN (N'芝',N'ダ')
),
seq AS (
  SELECT v,d,r,h,fin,surf,dist,mgn,agrank,
    LAG(agrank,1) OVER(PARTITION BY h ORDER BY d,r) p1,
    LAG(agrank,2) OVER(PARTITION BY h ORDER BY d,r) p2,
    LAG(mgn,1)    OVER(PARTITION BY h ORDER BY d,r) pm1,
    LAG(mgn,2)    OVER(PARTITION BY h ORDER BY d,r) pm2,
    LAG(surf,1)   OVER(PARTITION BY h ORDER BY d,r) psurf,
    LAG(v,1)      OVER(PARTITION BY h ORDER BY d,r) pv,
    LAG(dist,1)   OVER(PARTITION BY h ORDER BY d,r) pdist,
    LAG(d,1)      OVER(PARTITION BY h ORDER BY d,r) pd1
  FROM base
)
SELECT s.v,s.d,s.r,s.h,s.fin,s.surf,s.dist,s.p1,s.p2,s.pm1,s.pm2,
  CASE WHEN s.dist-s.pdist>=100 THEN N'延長' WHEN s.dist-s.pdist<=-100 THEN N'短縮' ELSE N'同距離' END distchg,
  CASE WHEN s.surf=s.psurf THEN N'同' WHEN s.psurf=N'ダ' AND s.surf=N'芝' THEN N'ダ→芝'
       WHEN s.psurf=N'芝' AND s.surf=N'ダ' THEN N'芝→ダ' ELSE N'他' END surfchg,
  CASE WHEN s.v=s.pv THEN N'同場' ELSE N'場替' END venuechg,
  o.単勝オッズ tan
INTO #s
FROM seq s
LEFT JOIN リアルタイムオッズ o ON o.開催場所=s.v AND o.開催日=s.d AND o.レース番号=s.r AND o.馬名=s.h
WHERE s.p1 IS NOT NULL AND s.p2 IS NOT NULL AND DATEDIFF(day,s.pd1,s.d)<=$MaxGapDays;
"@
$c=$conn.CreateCommand();$c.CommandTimeout=300;$c.CommandText=$build;[void]$c.ExecuteNonQuery()

function Agg([string]$where,[string]$groupcol){
  $sel= if($groupcol){"$groupcol grp"}else{"N'-' grp"}; $grp= if($groupcol){"GROUP BY $groupcol"}else{""}
  $sql=@"
SELECT $sel, COUNT(*) n,
  CAST(100.0*SUM(CASE WHEN fin=1 THEN 1.0 ELSE 0 END)/COUNT(*) AS decimal(5,1)) 勝率,
  CAST(100.0*SUM(CASE WHEN fin<=3 THEN 1.0 ELSE 0 END)/COUNT(*) AS decimal(5,1)) 複勝率,
  CAST(100.0*SUM(CASE WHEN fin=1 AND tan IS NOT NULL THEN tan ELSE 0 END)/NULLIF(SUM(CASE WHEN tan IS NOT NULL THEN 1 ELSE 0 END),0) AS decimal(6,1)) 単回収
FROM #s WHERE $where $grp ORDER BY $(if($groupcol){'grp'}else{'1'})
"@
  $cmd=$conn.CreateCommand();$cmd.CommandText=$sql;$r=$cmd.ExecuteReader()
  $o=@();while($r.Read()){$row=[ordered]@{};for($i=0;$i -lt $r.FieldCount;$i++){$row[$r.GetName($i)]=$r.GetValue($i)};$o+=[pscustomobject]$row};$r.Close();,$o
}
function Show($rows,$label){
  "{0,-10}{1,7}{2,8}{3,8}{4,9}" -f $label,'n','勝率%','複勝%','単回収%'
  foreach($x in $rows){ "{0,-10}{1,7}{2,8}{3,8}{4,9}" -f $x.grp,$x.n,$x.勝率,$x.複勝率,$x.単回収 }
}
$STRKM="p1<=3 AND p2<=3 AND pm1<=$MaxMargin AND pm2<=$MaxMargin"
$rB=Agg "1=1" $null; $rM=Agg $STRKM $null
"════ ★(上り連続+着差≤${MaxMargin}秒) × 前走→今走ローテ ════"
"基準(全馬): 複勝 {0}%  /  ★全体: n{1} 勝率{2}% 複勝{3}%`n" -f $rB[0].複勝率,$rM[0].n,$rM[0].勝率,$rM[0].複勝率

"■ ★ × 距離変化"
Show (Agg $STRKM "distchg") '距離変化'
"  (参考)全馬 × 距離変化"
Show (Agg "1=1" "distchg") '距離変化'
"`n■ ★ × コース替わり"
Show (Agg $STRKM "surfchg") 'コース替'
"`n■ ★ × 開催場所替わり"
Show (Agg $STRKM "venuechg") '場替'
"`n■ ★ × 距離変化 × コース替わり(n≥30)"
Show (Agg $STRKM "distchg+N'/'+surfchg" | Where-Object {$_.n -ge 30}) '距離/コース'
$conn.Close()
