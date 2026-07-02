<#
.SYNOPSIS
  軸候補(コンピ1位)の 前々走→前走→今走 のコンピ指数変遷で「下降」軸の成績と、評価ダウン時の効果を検証。
.DESCRIPTION
  各コンピ1位の 今走指数 i0 / 前走 i1 / 前々走 i2(馬名で過去コンピ参照)。
  パターン別(単調下降 i0<i1<i2 / 累積下降幅帯 / 上昇 等)に コンピ1位の勝率/複勝率/単回収。
  「下降軸を軸から外す」効果= 非下降のみ残した軸の成績 と 外した(下降)軸の成績 を対比。
  さらに下降レースでコンピ2位へ入替えた場合の2位成績も対比。年別頑健性も。市場効率の規律で判定。
#>
[CmdletBinding()]param([string]$From='2022-01-01',[string]$To='2026-12-31')
$ErrorActionPreference='Stop'
$cs=(Get-Content (Join-Path $PSScriptRoot '..\共通\appsettings.json') -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
$conn=New-Object System.Data.SqlClient.SqlConnection($cs);$conn.Open()
function Q($s){$c=$conn.CreateCommand();$c.CommandText=$s;$c.CommandTimeout=600;[void]$c.Parameters.AddWithValue('@f',$From);[void]$c.Parameters.AddWithValue('@t',$To);$r=$c.ExecuteReader();$o=@();while($r.Read()){$row=[ordered]@{};for($i=0;$i -lt $r.FieldCount;$i++){$row[$r.GetName($i)]=$r.GetValue($i)};$o+=[pscustomobject]$row};$r.Close();$o}

# 軸候補=コンピ1位。今走i0/前走i1/前々走i2(馬名で過去参照)+着順+単勝払戻。基準ビューd。
$CTE=@"
t AS (
  SELECT 開催日,開催場所,レース番号,馬番,馬名,CAST(指数 AS int) i0
  FROM (SELECT *,ROW_NUMBER() OVER(PARTITION BY 開催日,開催場所,レース番号,馬番 ORDER BY 取得日時 DESC) rn FROM コンピ指数 WHERE 開催日 BETWEEN @f AND @t AND 指数順位=1 AND 指数 IS NOT NULL) z WHERE rn=1
),
d AS (
 SELECT t.開催日,t.開催場所,t.レース番号,t.馬番,r.着順,t.i0,pp.i1,pp.i2,pay.金額 tan
 FROM t
 JOIN レース情報 r ON r.開催日=t.開催日 AND r.開催場所=t.開催場所 AND r.レース番号=t.レース番号 AND r.馬番=t.馬番 AND r.着順>0
 OUTER APPLY (
   SELECT MAX(CASE WHEN rk=1 THEN idx END) i1, MAX(CASE WHEN rk=2 THEN idx END) i2
   FROM (SELECT CAST(z.指数 AS int) idx, ROW_NUMBER() OVER(ORDER BY z.開催日 DESC,z.レース番号 DESC) rk
         FROM (SELECT *,ROW_NUMBER() OVER(PARTITION BY 開催日,開催場所,レース番号 ORDER BY 取得日時 DESC) rr FROM コンピ指数 WHERE 馬名=t.馬名 AND 開催日<t.開催日 AND 指数 IS NOT NULL) z
         WHERE z.rr=1) y WHERE rk<=2
 ) pp
 OUTER APPLY (SELECT TOP 1 TRY_CONVERT(int,金額) 金額 FROM 払戻金 p WHERE p.開催日=t.開催日 AND p.開催場所=t.開催場所 AND p.レース番号=t.レース番号 AND p.馬券=N'単勝' AND TRY_CONVERT(int,p.組番)=t.馬番) pay
)
"@
function Met($cond){
  $m=(Q @"
WITH $CTE
SELECT COUNT(*) N,100.0*SUM(CASE WHEN 着順=1 THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) 勝,100.0*SUM(CASE WHEN 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) 複,100.0*SUM(CASE WHEN 着順=1 THEN ISNULL(tan,0) ELSE 0 END)/NULLIF(100.0*COUNT(*),0) 単回
FROM d WHERE $cond
"@)[0]; $m
}
function Show($lab,$cond){ $m=Met $cond; "  {0,-30} N={1,5} 勝率={2,5:N1}% 複勝率={3,5:N1}% 単回収={4,6:N1}%" -f $lab,$m.N,$m.勝,$m.複,$m.単回 }

"===== 軸候補(コンピ1位)の 指数変遷別 成績  ($From〜$To) ====="
Show "全コンピ1位(基準)"           "1=1"
Show "  2走分とも有(判定可)"       "i1 IS NOT NULL AND i2 IS NOT NULL"
Show "  単調下降 i0<i1<i2"         "i2 IS NOT NULL AND i0<i1 AND i1<i2"
Show "  下降傾向 i0<i1 & i1<=i2"   "i2 IS NOT NULL AND i0<i1 AND i1<=i2"
Show "  横ばい/混在"               "i2 IS NOT NULL AND NOT(i0<i1 AND i1<=i2) AND NOT(i0>i1 AND i1>=i2)"
Show "  上昇傾向 i0>i1 & i1>=i2"   "i2 IS NOT NULL AND i0>i1 AND i1>=i2"
""
"===== 累積下降幅(i2-i0)帯別 (判定可のみ) ====="
foreach($b in @(@('下降15+','(i2-i0)>=15'),@('下降8-14','(i2-i0) BETWEEN 8 AND 14'),@('下降1-7','(i2-i0) BETWEEN 1 AND 7'),@('変化0','(i2-i0)=0'),@('上昇1-7','(i0-i2) BETWEEN 1 AND 7'),@('上昇8+','(i0-i2)>=8'))){
  Show $b[0] ("i2 IS NOT NULL AND "+$b[1])
}
""
"===== 評価ダウン効果: 下降軸を外す ====="
Show "外す前(判定可の全軸)"        "i1 IS NOT NULL AND i2 IS NOT NULL"
Show "外す(単調下降を除外し残す軸)" "i1 IS NOT NULL AND i2 IS NOT NULL AND NOT(i0<i1 AND i1<i2)"
Show "外した分(単調下降軸=評価ダウン)" "i2 IS NOT NULL AND i0<i1 AND i1<i2"
""
"===== 単調下降の年別頑健性 ====="
foreach($y in 2022,2023,2024,2025,2026){
  $m=(Q @"
WITH $CTE
SELECT COUNT(*) N,100.0*SUM(CASE WHEN 着順=1 THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) 勝,100.0*SUM(CASE WHEN 着順 BETWEEN 1 AND 3 THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) 複
FROM d WHERE i2 IS NOT NULL AND i0<i1 AND i1<i2 AND YEAR(開催日)=$y
"@)[0]
  "  {0}: 単調下降軸 N={1,4} 勝率={2,5:N1}% 複勝率={3,5:N1}%" -f $y,$m.N,$m.勝,$m.複
}
$conn.Close()
