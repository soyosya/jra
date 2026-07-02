<#
.SYNOPSIS
  中央競馬の軸予測用 特徴量テーブルを materialize する(リークなし・レース時点で既知の情報のみ)。
.DESCRIPTION
  キー (開催場所,開催日,レース番号,馬番) で 特徴量 テーブルを全置換。
  含む特徴(すべて出走前に既知):
    頭数, コンピ指数/順位/相対順位/レース内z,
    過去SF(best/avg3/last/本数)・前走からの間隔日, 斤量/斤量z, 馬体重増減, 枠番, 馬齢, 牝flag。
  併せて市場(単勝オッズ,人気)とラベル(着順,win,place)を格納(EV検証・学習用)。
  過去SFは スピード指数 を 馬名×開催日<当日 で自己結合(=リークなし)。
.PARAMETER From 既定 2022-01-01  .PARAMETER To 既定 2100-01-01
#>
[CmdletBinding()]
param([string]$From='2022-01-01',[string]$To='2100-01-01')
$ErrorActionPreference='Stop'
$connStr=(Get-Content 'C:\jra\共通\appsettings.json' -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
$conn=New-Object System.Data.SqlClient.SqlConnection($connStr); $conn.Open()
try {
  $ddl=@"
IF OBJECT_ID('dbo.特徴量','U') IS NULL
CREATE TABLE dbo.特徴量(
  開催場所 nvarchar(10) NOT NULL, 開催日 date NOT NULL, レース番号 int NOT NULL, 馬番 int NOT NULL,
  馬名 nvarchar(50) NULL, 頭数 int NULL,
  compi_idx int NULL, compi_rank int NULL, compi_relrank float NULL, compi_z float NULL,
  sf_best float NULL, sf_avg3 float NULL, sf_last float NULL, n_prior int NULL, days_since int NULL,
  kinryo float NULL, kinryo_z float NULL, taiju_delta int NULL, waku int NULL, age int NULL, is_hin int NULL,
  tan_odds decimal(9,1) NULL, ninki int NULL,
  fin int NULL, win int NULL, plc int NULL,
  CONSTRAINT PK_特徴量 PRIMARY KEY(開催場所,開催日,レース番号,馬番)
);
"@
  $c=$conn.CreateCommand();$c.CommandText=$ddl;[void]$c.ExecuteNonQuery()
  $c=$conn.CreateCommand();$c.CommandText="DELETE FROM dbo.特徴量 WHERE 開催日>=@f AND 開催日<@t"
  [void]$c.Parameters.AddWithValue('@f',$From);[void]$c.Parameters.AddWithValue('@t',$To);[void]$c.ExecuteNonQuery()

  $ins=@"
WITH base AS (
  SELECT k.開催場所 v,k.開催日 d,k.レース番号 r,k.馬番 no,k.馬名 horse,k.着順 fin,
         ri.距離 dist, ri.斤量 kin, ri.馬体重増減 td, k.枠番 waku, ri.馬齢 age, ri.性別 sex,
         co.指数 cidx, co.指数順位 crank, co.頭数 cnt,
         o.単勝オッズ tan, o.人気 nin
  FROM 競走結果 k
  JOIN レース情報 ri ON ri.開催場所=k.開催場所 AND ri.開催日=k.開催日 AND ri.レース番号=k.レース番号 AND ri.馬番=k.馬番
  LEFT JOIN コンピ指数 co ON co.開催場所=k.開催場所 AND co.開催日=k.開催日 AND co.レース番号=k.レース番号 AND co.馬番=k.馬番
  LEFT JOIN リアルタイムオッズ o ON o.開催場所=k.開催場所 AND o.開催日=k.開催日 AND o.レース番号=k.レース番号 AND o.馬番=k.馬番
  WHERE k.開催日>=@f AND k.開催日<@t
),
racestat AS (
  SELECT v,d,r, AVG(CAST(cidx AS float)) ai, STDEV(CAST(cidx AS float)) si,
                AVG(CAST(kin AS float))  ak, STDEV(CAST(kin AS float))  sk,
                COUNT(*) cntall
  FROM base GROUP BY v,d,r
)
INSERT INTO dbo.特徴量
(開催場所,開催日,レース番号,馬番,馬名,頭数,compi_idx,compi_rank,compi_relrank,compi_z,
 sf_best,sf_avg3,sf_last,n_prior,days_since,kinryo,kinryo_z,taiju_delta,waku,age,is_hin,tan_odds,ninki,fin,win,plc)
SELECT b.v,b.d,b.r,b.no,b.horse, ISNULL(b.cnt,rs.cntall),
  b.cidx, b.crank,
  CASE WHEN b.cnt>1 THEN (b.crank-1.0)/(b.cnt-1) END,
  CASE WHEN rs.si>0 THEN (b.cidx-rs.ai)/rs.si END,
  sp.best, sp.avg3, sp.lastsf, ISNULL(sp.np,0), sp.dsince,
  b.kin, CASE WHEN rs.sk>0 THEN (b.kin-rs.ak)/rs.sk END,
  b.td, b.waku, b.age, CASE WHEN b.sex=N'牝' THEN 1 ELSE 0 END,
  b.tan, b.nin, b.fin,
  CASE WHEN b.fin=1 THEN 1 ELSE 0 END, CASE WHEN b.fin<=3 THEN 1 ELSE 0 END
FROM base b JOIN racestat rs ON rs.v=b.v AND rs.d=b.d AND rs.r=b.r
OUTER APPLY (
  SELECT MAX(p.SF) best, AVG(p.SF) avg3all, COUNT(*) np,
         MAX(CASE WHEN p.開催日=lp.ld THEN p.SF END) lastsf,
         DATEDIFF(day, lp.ld, b.d) dsince,
         (SELECT AVG(x.SF) FROM (SELECT TOP 3 SF FROM スピード指数 q WHERE q.馬名=b.horse AND q.開催日<b.d ORDER BY q.開催日 DESC) x) avg3
  FROM スピード指数 p
  CROSS APPLY (SELECT MAX(p2.開催日) ld FROM スピード指数 p2 WHERE p2.馬名=b.horse AND p2.開催日<b.d) lp
  WHERE p.馬名=b.horse AND p.開催日<b.d
  GROUP BY lp.ld
) sp;
"@
  $c=$conn.CreateCommand();$c.CommandTimeout=600;$c.CommandText=$ins
  [void]$c.Parameters.AddWithValue('@f',$From);[void]$c.Parameters.AddWithValue('@t',$To)
  $n=$c.ExecuteNonQuery()
  Write-Host ("✓ 特徴量 へ {0} 行 materialize ({1}〜{2})" -f $n,$From,$To)
  # サマリ
  $c=$conn.CreateCommand();$c.CommandText="SELECT COUNT(*) n,SUM(CASE WHEN compi_idx IS NOT NULL THEN 1 ELSE 0 END) hc,SUM(CASE WHEN n_prior>0 THEN 1 ELSE 0 END) hsf,SUM(CASE WHEN tan_odds IS NOT NULL THEN 1 ELSE 0 END) ho FROM 特徴量 WHERE YEAR(開催日)=2023"
  $r=$c.ExecuteReader();$r.Read()|Out-Null
  "2023: 行$($r['n']) / コンピ有$($r['hc']) / 過去SF有$($r['hsf']) / オッズ有$($r['ho'])"
  $r.Close()
} finally { $conn.Close() }
