$ErrorActionPreference='Stop'
$cfg = (Get-Content 'C:\jra\共通\appsettings.json' -Raw -Encoding UTF8 | ConvertFrom-Json)
$cs = $cfg.ConnectionStrings.DefaultConnection
$file = 'C:\jra\analysis\zenso-jra-verify\jra_csv\target_outcomes.csv'
$sql = @"
SELECT CONVERT(varchar,k.開催日,23) AS 開催日, k.開催場所, k.レース番号, ri.距離, k.馬番, k.馬名, k.着順,
       n.頭数, ci.指数順位, tan.金額 AS 単勝, fuk.金額 AS 複勝
FROM dbo.競走結果 k
JOIN dbo.レース情報 ri ON ri.開催日=k.開催日 AND ri.開催場所=k.開催場所 AND ri.レース番号=k.レース番号 AND ri.馬番=k.馬番
JOIN (SELECT 開催日,開催場所,レース番号,COUNT(*) AS 頭数 FROM dbo.競走結果 GROUP BY 開催日,開催場所,レース番号) n
     ON n.開催日=k.開催日 AND n.開催場所=k.開催場所 AND n.レース番号=k.レース番号
OUTER APPLY (SELECT TOP 1 指数順位 FROM dbo.コンピ指数 c
     WHERE c.開催日=k.開催日 AND c.開催場所=k.開催場所 AND c.レース番号=k.レース番号 AND c.馬番=k.馬番
     ORDER BY c.取得日時 DESC, c.Id DESC) ci
OUTER APPLY (SELECT TOP 1 金額 FROM dbo.払戻金 t WHERE t.開催日=k.開催日 AND t.開催場所=k.開催場所 AND t.レース番号=k.レース番号 AND t.馬券=N'単勝' AND t.組番=CAST(k.馬番 AS varchar)) tan
OUTER APPLY (SELECT TOP 1 金額 FROM dbo.払戻金 f WHERE f.開催日=k.開催日 AND f.開催場所=k.開催場所 AND f.レース番号=k.レース番号 AND f.馬券=N'複勝' AND f.組番=CAST(k.馬番 AS varchar)) fuk
WHERE k.開催日 BETWEEN '2023-01-01' AND '2025-12-31' AND ri.コース種別=N'ダ' AND ri.距離>=1700
"@
$cn = New-Object System.Data.SqlClient.SqlConnection $cs; $cn.Open()
$cmd=$cn.CreateCommand(); $cmd.CommandText=$sql; $cmd.CommandTimeout=600
$r=$cmd.ExecuteReader()
$sw=New-Object System.IO.StreamWriter($file,$false,(New-Object System.Text.UTF8Encoding($true)))
$hdr=@(); for($i=0;$i -lt $r.FieldCount;$i++){$hdr+=$r.GetName($i)}; $sw.WriteLine(($hdr -join ','))
$nf=$r.FieldCount; $c=0
while($r.Read()){
  $vals=@()
  for($i=0;$i -lt $nf;$i++){ $v=$r.GetValue($i); if($v -is [System.DBNull]){$vals+=''}else{ $s=[string]$v; if($s.IndexOfAny([char[]]@(',','"'))-ge 0){$s='"'+$s.Replace('"','""')+'"'}; $vals+=$s } }
  $sw.WriteLine($vals -join ','); $c++
}
$sw.Close();$r.Close();$cn.Close()
"target_outcomes.csv rows=$c"