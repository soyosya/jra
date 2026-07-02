# JRAライブ中継(sp.gch.jp/jra)をサーバの可視Chromeで開く。IpatVote live [会場名]。
# ★動画はサーバ機(192.168.168.81)のデスクトップに表示される(スマホ不可)。実金操作なし(視聴のみ)。
param([string]$Venue='')
$OutputEncoding=[Console]::OutputEncoding=[System.Text.Encoding]::UTF8
$exe='C:\jra\IpatVote\bin\Release\net10.0\IpatVote.exe'
if(-not (Test-Path $exe)){ Write-Output 'NG: IpatVote.exe が見つかりません(要ビルド)'; exit 1 }
try{
  $out = & $exe live $Venue 2>&1 | Out-String
  Write-Output ("OK: サーバのデスクトップでライブ(sp.gch.jp/jra)を開きました。" + "`n" + $out.Trim())
}catch{ Write-Output "NG: $($_.Exception.Message)" }
