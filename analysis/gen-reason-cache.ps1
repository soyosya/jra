# 指定 -Date -Venue の選定理由キャッシュ(C:\temp\jra_reason_<ymd>_<場>.json)を強制再生成する。
# reason-warm.ps1 の中核を単体化(25分スキップ無し・1場のみ)。jra-card現行=相手フロア置換版で評価。
param([Parameter(Mandatory=$true)][string]$Date,[Parameter(Mandatory=$true)][string]$Venue,[switch]$Force)
$cardPs='C:\jra\tools\jra-card.ps1'
$ymd=($Date -replace '-','')
$cf="C:\temp\jra_reason_${ymd}_${Venue}.json"
if((Test-Path $cf) -and -not $Force){ Write-Output "既存(スキップ): $cf"; return }
$byRace=@{}
$lines = & $cardPs -Date $Date -Venue $Venue -ExportBets -ExportHorses 2>$null
foreach($ln in $lines){ $t="$ln"
  if($t -like 'HORSE|*'){ $f=$t -split '\|'; if($f.Count -ge 6){ $rr=$f[1]; if(-not $byRace.ContainsKey($rr)){$byRace[$rr]=@{horses=@{};axis='';axisLab='';partners=''}}; $byRace[$rr].horses[$f[2]]=@{eval=$f[3];compi=$f[4];sougou=$f[5]} } }
  elseif($t -like 'EXPORT|*'){ $f=$t -split '\|'; if($f.Count -ge 6){ $rr=$f[1]; if(-not $byRace.ContainsKey($rr)){$byRace[$rr]=@{horses=@{};axis='';axisLab='';partners=''}}; $byRace[$rr].axis=$f[3]; $byRace[$rr].axisLab=$f[4]; $byRace[$rr].partners=$f[5] } }
}
if($byRace.Count -gt 0){ ($byRace|ConvertTo-Json -Depth 6 -Compress)|Out-File $cf -Encoding UTF8; Write-Output "生成: $cf ($($byRace.Count)R)" } else { Write-Output "警告: データ無し $Date $Venue" }
