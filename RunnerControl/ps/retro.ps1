# 指定日の「日次総括＋深掘り一覧」(JSON)。読み取り専用。
# 源: C:\jra\reasons\<date>\_総括.md(総括) と 同フォルダの <場>_<R>.md(各レース深掘り、先頭行=見出し)。
param([string]$Date='')
$OutputEncoding=[Console]::OutputEncoding=[System.Text.Encoding]::UTF8
$ErrorActionPreference='SilentlyContinue'
$root='C:\jra\reasons'
# 利用可能な日付(フォルダ)一覧・降順
$dates=@()
if(Test-Path $root){ $dates=@(Get-ChildItem $root -Directory | Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}$' } | Sort-Object Name -Descending | ForEach-Object { $_.Name }) }
$date= if($Date -and ($Date -match '^\d{4}-\d{2}-\d{2}$')){$Date} elseif($dates.Count -gt 0){$dates[0]} else {(Get-Date -Format 'yyyy-MM-dd')}
$dir=Join-Path $root $date

$summary=''
$sf=Join-Path $dir '_総括.md'
if(Test-Path $sf){ $summary=Get-Content $sf -Raw -Encoding UTF8 }

# 各レース深掘り: <場>_<R>.md。ファイル名の最後の'_'で場とRを分割。先頭の見出し行をタイトルに。
$races=@()
if(Test-Path $dir){
  foreach($f in (Get-ChildItem $dir -Filter '*.md' | Where-Object { $_.Name -ne '_総括.md' })){
    $base=$f.BaseName; $i=$base.LastIndexOf('_'); if($i -lt 1){ continue }
    $venue=$base.Substring(0,$i); $rstr=$base.Substring($i+1)
    $rno=0; if(-not [int]::TryParse(($rstr -replace '[^0-9]',''),[ref]$rno)){ continue }
    $head=''; foreach($ln in (Get-Content $f.FullName -Encoding UTF8)){ $t="$ln".Trim(); if($t -ne ''){ $head=($t -replace '^#\s*',''); break } }
    $races += [ordered]@{ venue=$venue; race=$rno; title=$head }
  }
}
$races=@($races | Sort-Object venue,{[int]$_.race})

[ordered]@{ date=$date; dates=$dates; summary=$summary; races=$races; count=$races.Count } | ConvertTo-Json -Depth 5 -Compress
