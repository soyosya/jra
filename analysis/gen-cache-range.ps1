# 指定期間の全(開催日×場)の選定理由キャッシュを生成(調教backfill後の完全データ前提)。最大N並列・-Forceで再生成。
param([Parameter(Mandatory=$true)][string]$From,[Parameter(Mandatory=$true)][string]$To,[int]$Par=4,[switch]$Force)
$ps='C:\Program Files\PowerShell\7\pwsh.exe'
$cs=(Get-Content 'C:\jra\共通\appsettings.json' -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
$cn=New-Object System.Data.SqlClient.SqlConnection $cs; $cn.Open()
$c=$cn.CreateCommand(); $c.CommandText="SELECT DISTINCT CONVERT(varchar(10),開催日,120) d, 開催場所 v FROM dbo.レース情報 WHERE 開催日 BETWEEN @f AND @t ORDER BY 開催場所"
[void]$c.Parameters.AddWithValue('@f',$From); [void]$c.Parameters.AddWithValue('@t',$To)
$r=$c.ExecuteReader(); $pairs=@(); while($r.Read()){ $pairs+=,@($r['d'],$r['v']) }; $r.Close(); $cn.Close()
Write-Output "対象 $($pairs.Count) venue-day ($From..$To) 並列$Par"
$fArg = if($Force){'-Force'}else{''}
$sb={ param($ps,$d,$v,$fArg) $a=@('-NoProfile','-File','C:\jra\analysis\gen-reason-cache.ps1','-Date',$d,'-Venue',$v); if($fArg){$a+=$fArg}; & $ps @a }
$i=0
while($i -lt $pairs.Count){
  $batch=@()
  for($j=0;$j -lt $Par -and $i -lt $pairs.Count;$j++,$i++){ $batch += Start-Job -ScriptBlock $sb -ArgumentList $ps,$pairs[$i][0],$pairs[$i][1],$fArg }
  $batch | Wait-Job -Timeout 900 | Out-Null
  $batch | ForEach-Object { Receive-Job $_ }; $batch | Remove-Job
}
Write-Output "CACHE_RANGE_DONE $From..$To"
