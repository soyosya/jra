# 汎用: 指定フォルダの retro-2025-*.txt(完全データ)を そのフォルダの retro-detail.md にデータ部として日別取込。
param([Parameter(Mandatory)][string]$Dir)
$dst=Join-Path $Dir 'retro-detail.md'
$nl="`r`n"
$files=@(Get-ChildItem (Join-Path $Dir 'retro-2025-*.txt') | Sort-Object Name)
$wmap=@{Sunday='日';Monday='月';Tuesday='火';Wednesday='水';Thursday='木';Friday='金';Saturday='土'}
$sb=New-Object System.Text.StringBuilder
[void]$sb.Append($nl+"# ========== 完全データ(全日・全12R) =========="+$nl)
$n=0
foreach($f in $files){ $n++
  $d=[regex]::Match($f.Name,'(\d{4}-\d{2}-\d{2})').Groups[1].Value
  $w=$wmap[[datetime]::Parse($d).DayOfWeek.ToString()]
  $lines=Get-Content $f.FullName -Encoding UTF8
  $body=($lines | Where-Object{ $_ -notmatch '^=== JRA統合カード' -and $_ -notmatch '^##########' }) -join $nl
  [void]$sb.Append($nl+"---"+$nl+"## ${n}日目 ${d}（${w}） 完全データ"+$nl+'```'+$nl+$body.Trim()+$nl+'```'+$nl)
}
Add-Content -Path $dst -Value $sb.ToString() -Encoding UTF8
"取込: $Dir ${n}日 → " + ((Get-Content $dst|Measure-Object -Line).Lines) + "行 / " + ((Select-String -Path $dst -Pattern '^=====').Count) + "R"
