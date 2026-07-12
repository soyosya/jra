$ErrorActionPreference='Stop'
$cfg = (Get-Content 'C:\jra\共通\appsettings.json' -Raw -Encoding UTF8 | ConvertFrom-Json)
$cn=New-Object System.Data.SqlClient.SqlConnection $cfg.ConnectionStrings.DefaultConnection;$cn.Open()
$cmd=$cn.CreateCommand();$cmd.CommandTimeout=300
$cmd.CommandText=@"
SELECT CONVERT(varchar,開催日,23) 開催日,開催場所,レース番号,組番,金額
FROM dbo.払戻金 WHERE 開催日 BETWEEN '2023-01-01' AND '2025-12-31' AND 馬券=N'ワイド'
"@
$r=$cmd.ExecuteReader()
$sw=New-Object System.IO.StreamWriter('C:\jra\analysis\zenso-jra-verify\jra_csv\wide.csv',$false,(New-Object System.Text.UTF8Encoding($true)))
$sw.WriteLine('開催日,開催場所,レース番号,組番,金額')
$c=0;while($r.Read()){ $sw.WriteLine(("{0},{1},{2},{3},{4}" -f $r[0],$r[1],$r[2],$r[3],$r[4]));$c++ }
$sw.Close();$r.Close();$cn.Close()
"wide.csv rows=$c"