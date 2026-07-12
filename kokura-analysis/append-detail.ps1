# 第2回小倉2025 全8日の retro-<date>.txt 完全データを retro-detail.md にデータ部として一括取込(順序固定)
$dst='C:\jra\kokura-analysis\retro-detail.md'
$nl="`r`n"
$days=@(
  @{n=1;d='2025-06-28';w='土'},@{n=2;d='2025-06-29';w='日'},@{n=3;d='2025-07-05';w='土'},@{n=4;d='2025-07-06';w='日'},
  @{n=5;d='2025-07-12';w='土'},@{n=6;d='2025-07-13';w='日'},@{n=7;d='2025-07-19';w='土'},@{n=8;d='2025-07-20';w='日'}
)
$sb=New-Object System.Text.StringBuilder
[void]$sb.Append($nl+"# ========== 完全データ(全8日・全12R) =========="+$nl)
foreach($x in $days){
  $f="C:\jra\kokura-analysis\retro-$($x.d).txt"
  if(-not (Test-Path $f)){ Write-Output "MISSING $f"; continue }
  $lines=Get-Content $f -Encoding UTF8
  $body=($lines | Where-Object{ $_ -notmatch '^=== JRA統合カード' -and $_ -notmatch '^##########' }) -join $nl
  [void]$sb.Append($nl+"---"+$nl)
  [void]$sb.Append("## 第2回小倉 $($x.n)日目 $($x.d)（$($x.w)） 完全データ"+$nl)
  [void]$sb.Append('```'+$nl+$body.Trim()+$nl+'```'+$nl)
}
Add-Content -Path $dst -Value $sb.ToString() -Encoding UTF8
"取込完了。retro-detail.md 行数: " + (Get-Content $dst | Measure-Object -Line).Lines + " / レースブロック: " + ((Select-String -Path $dst -Pattern '^=====').Count)
