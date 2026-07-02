<#
.SYNOPSIS
  前走・前々走で「レース内 上り3Fベスト3」を連続達成した馬の次走成績を分析。
.DESCRIPTION
  各(レース,馬)について上り3FのレースINランク(RANK,小さいほど速い)を算出し、
  馬ごとの時系列で 前走(p1)/前々走(p2) のランクを LAG で取得。
  「p1<=3 かつ p2<=3」を連続ベスト3とし、その馬の当該レース(=次走)の成績を集計。
  ベースライン(2走前提あり全馬)/前走のみベスト3 と比較し、さらに次走の 場/コース種別/距離 で層別。
  上り0や着順0(中止等)は除外。前走は365日以内に限定(データ欠損での無関係連鎖を抑制)。
  回収=単勝(単勝オッズ×100, 的中時)。複勝回収は別途。データは時計のある年に依存(実質2023中心)。
.PARAMETER MaxGapDays 前走までの最大日数。既定365。
#>
[CmdletBinding()] param([int]$MaxGapDays=365,[double]$MaxMargin=1.2)
$ErrorActionPreference='Stop'
$conn=New-Object System.Data.SqlClient.SqlConnection((Get-Content 'C:\jra\共通\appsettings.json' -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection)
$conn.Open()

# 1) #s 構築: 上りランク + 前走/前々走ランク・日付 + 単勝オッズ
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
  SELECT *,
    LAG(agrank,1) OVER(PARTITION BY h ORDER BY d,r) p1,
    LAG(agrank,2) OVER(PARTITION BY h ORDER BY d,r) p2,
    LAG(mgn,1)    OVER(PARTITION BY h ORDER BY d,r) pm1,
    LAG(mgn,2)    OVER(PARTITION BY h ORDER BY d,r) pm2,
    LAG(d,1) OVER(PARTITION BY h ORDER BY d,r) pd1
  FROM base
)
SELECT s.v,s.d,s.r,s.h,s.fin,s.surf,s.dist,s.agrank,s.p1,s.p2,s.pm1,s.pm2,
  CASE WHEN s.dist<=1200 THEN N'1_≤1200' WHEN s.dist<=1600 THEN N'2_1201-1600'
       WHEN s.dist<=2000 THEN N'3_1601-2000' ELSE N'4_2001+' END distband,
  o.単勝オッズ tan
INTO #s
FROM seq s
LEFT JOIN リアルタイムオッズ o ON o.開催場所=s.v AND o.開催日=s.d AND o.レース番号=s.r AND o.馬名=s.h
WHERE s.p1 IS NOT NULL AND s.p2 IS NOT NULL AND DATEDIFF(day,s.pd1,s.d)<=$MaxGapDays;
"@
$c=$conn.CreateCommand();$c.CommandTimeout=180;$c.CommandText=$build;[void]$c.ExecuteNonQuery()

function Agg([string]$where,[string]$groupcol){
  $sel = if($groupcol){"$groupcol grp"}else{"N'-' grp"}
  $grp = if($groupcol){"GROUP BY $groupcol"}else{""}
  $sql=@"
SELECT $sel, COUNT(*) n,
  CAST(100.0*SUM(CASE WHEN fin=1 THEN 1.0 ELSE 0 END)/COUNT(*) AS decimal(5,1)) 勝率,
  CAST(100.0*SUM(CASE WHEN fin<=3 THEN 1.0 ELSE 0 END)/COUNT(*) AS decimal(5,1)) 複勝率,
  SUM(CASE WHEN tan IS NOT NULL THEN 1 ELSE 0 END) n_odds,
  CAST(100.0*SUM(CASE WHEN fin=1 AND tan IS NOT NULL THEN tan ELSE 0 END)/NULLIF(SUM(CASE WHEN tan IS NOT NULL THEN 1 ELSE 0 END),0) AS decimal(6,1)) 単回収
FROM #s WHERE $where $grp ORDER BY $(if($groupcol){'grp'}else{'1'})
"@
  $cmd=$conn.CreateCommand();$cmd.CommandText=$sql
  try { $r=$cmd.ExecuteReader() } catch { Write-Host "---SQL---`n$sql`n---------"; throw }
  $o=@();while($r.Read()){$row=[ordered]@{};for($i=0;$i -lt $r.FieldCount;$i++){$row[$r.GetName($i)]=$r.GetValue($i)};$o+=[pscustomobject]$row};$r.Close();,$o
}
function Show($rows,$label){
  "{0,-14}{1,7}{2,8}{3,8}{4,9}" -f $label,'n','勝率%','複勝%','単回収%'
  foreach($x in $rows){ "{0,-14}{1,7}{2,8}{3,8}{4,9}" -f $x.grp,$x.n,$x.勝率,$x.複勝率,$x.単回収 }
}

$STRK = "p1<=3 AND p2<=3"
$STRKM = "p1<=3 AND p2<=3 AND pm1<=$MaxMargin AND pm2<=$MaxMargin"
$STRKMI = "$STRKM AND pm1 < pm2"   # 前走着差 < 前々走着差(=前走の方が1着に近い=上昇)
"════ 上り3F連続ベスト3 + 着差≤${MaxMargin}秒 + 前走着差<前々走着差(前走≤${MaxGapDays}日) ════`n"
"■ 比較(全体)"
$resBase=Agg "1=1" $null
$resStrk=Agg $STRK $null
$resStrkm=Agg $STRKM $null
$resStrkmi=Agg $STRKMI $null
$resStrkmn=Agg "$STRKM AND pm1 >= pm2" $null   # 対照: 前走着差≥前々走着差(非改善)
"{0,-30}{1,7}{2,8}{3,8}{4,9}" -f '区分','n','勝率%','複勝%','単回収%'
"{0,-30}{1,7}{2,8}{3,8}{4,9}" -f '2走前提あり全馬(基準)',$resBase[0].n,$resBase[0].勝率,$resBase[0].複勝率,$resBase[0].単回収
"{0,-30}{1,7}{2,8}{3,8}{4,9}" -f '連続上りベスト3',$resStrk[0].n,$resStrk[0].勝率,$resStrk[0].複勝率,$resStrk[0].単回収
"{0,-30}{1,7}{2,8}{3,8}{4,9}" -f "★連続+着差≤${MaxMargin}秒",$resStrkm[0].n,$resStrkm[0].勝率,$resStrkm[0].複勝率,$resStrkm[0].単回収
"{0,-30}{1,7}{2,8}{3,8}{4,9}" -f "★★ 前走着差<前々走(改善)",$resStrkmi[0].n,$resStrkmi[0].勝率,$resStrkmi[0].複勝率,$resStrkmi[0].単回収
"{0,-30}{1,7}{2,8}{3,8}{4,9}" -f "   対照 前走着差≥前々走(非改善)",$resStrkmn[0].n,$resStrkmn[0].勝率,$resStrkmn[0].複勝率,$resStrkmn[0].単回収

"`n■ ★★(前走着差<前々走着差) × 次走 開催場所別(n≥10)"
Show (Agg $STRKMI "v" | Where-Object {$_.n -ge 10}) '場'
"`n■ ★★ × 次走 コース種別別"
Show (Agg $STRKMI "surf") 'コース'
"`n■ ★★ × 次走 距離帯別"
Show (Agg $STRKMI "distband") '距離帯'
$conn.Close()
