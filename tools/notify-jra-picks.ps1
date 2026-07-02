<#
.SYNOPSIS
  中央競馬: 当日の各開催場の jra-card(◎軸/○相手)をまとめてメール通知する。
.DESCRIPTION
  対象日のレース情報(出馬表)から開催場を発見し、各場で jra-card.ps1 -Notify を実行して
  「各レースの軸/相手」を1行ずつ収集 → 1通のメールに整形して Send-Mail(Graph API)で送信。
  事前に対象日の fetch-jra-range(出馬表)/fetch-danwa/fetch-cyokyo/fetch-compi が必要(無い項目は欠落のまま)。
.PARAMETER Date    既定=当日(yyyy-MM-dd)。
.PARAMETER DryRun  送信せず件名/本文を標準出力に表示(確認用)。
#>
[CmdletBinding()]
param([string]$Date=(Get-Date).ToString('yyyy-MM-dd'),[string]$Venue='',[int]$Race=0,[switch]$DryRun)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'mail-lib.ps1')

$appsettings = Join-Path $PSScriptRoot '..\共通\appsettings.json'
$connStr = (Get-Content $appsettings -Raw -Encoding UTF8 | ConvertFrom-Json).ConnectionStrings.DefaultConnection
$conn = New-Object System.Data.SqlClient.SqlConnection($connStr); $conn.Open()
$cmd=$conn.CreateCommand(); $cmd.CommandText="SELECT DISTINCT 開催場所 FROM レース情報 WHERE 開催日=@d ORDER BY 開催場所"
[void]$cmd.Parameters.AddWithValue('@d',$Date)
$r=$cmd.ExecuteReader(); $venues=@(); while($r.Read()){ $venues+=[string]$r['開催場所'] }; $r.Close(); $conn.Close()
if($Venue){ $venues=@($venues | Where-Object { $_ -eq $Venue }) }   # -Venue指定で1場に絞る(ループの次レース再通知用)

if($venues.Count -eq 0){
  $subj="【中央競馬】本日の軸 {0}: 対象なし" -f $Date
  $body="{0} のレース情報(出馬表)が未取得です。fetch-jra-range 等を先に実行してください。" -f $Date
  if($DryRun){ "$subj`n`n$body" } else { Send-Mail $subj $body; "送信: $subj" }
  return
}

$card = Join-Path $PSScriptRoot 'jra-card.ps1'
$body = "中央競馬 本日の軸/相手   {0}`n" -f $Date
$body += "凡例: ◎堅軸/◎軸強=堅い本命, 安=コンピ安定上位/安★=3走平均指数も高く最堅(確度up), 信=コンピ指数2走連続上昇(確度up・複勝+5〜7pt), ↗=調教上昇/↗↗=過去3走持続上昇(確度up), ◎軸弱・注危・△危・▼降・▽調=割引(▼降=2走でコンピ指数大幅下降, ▽調=調教短評ネガ, ▽話=厩舎の話コメント悪化), ★=上り連続好調, 格=コンピ格上挑戦, ▽後=前残り場で後方脚質の本命(函館で割引)`n`n"
foreach($v in $venues){
  $lines = & $card -Date $Date -Venue $v -Notify 2>$null
  $lines = @($lines | Where-Object { "$_".Trim() -ne '' })
  if($Race -gt 0){ $lines = @($lines | Where-Object { "$_" -match ('^\s*{0}R\(' -f $Race) }) }   # -Raceで該当レース行だけ
  $body += "■ {0} ({1}R)`n{2}`n`n" -f $v,$lines.Count,(($lines) -join "`n")
}
$subj = if($Race -gt 0){ "【中央競馬】{0} {1}R 最新買目 {2}" -f ($venues -join '/'),$Race,$Date } else { "【中央競馬】本日の軸 {0} ({1})" -f $Date,($venues -join '/') }
if($DryRun){ "----- 件名 -----`n$subj`n`n----- 本文 -----`n$body" }
else { Send-Mail $subj $body; "送信しました: $subj" }
