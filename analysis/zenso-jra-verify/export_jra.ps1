# JRA data export to 前走同条件パッケージ CSV schema
$ErrorActionPreference='Stop'
$cfg = (Get-Content 'C:\jra\共通\appsettings.json' -Raw -Encoding UTF8 | ConvertFrom-Json)
$cs = $cfg.ConnectionStrings.DefaultConnection
$out = 'C:\jra\analysis\zenso-jra-verify\jra_csv'
New-Item -ItemType Directory -Force $out | Out-Null

function Export-Query($sql, $file, $headers) {
  $cn = New-Object System.Data.SqlClient.SqlConnection $cs
  $cn.Open()
  $cmd = $cn.CreateCommand(); $cmd.CommandText=$sql; $cmd.CommandTimeout=600
  $r = $cmd.ExecuteReader()
  $sw = New-Object System.IO.StreamWriter($file, $false, (New-Object System.Text.UTF8Encoding($true)))
  $sw.WriteLine(($headers -join ','))
  $nf = $r.FieldCount
  $sb = New-Object System.Text.StringBuilder
  while($r.Read()){
    [void]$sb.Clear()
    for($i=0;$i -lt $nf;$i++){
      if($i -gt 0){[void]$sb.Append(',')}
      $v = $r.GetValue($i)
      if($v -eq $null -or $v -is [System.DBNull]){ continue }
      $s = [string]$v
      if($s.IndexOfAny([char[]]@(',','"',"`n","`r")) -ge 0){
        $s = '"' + $s.Replace('"','""') + '"'
      }
      [void]$sb.Append($s)
    }
    $sw.WriteLine($sb.ToString())
  }
  $sw.Close(); $r.Close(); $cn.Close()
  "{0}: {1}" -f (Split-Path $file -Leaf), ((Get-Content $file | Measure-Object -Line).Lines - 1)
}

# 1) History: 競走結果 + 距離(レース情報) + 頭数(count) : 全期間(前3走用)
$histSql = @"
SELECT k.馬名, k.開催場所, CONVERT(varchar,k.開催日,23) AS 開催日, k.レース番号,
       ri.距離, k.着順, k.走破時計,
       COUNT(*) OVER (PARTITION BY k.開催日,k.開催場所,k.レース番号) AS 頭数,
       k.一コーナー, k.二コーナー, k.三コーナー, k.四コーナー, '' AS 血統登録番号
FROM dbo.競走結果 k
JOIN dbo.レース情報 ri ON ri.開催日=k.開催日 AND ri.開催場所=k.開催場所 AND ri.レース番号=k.レース番号 AND ri.馬番=k.馬番
WHERE k.開催日 BETWEEN '2021-06-01' AND '2025-12-31' AND k.馬名 IS NOT NULL AND k.馬名<>''
"@
Export-Query $histSql "$out\vw_競走結果統合.csv" @('馬名','開催場所','開催日','レース番号','距離','着順','走破時計','頭数','一コーナー','二コーナー','三コーナー','四コーナー','血統登録番号')

# 2) Entries: レース情報 (target 2023-2025)
$entSql = @"
SELECT CONVERT(varchar,開催日,23) AS 開催日, 開催場所, レース番号, 馬番, 距離, 馬名, '' AS 血統登録番号, 発走時刻, 競走名
FROM dbo.レース情報
WHERE 開催日 BETWEEN '2023-01-01' AND '2025-12-31' AND 馬名 IS NOT NULL AND 馬名<>''
"@
Export-Query $entSql "$out\レース情報.csv" @('開催日','開催場所','レース番号','馬番','距離','馬名','血統登録番号','発走時刻','競走名')

# 3) Compi (target 2023-2025)
$compiSql = @"
SELECT CONVERT(varchar,開催日,23) AS 開催日, 開催場所, レース番号, 馬番, 馬名, 指数, 指数順位, 頭数, CONVERT(varchar,取得日時,120) AS 取得日時, Id
FROM dbo.コンピ指数
WHERE 開催日 BETWEEN '2023-01-01' AND '2025-12-31'
"@
Export-Query $compiSql "$out\コンピ指数.csv" @('開催日','開催場所','レース番号','馬番','馬名','指数','指数順位','頭数','取得日時','Id')

# 4) JRA config: validated_cells = distinct (venue,distance) 2023-2025
$cn = New-Object System.Data.SqlClient.SqlConnection $cs; $cn.Open()
$cmd=$cn.CreateCommand(); $cmd.CommandText="SELECT DISTINCT 開催場所, 距離 FROM dbo.レース情報 WHERE 開催日 BETWEEN '2023-01-01' AND '2025-12-31' AND 距離 IS NOT NULL ORDER BY 開催場所,距離"
$r=$cmd.ExecuteReader(); $cells=@(); while($r.Read()){ $cells += ,@($r[0],[int]$r[1]) }; $r.Close(); $cn.Close()
$base = Get-Content 'C:\jra\analysis\zenso-jra-verify\package\前走同条件_完全再現パッケージ_20260711\config\samecond_v3.json' -Raw | ConvertFrom-Json
$obj = [ordered]@{}
foreach($p in $base.PSObject.Properties){ $obj[$p.Name]=$p.Value }
$obj['validated_cells'] = $cells
$obj['exclude_history_venue'] = '___none___'
$obj | ConvertTo-Json -Depth 5 | Set-Content "$out\samecond_jra.json" -Encoding UTF8
"cells: $($cells.Count)"

# 5) Zip
$zip = 'C:\jra\analysis\zenso-jra-verify\jra_input.zip'
if(Test-Path $zip){ Remove-Item $zip }
Compress-Archive -Path "$out\vw_競走結果統合.csv","$out\レース情報.csv","$out\コンピ指数.csv" -DestinationPath $zip
"ZIP: $zip"
"DONE"
