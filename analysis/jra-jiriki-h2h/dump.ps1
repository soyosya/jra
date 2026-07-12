$cfg=(Get-Content 'C:\jra\共通\appsettings.json' -Raw -Encoding UTF8|ConvertFrom-Json); $cs=$cfg.ConnectionStrings.DefaultConnection
$conn=New-Object System.Data.SqlClient.SqlConnection($cs); $conn.Open()
function DumpCsv($sql,$file){
  $c=$conn.CreateCommand(); $c.CommandText=$sql; $c.CommandTimeout=600
  $r=$c.ExecuteReader()
  $sw=New-Object System.IO.StreamWriter($file,$false,(New-Object System.Text.UTF8Encoding($false)))
  $cols=@(); for($i=0;$i -lt $r.FieldCount;$i++){ $cols+=$r.GetName($i) }
  $sw.WriteLine(($cols -join "`t"))
  $n=0
  while($r.Read()){
    $vals=@(); for($i=0;$i -lt $r.FieldCount;$i++){ $v=$r.GetValue($i); if($v -is [DBNull]){ $vals+='' } elseif($v -is [datetime]){ $vals+=$v.ToString('yyyy-MM-dd') } else { $vals+=([string]$v).Replace("`t"," ").Replace("`r"," ").Replace("`n"," ") } }
    $sw.WriteLine(($vals -join "`t")); $n++
  }
  $sw.Close(); $r.Close()
  "  $file : $n rows"
}
DumpCsv "SELECT 開催日,開催場所,レース番号,馬番,馬名,TRY_CAST(距離 AS int) dist,コース種別 surf FROM dbo.レース情報 WHERE 開催日>='2020-06-01'" "race_info.tsv"
DumpCsv "SELECT 開催日,開催場所,レース番号,馬番,馬名,TRY_CAST(着順 AS int) rank,TRY_CAST(走破時計 AS float) tim,TRY_CAST(四コーナー AS int) c4 FROM dbo.競走結果 WHERE 開催日>='2020-06-01'" "result.tsv"
DumpCsv "SELECT 開催日,開催場所,レース番号,馬番,馬名,指数順位 rankc,頭数 FROM (SELECT *,ROW_NUMBER() OVER(PARTITION BY 開催日,開催場所,レース番号,馬名 ORDER BY 取得日時 DESC) rn FROM dbo.コンピ指数 WHERE 開催日>='2022-01-01') t WHERE rn=1" "compi.tsv"
DumpCsv "SELECT 開催日,開催場所,レース番号,馬券 bet,組番,TRY_CAST(金額 AS float) pay FROM dbo.払戻金 WHERE 開催日>='2022-01-01' AND 馬券 IN (N'単勝',N'複勝')" "payout.tsv"
$conn.Close()
