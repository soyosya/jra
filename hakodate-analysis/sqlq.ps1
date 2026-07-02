param([string]$Sql)
$cs = (Get-Content 'C:\jra\共通\appsettings.json' -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
$cn = New-Object System.Data.SqlClient.SqlConnection $cs
$cn.Open()
$cmd = $cn.CreateCommand(); $cmd.CommandText = $Sql; $cmd.CommandTimeout=120
$da = New-Object System.Data.SqlClient.SqlDataAdapter $cmd
$ds = New-Object System.Data.DataSet
$da.Fill($ds) | Out-Null
foreach($t in $ds.Tables){
  $t | Format-Table -AutoSize | Out-String -Width 4000 | Write-Output
  "----"
}
$cn.Close()
