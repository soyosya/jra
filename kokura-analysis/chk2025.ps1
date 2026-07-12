[Console]::OutputEncoding=[Text.Encoding]::UTF8
$cs='Server=192.168.168.81\SQLEXPRESS;Database=中央競馬;User Id=sa;Password=Hanasaki#2093;TrustServerCertificate=True;'
$cn=New-Object System.Data.SqlClient.SqlConnection $cs;$cn.Open()
function Q($sql){ $c=$cn.CreateCommand();$c.CommandText=$sql;$dt=New-Object System.Data.DataTable;(New-Object System.Data.SqlClient.SqlDataAdapter $c).Fill($dt)|Out-Null;,$dt.Rows }
$V=[char]0x5c0f+[char]0x5009
"=== 小倉 2025-06〜07 の開催日(レース数/結果/コンピ/オッズ人気の有無) ==="
$sql=@"
SELECT CONVERT(varchar(10),ri.開催日,23) d,
 COUNT(DISTINCT ri.レース番号) races,
 (SELECT COUNT(DISTINCT レース番号) FROM dbo.競走結果 k WHERE k.開催日=ri.開催日 AND k.開催場所=ri.開催場所 AND TRY_CONVERT(int,k.着順)>0) res,
 (SELECT COUNT(DISTINCT レース番号) FROM dbo.コンピ指数 c WHERE c.開催日=ri.開催日 AND c.開催場所=ri.開催場所) compi,
 (SELECT COUNT(*) FROM dbo.リアルタイムオッズ o WHERE o.開催日=ri.開催日 AND o.開催場所=ri.開催場所 AND o.人気 IS NOT NULL) oddspop
FROM dbo.レース情報 ri
WHERE ri.開催場所=N'$V' AND ri.開催日 BETWEEN '2025-06-15' AND '2025-07-20'
GROUP BY ri.開催日,ri.開催場所 ORDER BY ri.開催日
"@
foreach($x in (Q $sql)){ "  {0}  レース{1}  結果{2}  コンピ{3}  オッズ人気行{4}" -f $x.d,$x.races,$x.res,$x.compi,$x.oddspop }
$cn.Close()
