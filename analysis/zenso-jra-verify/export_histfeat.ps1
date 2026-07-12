$ErrorActionPreference='Stop'
$cfg = (Get-Content 'C:\jra\共通\appsettings.json' -Raw -Encoding UTF8 | ConvertFrom-Json)
$cs = $cfg.ConnectionStrings.DefaultConnection
$file='C:\jra\analysis\zenso-jra-verify\jra_csv\history_feat.csv'
$sql=@"
SELECT k.馬名, k.開催場所, CONVERT(varchar,k.開催日,23) AS 開催日, k.レース番号, ri.距離,
       ri.コース種別, ri.馬場, k.着順, n.頭数, k.一コーナー, k.二コーナー, k.三コーナー, k.四コーナー,
       k.上り3F, k.走破時計, k.一着馬着差タイム
FROM dbo.競走結果 k
JOIN dbo.レース情報 ri ON ri.開催日=k.開催日 AND ri.開催場所=k.開催場所 AND ri.レース番号=k.レース番号 AND ri.馬番=k.馬番
JOIN (SELECT 開催日,開催場所,レース番号,COUNT(*) AS 頭数 FROM dbo.競走結果 GROUP BY 開催日,開催場所,レース番号) n
     ON n.開催日=k.開催日 AND n.開催場所=k.開催場所 AND n.レース番号=k.レース番号
WHERE k.開催日 BETWEEN '2021-06-01' AND '2025-12-31' AND k.馬名 IS NOT NULL AND k.馬名<>''
"@
$cn=New-Object System.Data.SqlClient.SqlConnection $cs;$cn.Open()
$cmd=$cn.CreateCommand();$cmd.CommandText=$sql;$cmd.CommandTimeout=600
$r=$cmd.ExecuteReader()
$sw=New-Object System.IO.StreamWriter($file,$false,(New-Object System.Text.UTF8Encoding($true)))
$hdr=@();for($i=0;$i -lt $r.FieldCount;$i++){$hdr+=$r.GetName($i)};$sw.WriteLine(($hdr -join ','))
$nf=$r.FieldCount;$c=0
while($r.Read()){
  $vals=@();for($i=0;$i -lt $nf;$i++){$v=$r.GetValue($i);if($v -is [System.DBNull]){$vals+=''}else{$s=[string]$v;if($s.IndexOfAny([char[]]@(',','"'))-ge 0){$s='"'+$s.Replace('"','""')+'"'};$vals+=$s}}
  $sw.WriteLine($vals -join ',');$c++
}
$sw.Close();$r.Close();$cn.Close()
"history_feat.csv rows=$c"