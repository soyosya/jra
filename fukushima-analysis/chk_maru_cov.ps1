[Console]::OutputEncoding=[Text.Encoding]::UTF8
$cs=(Get-Content 'C:\jra\共通\appsettings.json' -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
$cn=New-Object System.Data.SqlClient.SqlConnection $cs;$cn.Open();$c=$cn.CreateCommand()
"=== 厩舎の話 年別: 全行 / 印◎ / ◎かつ結果あり ==="
$c.CommandText=@"
SELECT YEAR(h.開催日) y, COUNT(*) total,
  SUM(CASE WHEN h.印=N'◎' THEN 1 ELSE 0 END) maru,
  SUM(CASE WHEN h.印=N'◎' AND EXISTS(SELECT 1 FROM dbo.競走結果 k WHERE k.開催日=h.開催日 AND k.開催場所=h.開催場所 AND k.レース番号=h.レース番号 AND k.馬名=h.馬名 AND TRY_CONVERT(int,k.着順)>0) THEN 1 ELSE 0 END) maru_res
FROM dbo.厩舎の話 h GROUP BY YEAR(h.開催日) ORDER BY y
"@
$r=$c.ExecuteReader();while($r.Read()){Write-Output ("  "+$r['y']+": 全"+$r['total']+" / 印◎"+$r['maru']+" / ◎結果あり"+$r['maru_res'])};$r.Close()
"--- 厩舎◎ 月別(2025-2026) ---"
$c.CommandText="SELECT YEAR(開催日)*100+MONTH(開催日) ym,COUNT(*) n FROM dbo.厩舎の話 WHERE 印=N'◎' AND 開催日>='2025-01-01' GROUP BY YEAR(開催日)*100+MONTH(開催日) ORDER BY ym"
$r=$c.ExecuteReader();$s=@();while($r.Read()){$s+=($r['ym'].ToString()+":"+$r['n'])};$r.Close(); Write-Output ("  "+($s -join " "))
"--- コンピ指数 年別(厩舎◎をコンピ順位で絞るため) ---"
$c.CommandText="SELECT YEAR(開催日) y,COUNT(DISTINCT 開催日) d FROM dbo.コンピ指数 GROUP BY YEAR(開催日) ORDER BY y"
$r=$c.ExecuteReader();while($r.Read()){Write-Output ("  "+$r['y']+": コンピ開催日"+$r['d'])};$r.Close()
$cn.Close()
