# バックテスト用: 未生成キャッシュ(2025函館3日・2025福島8日)を並列生成(throttle5)。
$helper='C:\Users\suzukih\AppData\Local\Temp\claude\C--temp\7e8ddbe8-2aa5-43e9-8247-e32904cfe108\scratchpad\jracard-cache.ps1'
$jobs=@(
 @('2025-07-13','函館'),@('2025-07-19','函館'),@('2025-07-20','函館'),
 @('2025-06-28','福島'),@('2025-06-29','福島'),@('2025-07-05','福島'),@('2025-07-06','福島'),
 @('2025-07-12','福島'),@('2025-07-13','福島'),@('2025-07-19','福島'),@('2025-07-20','福島')
)
$jobs | ForEach-Object -ThrottleLimit 5 -Parallel {
  $d=$_[0];$v=$_[1]; $h=$using:helper
  try{ & 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -File $h -Date $d -Venue $v 2>$null | Out-Null; Write-Output "done $d $v" }catch{ Write-Output "ERR $d $v" }
}
Write-Output "ALL_DONE"
