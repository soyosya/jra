# JRA「選定理由」評価キャッシュ・ウォーマー。当日の各開催場で jra-card -ExportBets -ExportHorses を実行し
# C:\temp\jra_reason_<ymd>_<場>.json(各レース HORSE評価/総合 + EXPORT軸/相手) を生成。reason.ps1 はこれを読むだけ。
# jra-cardは場一括で約150秒級のため、①25分以内に更新済の場はスキップ ②1回の起動で最大1場だけ更新(CPU平準化)。
# RunnerControl のバックグラウンドループが定期起動する(自動精算ループと同方式)。
param([string]$Date='')
$OutputEncoding=[Console]::OutputEncoding=[System.Text.Encoding]::UTF8
$ErrorActionPreference='SilentlyContinue'
$date= if($Date){$Date}else{(Get-Date -Format 'yyyy-MM-dd')}; $ymd=($date -replace '[^0-9]','')
$cardPs='C:\jra\tools\jra-card.ps1'
$cs=(Get-Content 'C:\jra\共通\appsettings.json' -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
$cn=New-Object System.Data.SqlClient.SqlConnection $cs; $cn.Open()
$c=$cn.CreateCommand(); $c.CommandText="SELECT DISTINCT 開催場所 FROM レース情報 WHERE 開催日=@d ORDER BY 開催場所"; [void]$c.Parameters.AddWithValue('@d',$date)
$r=$c.ExecuteReader(); $venues=@(); while($r.Read()){ $venues+=[string]$r['開催場所'] }; $r.Close(); $cn.Close()
if($venues.Count -eq 0){ '{"ok":true,"warmed":0,"note":"非開催"}'; return }
$warmed=0; $target=''
foreach($v in $venues){
  $cf="C:\temp\jra_reason_${ymd}_${v}.json"
  if(Test-Path $cf){ $age=((Get-Date)-(Get-Item $cf).LastWriteTime).TotalSeconds; if($age -lt 1500){ continue } }  # 25分以内は再利用
  $byRace=@{}
  try{
    $lines = & $cardPs -Date $date -Venue $v -ExportBets -ExportHorses 2>$null
    foreach($ln in $lines){ $t="$ln"
      if($t -like 'HORSE|*'){ $f=$t -split '\|'; if($f.Count -ge 6){ $rr=$f[1]; if(-not $byRace.ContainsKey($rr)){$byRace[$rr]=@{horses=@{};axis='';axisLab='';partners=''}}; $byRace[$rr].horses[$f[2]]=@{eval=$f[3];compi=$f[4];sougou=$f[5]} } }
      elseif($t -like 'EXPORT|*'){ $f=$t -split '\|'; if($f.Count -ge 6){ $rr=$f[1]; if(-not $byRace.ContainsKey($rr)){$byRace[$rr]=@{horses=@{};axis='';axisLab='';partners=''}}; $byRace[$rr].axis=$f[3]; $byRace[$rr].axisLab=$f[4]; $byRace[$rr].partners=$f[5] } }
    }
    if($byRace.Count -gt 0){ ($byRace|ConvertTo-Json -Depth 6 -Compress)|Out-File $cf -Encoding UTF8; $warmed++; $target=$v; break }  # 1回1場のみ
  }catch{}
}
"{`"ok`":true,`"warmed`":$warmed,`"venue`":`"$target`",`"date`":`"$date`"}"
