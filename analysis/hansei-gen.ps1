# 昨年同開催(2025-06-28/29 小倉・福島・函館)のカードを ExportBets+ExportHorses で生成→ファイル保存。
$card='C:\jra\tools\jra-card.ps1'
$outdir='C:\jra\analysis\hansei-2025'
if(-not (Test-Path $outdir)){ New-Item -ItemType Directory -Path $outdir | Out-Null }
foreach($d in '2025-06-28','2025-06-29'){ foreach($v in '小倉','福島','函館'){
  $out=Join-Path $outdir ("{0}_{1}.txt" -f $v,($d -replace '-',''))
  $lines = & 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -File $card -Venue $v -Date $d -ExportBets -ExportHorses 2>$null
  ($lines | Where-Object { $_ -match '^(HORSE|EXPORT)\|' }) | Set-Content -Path $out -Encoding UTF8
  Write-Host ("{0} {1}: {2}行" -f $v,$d,(@($lines | Where-Object { $_ -match '^(HORSE|EXPORT)\|' }).Count))
} }
Write-Host 'GEN_DONE'
