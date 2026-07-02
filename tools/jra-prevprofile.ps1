<#
.SYNOPSIS
  前走プロファイル(場+種別+距離+四角位置+上り3F順位)→今走の好走(複勝/勝率/単回収/年別)を洗い出す。
.DESCRIPTION
  前走→今走ペア表 dbo.xcourse_l(レース情報+競走結果(上り3F/四角)+リアルタイムオッズ、馬名チェーンLAG)を集計。
  上り3Fはレース内順位(ar1: 1=最速)で相対化(ペース/馬場差を吸収)。四角位置は位置率pos1(0=最内前,1=最後方)。
  ・前走条件を指定すると、その軸の今走 複勝/勝率/単回収 と年別頑健性を表示。
  ・前走条件を省略 or -Scan で、複勝(または-By 回収)の上位プロファイルをランキング表示。
  検証結論([[jra-course-agari]]): 中央場の中距離×前目〜中団×上り上位だった馬は今走複勝が高い(40-59%・確度頑健)。
    但し単回収は概ね<100%(高回収は単年ノイズ)=市場効率的で+EVは無し→確度ラベル用。
.PARAMETER Rebuild   xcourse/xcourse_l を作り直す(データ更新後)。
.PARAMETER PrevVenue 前走場(東京/中山/阪神…)。PrevSurf 前走種別(芝/ダ)。PrevDistMin/Max 前走距離。
.PARAMETER PrevPos   前走四角位置: 前(<=0.33)/中(<=0.66)/後。  PrevAgari 前走上り順位: 最速/上位/中/下。
.PARAMETER TodayVenue/TodaySurf/TodayDistMin/Max 今走コースで絞る(任意)。
.PARAMETER Scan      ランキング表示を強制。 -By 複勝|回収。 -MinN 最小n(既定80)。 -Top 件数(既定20)。
.EXAMPLE
  pwsh jra-prevprofile.ps1 -PrevVenue 東京 -PrevSurf 芝 -PrevDistMin 1600 -PrevDistMax 1600 -PrevPos 前 -PrevAgari 上位
  pwsh jra-prevprofile.ps1 -Scan -By 複勝 -MinN 100
#>
[CmdletBinding()]
param(
  [switch]$Rebuild,
  [string]$PrevVenue,[string]$PrevSurf,[int]$PrevDistMin,[int]$PrevDistMax,[ValidateSet('前','中','後','')][string]$PrevPos='',[ValidateSet('最速','上位','中','下','')][string]$PrevAgari='',
  [string]$Prev2Surf,[int]$Prev2DistMin,[int]$Prev2DistMax,[ValidateSet('前','中','後','')][string]$Prev2Pos='',[ValidateSet('最速','上位','中','下','')][string]$Prev2Agari='', # 前々走条件(2走一貫の検証用)
  [string]$TodayVenue,[string]$TodaySurf,[int]$TodayDistMin,[int]$TodayDistMax,
  [switch]$Scan,[ValidateSet('複勝','回収')][string]$By='複勝',[int]$MinN=80,[int]$Top=20
)
$cs=(Get-Content 'C:\jra\共通\appsettings.json' -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
function Exec($sql){$cn=New-Object System.Data.SqlClient.SqlConnection $cs;$cn.Open();$c=$cn.CreateCommand();$c.CommandText=$sql;$c.CommandTimeout=600;$c.ExecuteNonQuery()|Out-Null;$cn.Close()}
function Q($sql){$cn=New-Object System.Data.SqlClient.SqlConnection $cs;$cn.Open();$c=$cn.CreateCommand();$c.CommandText=$sql;$c.CommandTimeout=300;$da=New-Object System.Data.SqlClient.SqlDataAdapter $c;$ds=New-Object System.Data.DataSet;$da.Fill($ds)|Out-Null;$ds.Tables[0]|Format-Table -AutoSize|Out-String -Width 200;$cn.Close()}

if($Rebuild){
  Write-Host "xcourse/xcourse_l を再構築中..."
  Exec @"
IF OBJECT_ID('dbo.xcourse') IS NOT NULL DROP TABLE dbo.xcourse;
WITH kk AS (SELECT 開催日 d,開催場所 v,レース番号 rno,TRY_CAST(馬番 AS int) u,TRY_CAST(上り3F AS float) ag,TRY_CAST(四コーナー AS int) c4 FROM 競走結果),
fld AS (SELECT 開催場所 v,開催日 d,レース番号 rno,COUNT(*) fc FROM 競走結果 WHERE 着順>0 GROUP BY 開催場所,開催日,レース番号),
po AS (SELECT 開催日 d,開催場所 v,レース番号 rno,TRY_CAST(馬番 AS int) u,TRY_CAST(単勝オッズ AS float) od,TRY_CAST(人気 AS int) pop FROM (SELECT *,ROW_NUMBER() OVER(PARTITION BY 開催日,開催場所,レース番号,馬番 ORDER BY 日時 DESC) rn FROM リアルタイムオッズ) t WHERE rn=1),
b AS (SELECT r.開催日 d,r.開催場所 v,r.レース番号 rno,TRY_CAST(r.馬番 AS int) u,r.馬名 nm,TRY_CAST(r.着順 AS int) rk,po.od,po.pop,LTRIM(RTRIM(r.コース種別)) surf,TRY_CAST(r.距離 AS int) dist,kk.ag,CASE WHEN fld.fc>0 THEN CAST(1.0*kk.c4/fld.fc AS decimal(4,3)) END pos,fld.fc
 FROM レース情報 r LEFT JOIN kk ON kk.d=r.開催日 AND kk.v=r.開催場所 AND kk.rno=r.レース番号 AND kk.u=TRY_CAST(r.馬番 AS int)
 LEFT JOIN fld ON fld.d=r.開催日 AND fld.v=r.開催場所 AND fld.rno=r.レース番号
 LEFT JOIN po ON po.d=r.開催日 AND po.v=r.開催場所 AND po.rno=r.レース番号 AND po.u=TRY_CAST(r.馬番 AS int) WHERE TRY_CAST(r.馬番 AS int)>0)
SELECT *,CASE WHEN ag>0 THEN RANK() OVER(PARTITION BY d,v,rno ORDER BY CASE WHEN ag>0 THEN ag ELSE 9999 END) END ar INTO dbo.xcourse FROM b;
"@
  Exec @"
IF OBJECT_ID('dbo.xcourse_l') IS NOT NULL DROP TABLE dbo.xcourse_l;
SELECT d,v,rno,nm,rk,od,pop,surf,dist,
 LAG(v) OVER(PARTITION BY nm ORDER BY d,rno) v1,LAG(surf) OVER(PARTITION BY nm ORDER BY d,rno) surf1,LAG(dist) OVER(PARTITION BY nm ORDER BY d,rno) dist1,
 LAG(ag) OVER(PARTITION BY nm ORDER BY d,rno) ag1,LAG(pos) OVER(PARTITION BY nm ORDER BY d,rno) pos1,LAG(ar) OVER(PARTITION BY nm ORDER BY d,rno) ar1,LAG(rk) OVER(PARTITION BY nm ORDER BY d,rno) rk1
INTO dbo.xcourse_l FROM dbo.xcourse;
CREATE INDEX ix_xc ON dbo.xcourse_l(v1,surf1,dist1);
"@
  Write-Host "再構築OK"
}

# 前走条件WHERE構築
$w=@("rk>0","od>0","pos1 IS NOT NULL","ar1 IS NOT NULL","surf1 NOT LIKE N'%障%'")
if($PrevVenue){ $w+="v1=N'$PrevVenue'" }
if($PrevSurf){ $w+="surf1=N'$PrevSurf'" }
if($PrevDistMin){ $w+="dist1>=$PrevDistMin" }
if($PrevDistMax){ $w+="dist1<=$PrevDistMax" }
switch($PrevPos){ '前'{$w+="pos1<=0.33"} '中'{$w+="pos1>0.33 AND pos1<=0.66"} '後'{$w+="pos1>0.66"} }
switch($PrevAgari){ '最速'{$w+="ar1=1"} '上位'{$w+="ar1<=3"} '中'{$w+="ar1 BETWEEN 4 AND 6"} '下'{$w+="ar1>=7"} }
# 前々走条件(2走一貫の検証)。pos2/ar2/surf2/dist2 を使用
if($Prev2Surf){ $w+="surf2=N'$Prev2Surf'" }
if($Prev2DistMin){ $w+="dist2>=$Prev2DistMin" }
if($Prev2DistMax){ $w+="dist2<=$Prev2DistMax" }
switch($Prev2Pos){ '前'{$w+="pos2<=0.33"} '中'{$w+="pos2>0.33 AND pos2<=0.66"} '後'{$w+="pos2>0.66"} }
switch($Prev2Agari){ '最速'{$w+="ar2=1"} '上位'{$w+="ar2<=3"} '中'{$w+="ar2 BETWEEN 4 AND 6"} '下'{$w+="ar2>=7"} }
if($TodayVenue){ $w+="v=N'$TodayVenue'" }
if($TodaySurf){ $w+="surf=N'$TodaySurf'" }
if($TodayDistMin){ $w+="dist>=$TodayDistMin" }
if($TodayDistMax){ $w+="dist<=$TodayDistMax" }
$where=$w -join ' AND '
$hasPrev = $PrevVenue -or $PrevSurf -or $PrevDistMin -or $PrevPos -or $PrevAgari -or $Prev2Surf -or $Prev2DistMin -or $Prev2Pos -or $Prev2Agari

if($hasPrev -and -not $Scan){
  Write-Host "=== 指定軸の今走成績(基準: 全馬複勝~23%) ==="
  Write-Host "前走: 場=$PrevVenue 種別=$PrevSurf 距離=$PrevDistMin-$PrevDistMax 位置=$PrevPos 上り=$PrevAgari / 前々走: 種別=$Prev2Surf 距離=$Prev2DistMin-$Prev2DistMax 位置=$Prev2Pos 上り=$Prev2Agari / 今走: 場=$TodayVenue 種別=$TodaySurf 距離=$TodayDistMin-$TodayDistMax"
  Q "SELECT COUNT(*) n,CAST(100.0*AVG(CASE WHEN rk<=3 THEN 1.0 ELSE 0 END) AS decimal(4,1)) 今走複勝,CAST(100.0*AVG(CASE WHEN rk=1 THEN 1.0 ELSE 0 END) AS decimal(4,1)) 今走勝率,CAST(100.0*SUM(CASE WHEN rk=1 THEN od ELSE 0 END)/COUNT(*) AS decimal(6,1)) 単回収 FROM dbo.xcourse_l WHERE $where"
  Write-Host "--- 年別頑健性(2025はデータ薄で除外) ---"
  Q "SELECT YEAR(d) yr,COUNT(*) n,CAST(100.0*AVG(CASE WHEN rk<=3 THEN 1.0 ELSE 0 END) AS decimal(4,1)) 複勝,CAST(100.0*SUM(CASE WHEN rk=1 THEN od ELSE 0 END)/COUNT(*) AS decimal(6,1)) 単回収 FROM dbo.xcourse_l WHERE $where AND YEAR(d) IN(2022,2023,2024,2026) GROUP BY YEAR(d) ORDER BY yr"
}
else {
  $ord= if($By -eq '回収'){'単回収'}else{'今走複勝'}
  Write-Host "=== 前走プロファイル ランキング($By 上位・n>=$MinN) ==="
  if($where){ Write-Host "絞り込み: $where" }
  $sel=@"
SELECT v1+surf1+CAST(dist1 AS varchar)+'/'+CASE WHEN pos1<=0.33 THEN '前' WHEN pos1<=0.66 THEN '中' ELSE '後' END
 +'/'+CASE WHEN ar1=1 THEN '上速' WHEN ar1<=3 THEN '上2-3' WHEN ar1<=6 THEN '上中' ELSE '上下' END 前走軸,
 COUNT(*) n,CAST(100.0*AVG(CASE WHEN rk<=3 THEN 1.0 ELSE 0 END) AS decimal(4,1)) 今走複勝,
 CAST(100.0*AVG(CASE WHEN rk=1 THEN 1.0 ELSE 0 END) AS decimal(4,1)) 今走勝率,
 CAST(100.0*SUM(CASE WHEN rk=1 THEN od ELSE 0 END)/COUNT(*) AS decimal(6,1)) 単回収
FROM dbo.xcourse_l WHERE $where AND dist1>0
GROUP BY v1+surf1+CAST(dist1 AS varchar)+'/'+CASE WHEN pos1<=0.33 THEN '前' WHEN pos1<=0.66 THEN '中' ELSE '後' END+'/'+CASE WHEN ar1=1 THEN '上速' WHEN ar1<=3 THEN '上2-3' WHEN ar1<=6 THEN '上中' ELSE '上下' END
"@
  Q "SELECT TOP $Top * FROM ($sel) t WHERE n>=$MinN ORDER BY $ord DESC"
  Write-Host "※高回収は単年ノイズの可能性大。複勝が高く全年安定なものが確度シグナル(+EVは中央では出ない=織込済)。"
}
