# 2026-07-05 最終レース(小倉12R=最遅16:30)の確定を待つ。3場の12Rすべてに払戻金が入ったら終了。
$cs=(Get-Content 'C:\jra\共通\appsettings.json' -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
function Cnt($sql){ $cn=New-Object System.Data.SqlClient.SqlConnection $cs; $cn.Open(); $c=$cn.CreateCommand(); $c.CommandText=$sql; $n=[int]$c.ExecuteScalar(); $cn.Close(); $n }
$deadline=(Get-Date).AddHours(3)
while((Get-Date) -lt $deadline){
  $n=Cnt "SELECT COUNT(DISTINCT 開催場所) FROM dbo.払戻金 WHERE 開催日='2026-07-05' AND レース番号=12 AND 開催場所 IN (N'函館',N'福島',N'小倉')"
  if($n -ge 3){ Write-Output ("CONFIRMED 3場12R確定 "+(Get-Date -Format 'HH:mm')); exit 0 }
  Write-Output ("待機中: 12R確定 $n/3場 "+(Get-Date -Format 'HH:mm'))
  Start-Sleep -Seconds 300
}
Write-Output "TIMEOUT 3時間経過"; exit 0
