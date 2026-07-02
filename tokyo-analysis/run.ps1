param([Parameter(Mandatory=$true)][string]$File)
$ErrorActionPreference='Stop'
$cs = (Get-Content 'C:\jra\共通\appsettings.json' -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
$sql = [IO.File]::ReadAllText($File, [Text.UTF8Encoding]::new($false))
$conn = New-Object System.Data.SqlClient.SqlConnection($cs)
$conn.Open()
try {
  $c = $conn.CreateCommand(); $c.CommandTimeout = 180; $c.CommandText = $sql
  $a = New-Object System.Data.SqlClient.SqlDataAdapter($c)
  $ds = New-Object System.Data.DataSet
  [void]$a.Fill($ds)
  foreach ($t in $ds.Tables) { $t | Format-Table -AutoSize | Out-String -Width 200 | Write-Output; '' }
} finally { $conn.Close() }
