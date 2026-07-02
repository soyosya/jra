<#
  軸(コンピ1位)の信頼度を上げる「前々走→前走→今走」変遷シグナル探索。
  レース情報+競走結果+コンピ指数+リアルタイムオッズを馬名チェーンでLAGし、各ファクトの変遷で複勝率/単回収を検証。
  使い方: pwsh -File jra-traj-explore.ps1 [-Rebuild]   (-Rebuild で特徴表 traj_feat/traj_lag を作り直す)
  結論(2026-06-21): 軸=コンピ1位 基準 複勝62.9%/単回収78.8%(市場効率的)。
    ★連続3着内(前々走前走とも3着以内)=複勝66-68%・全年(22/23/24/26)頑健・+4pt=最も確実な確度シグナル(単回収<100%で妙味でなく確度)。
    ★失速型(前走6着以下だが前々走3着以内)=複勝51-53%・22-24頑健(2026のみ61で要観察)=消し。
    着順トラジェクトリが最強。人気/上り3F/コンピ/馬体重/脚質の変遷は弱いor年ブレ大。+EVはどこも無し(織込済)。
#>
param([switch]$Rebuild)
$cs=(Get-Content 'C:\jra\共通\appsettings.json' -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
function Exec($sql){$cn=New-Object System.Data.SqlClient.SqlConnection $cs;$cn.Open();$c=$cn.CreateCommand();$c.CommandText=$sql;$c.CommandTimeout=600;$c.ExecuteNonQuery()|Out-Null;$cn.Close()}
function Q($sql){$cn=New-Object System.Data.SqlClient.SqlConnection $cs;$cn.Open();$c=$cn.CreateCommand();$c.CommandText=$sql;$c.CommandTimeout=300;$da=New-Object System.Data.SqlClient.SqlDataAdapter $c;$ds=New-Object System.Data.DataSet;$da.Fill($ds)|Out-Null;$ds.Tables[0]|Format-Table -AutoSize|Out-String -Width 200;$cn.Close()}

if($Rebuild){
 Write-Host "特徴表を構築中..."
 Exec @"
IF OBJECT_ID('dbo.traj_feat') IS NOT NULL DROP TABLE dbo.traj_feat;
WITH cp AS (SELECT 開催日 d,開催場所 v,レース番号 rno,馬番 u,指数順位 cprank,指数 cpval FROM (SELECT *,ROW_NUMBER() OVER(PARTITION BY 開催日,開催場所,レース番号,馬番 ORDER BY 取得日時 DESC) rn FROM コンピ指数) t WHERE rn=1),
po AS (SELECT 開催日 d,開催場所 v,レース番号 rno,TRY_CAST(馬番 AS int) u,TRY_CAST(人気 AS int) pop,TRY_CAST(単勝オッズ AS float) od FROM (SELECT *,ROW_NUMBER() OVER(PARTITION BY 開催日,開催場所,レース番号,馬番 ORDER BY 日時 DESC) rn FROM リアルタイムオッズ) t WHERE rn=1),
kk AS (SELECT 開催日 d,開催場所 v,レース番号 rno,TRY_CAST(馬番 AS int) u,TRY_CAST(上り3F AS float) ag,TRY_CAST(四コーナー AS int) c4 FROM 競走結果),
fld AS (SELECT 開催場所 v,開催日 d,レース番号 rno,COUNT(*) fc FROM 競走結果 WHERE 着順>0 GROUP BY 開催場所,開催日,レース番号)
SELECT r.開催日 d,r.開催場所 v,r.レース番号 rno,TRY_CAST(r.馬番 AS int) u,r.馬名 nm,
 TRY_CAST(r.着順 AS int) rk,po.pop,po.od,TRY_CAST(r.馬体重増減 AS int) dw,TRY_CAST(r.斤量 AS float) kin,cp.cprank,cp.cpval,kk.ag,kk.c4,fld.fc
INTO dbo.traj_feat FROM レース情報 r
LEFT JOIN cp ON cp.d=r.開催日 AND cp.v=r.開催場所 AND cp.rno=r.レース番号 AND cp.u=TRY_CAST(r.馬番 AS int)
LEFT JOIN po ON po.d=r.開催日 AND po.v=r.開催場所 AND po.rno=r.レース番号 AND po.u=TRY_CAST(r.馬番 AS int)
LEFT JOIN kk ON kk.d=r.開催日 AND kk.v=r.開催場所 AND kk.rno=r.レース番号 AND kk.u=TRY_CAST(r.馬番 AS int)
LEFT JOIN fld ON fld.d=r.開催日 AND fld.v=r.開催場所 AND fld.rno=r.レース番号
WHERE TRY_CAST(r.馬番 AS int)>0;
IF OBJECT_ID('dbo.traj_lag') IS NOT NULL DROP TABLE dbo.traj_lag;
SELECT d,v,rno,u,nm,rk,pop,od,dw,kin,cprank,cpval,ag,c4,fc,YEAR(d) yr,
 LAG(rk) OVER(PARTITION BY nm ORDER BY d,rno) rk1,LAG(rk,2) OVER(PARTITION BY nm ORDER BY d,rno) rk2,
 LAG(pop) OVER(PARTITION BY nm ORDER BY d,rno) pop1,LAG(pop,2) OVER(PARTITION BY nm ORDER BY d,rno) pop2,
 LAG(ag) OVER(PARTITION BY nm ORDER BY d,rno) ag1,LAG(ag,2) OVER(PARTITION BY nm ORDER BY d,rno) ag2,
 LAG(cpval) OVER(PARTITION BY nm ORDER BY d,rno) cpv1,LAG(cpval,2) OVER(PARTITION BY nm ORDER BY d,rno) cpv2,
 LAG(dw) OVER(PARTITION BY nm ORDER BY d,rno) dw1,
 LAG(CASE WHEN fc>0 THEN 1.0*c4/fc END) OVER(PARTITION BY nm ORDER BY d,rno) pr1,
 LAG(CASE WHEN fc>0 THEN 1.0*c4/fc END,2) OVER(PARTITION BY nm ORDER BY d,rno) pr2
INTO dbo.traj_lag FROM dbo.traj_feat;
CREATE INDEX ix_lag ON dbo.traj_lag(cprank,yr);
"@
}
if((Q "SELECT COUNT(*) n FROM sys.tables WHERE name='traj_lag'") -notmatch '[1-9]'){ Write-Host "traj_lag が無い。-Rebuild を付けて実行してください。"; return }
"=== 着順トラジェクトリ × 年別(コンピ1位・基準 複勝62.9/単回収78.8) ==="
Q @"
SELECT sig パターン,yr,COUNT(*) n,CAST(100.0*AVG(CASE WHEN rk<=3 THEN 1.0 ELSE 0 END) AS decimal(4,1)) 複勝,
 CAST(100.0*SUM(CASE WHEN rk=1 THEN od ELSE 0 END)/COUNT(*) AS decimal(5,1)) 単回収
FROM (SELECT yr,rk,od,CASE WHEN rk1 BETWEEN 1 AND 3 AND rk2 BETWEEN 1 AND 3 THEN '1 連続3着内(確度)'
  WHEN rk1>=6 AND rk2 BETWEEN 1 AND 3 THEN '2 失速(前走大敗/前々走好走=消し)' ELSE '9 その他' END sig
 FROM dbo.traj_lag WHERE cprank=1 AND rk>0 AND od>0 AND rk1>0 AND rk2>0) t
WHERE yr IN(2022,2023,2024,2026) GROUP BY sig,yr ORDER BY sig,yr
"@
