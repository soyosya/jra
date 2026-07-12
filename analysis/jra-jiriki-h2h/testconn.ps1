$cfg=(Get-Content 'C:\jra\共通\appsettings.json' -Raw -Encoding UTF8|ConvertFrom-Json); $cs=$cfg.ConnectionStrings.DefaultConnection
$conn=New-Object System.Data.SqlClient.SqlConnection($cs); $conn.Open()
$cmd=$conn.CreateCommand()
$cmd.CommandText=@"
SELECT YEAR(開催日) AS y,
 COUNT(*) AS c_result,
 SUM(CASE WHEN 走破時計>0 THEN 1 ELSE 0 END) AS c_time
FROM dbo.競走結果 GROUP BY YEAR(開催日) ORDER BY y
"@
$r=$cmd.ExecuteReader(); while($r.Read()){ "{0}  result={1}  time={2}" -f $r['y'],$r['c_result'],$r['c_time'] }; $r.Close()
$conn.Close()
