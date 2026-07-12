# H1バックテスト: ダ中距離(1600-1800)下級条件で「前走短距離(≤1400)ダを先行(四角≤4)して善戦(5着内)した距離延長馬」の単勝/複勝回収を年別で。base比。
[Console]::OutputEncoding=[Text.Encoding]::UTF8
$cs='Server=192.168.168.81\SQLEXPRESS;Database=中央競馬;User Id=sa;Password=Hanasaki#2093;TrustServerCertificate=True;Connect Timeout=30'
$cn=New-Object System.Data.SqlClient.SqlConnection $cs;$cn.Open()
function Q($sql){ $c=$cn.CreateCommand();$c.CommandText=$sql;$c.CommandTimeout=600;$dt=New-Object System.Data.DataTable;(New-Object System.Data.SqlClient.SqlDataAdapter $c).Fill($dt)|Out-Null;,$dt.Rows }
$sql=@"
WITH runs AS (
  SELECT k.馬名, YEAR(k.開催日) yr, k.開催日 d, k.開催場所 v, k.レース番号 r, k.馬番 no,
    TRY_CONVERT(int,k.着順) ch, TRY_CONVERT(int,k.四コーナー) c4, ri.距離 dist, ri.コース種別 sf, ri.条件 jk,
    LAG(ri.距離)                    OVER(PARTITION BY k.馬名 ORDER BY k.開催日,k.レース番号) pdist,
    LAG(ri.コース種別)              OVER(PARTITION BY k.馬名 ORDER BY k.開催日,k.レース番号) psf,
    LAG(TRY_CONVERT(int,k.着順))    OVER(PARTITION BY k.馬名 ORDER BY k.開催日,k.レース番号) pch,
    LAG(TRY_CONVERT(int,k.四コーナー)) OVER(PARTITION BY k.馬名 ORDER BY k.開催日,k.レース番号) pc4
  FROM dbo.競走結果 k
  JOIN dbo.レース情報 ri ON ri.開催日=k.開催日 AND ri.開催場所=k.開催場所 AND ri.レース番号=k.レース番号 AND ri.馬番=k.馬番
  WHERE TRY_CONVERT(int,k.着順)>0
),
uni AS (
  SELECT *, CASE WHEN psf LIKE N'%ダ%' AND pdist<=1400 AND pc4 BETWEEN 1 AND 4 AND pch BETWEEN 1 AND 5 THEN 1 ELSE 0 END feat
  FROM runs
  WHERE sf LIKE N'%ダ%' AND dist BETWEEN 1600 AND 1800 AND (jk LIKE N'%未勝利%' OR jk LIKE N'%1勝%' OR jk LIKE N'%2勝%')
),
pay AS (
  SELECT 開催日 d,開催場所 v,レース番号 r, TRY_CONVERT(int,組番) kb, 馬券, TRY_CONVERT(int,金額) kin
  FROM dbo.払戻金 WHERE 馬券 IN (N'単勝',N'複勝')
)
SELECT u.yr, u.feat,
  COUNT(*) n,
  SUM(CASE WHEN u.ch=1 THEN 1 ELSE 0 END) wins,
  SUM(CASE WHEN u.ch<=3 THEN 1 ELSE 0 END) top3,
  SUM(ISNULL(pt.kin,0)) tan_ret,
  SUM(ISNULL(pf.kin,0)) fuku_ret
FROM uni u
LEFT JOIN pay pt ON pt.d=u.d AND pt.v=u.v AND pt.r=u.r AND pt.kb=u.no AND pt.馬券=N'単勝' AND u.ch=1
LEFT JOIN pay pf ON pf.d=u.d AND pf.v=u.v AND pf.r=u.r AND pf.kb=u.no AND pf.馬券=N'複勝' AND u.ch<=3
GROUP BY u.yr, u.feat ORDER BY u.feat DESC, u.yr
"@
"=== H1: ダ1600-1800下級条件 / feat=1:前走ダ≤1400先行(四角1-4)着≤5の距離延長馬 ==="
"{0,-6} {1,4} {2,7} {3,7} {4,8} {5,8} {6,8}" -f 'feat/年','n','勝率','複勝率','単回収','複回収',''
'-'*58
$agg=@{}
foreach($x in (Q $sql)){
  $n=[int]$x.n; if($n -eq 0){continue}
  $tan= if($n){[double]$x.tan_ret/($n*100)}else{0}; $fuku= if($n){[double]$x.fuku_ret/($n*100)}else{0}
  "{0,-6} {1,4} {2,6:P1} {3,6:P1} {4,7:P1} {5,7:P1}" -f ("f$($x.feat)/$($x.yr)"),$n,([double]$x.wins/$n),([double]$x.top3/$n),$tan,$fuku
  $k=[int]$x.feat; if(-not $agg.ContainsKey($k)){$agg[$k]=@{n=0;w=0;t3=0;tr=0;fr=0}}
  $agg[$k].n+=$n;$agg[$k].w+=[int]$x.wins;$agg[$k].t3+=[int]$x.top3;$agg[$k].tr+=[double]$x.tan_ret;$agg[$k].fr+=[double]$x.fuku_ret
}
'-'*58
foreach($k in 1,0){ if($agg.ContainsKey($k)){ $a=$agg[$k]; "{0,-6} {1,4} {2,6:P1} {3,6:P1} {4,7:P1} {5,7:P1}  ← 全年計" -f ("feat$k"),$a.n,($a.w/$a.n),($a.t3/$a.n),($a.tr/($a.n*100)),($a.fr/($a.n*100)) } }
$cn.Close()
