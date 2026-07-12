$cfg=(Get-Content 'C:\jra\共通\appsettings.json' -Raw -Encoding UTF8|ConvertFrom-Json); $cs=$cfg.ConnectionStrings.DefaultConnection
$conn=New-Object System.Data.SqlClient.SqlConnection($cs); $conn.Open()
function Q($sql){ $c=$conn.CreateCommand(); $c.CommandText=$sql; $r=$c.ExecuteReader(); $o=@(); while($r.Read()){ $row=[ordered]@{}; for($i=0;$i -lt $r.FieldCount;$i++){ $row[$r.GetName($i)]=$r.GetValue($i) }; $o+=[pscustomobject]$row }; $r.Close(); $o }
"== コンピ指数 by year =="
Q "SELECT YEAR(開催日) y,COUNT(*) c,SUM(CASE WHEN 指数順位 IS NOT NULL THEN 1 ELSE 0 END) rankc FROM dbo.コンピ指数 GROUP BY YEAR(開催日) ORDER BY y" | Format-Table -Auto
"== 払戻 馬券種別 distinct =="
Q "SELECT DISTINCT 馬券 FROM dbo.払戻金" | Format-Table -Auto
"== 払戻 sample 単勝/複勝 =="
Q "SELECT TOP 8 開催日,開催場所,レース番号,馬券,組番,金額 FROM dbo.払戻金 WHERE 馬券 IN (N'単勝',N'複勝') ORDER BY 開催日 DESC" | Format-Table -Auto
"== レース情報 columns sample =="
Q "SELECT TOP 2 * FROM dbo.レース情報" | Format-List
$conn.Close()
