<#
.SYNOPSIS
  中央競馬: 地方競馬(keiba-card-full)同形式の「全馬・買い目カード(発走時刻順)」を生成する。
.DESCRIPTION
  各開催場で jra-card.ps1 -NotifyFull を実行し、レース単位ブロック(ヘッダ＋全頭行)を収集。
  全場を発走時刻順に束ね、地方競馬と同じ体裁のテキストにする(印◎○△ + 調教矢印 + コンピ順位(指数) + 人気 + JRAフラグ)。
  事前に対象日の レース情報(出馬表=jra-fetch-shutuba) + fetch-compi + fetch-danwa + fetch-cyokyo が必要。
.PARAMETER Date     対象日。既定=翌日(明日)。
.PARAMETER ExportTxt 出力先パス(省略時は標準出力にテキストを返す)。
.PARAMETER Notify   指定時は mail-lib(Graph)でメール送信。
#>
[CmdletBinding()]
param([string]$Date=((Get-Date).AddDays(1).ToString('yyyy-MM-dd')),[string]$ExportTxt='',[switch]$Notify,[switch]$WithResult)
$ErrorActionPreference='Stop'
$tools=$PSScriptRoot
$card=Join-Path $tools 'jra-card.ps1'
$pwsh=(Get-Command pwsh -ErrorAction SilentlyContinue).Source; if(-not $pwsh){ $pwsh='C:\Program Files\PowerShell\7\pwsh.exe' }

# 開催場の発見(レース情報→無ければコンピ指数)
$cs=(Get-Content (Join-Path $tools '..\共通\appsettings.json') -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
$conn=New-Object System.Data.SqlClient.SqlConnection($cs);$conn.Open()
function Venues($tbl){ $c=$conn.CreateCommand();$c.CommandText="SELECT DISTINCT 開催場所 FROM $tbl WHERE 開催日=@d ORDER BY 開催場所";[void]$c.Parameters.AddWithValue('@d',$Date);$r=$c.ExecuteReader();$v=@();while($r.Read()){$v+=[string]$r['開催場所']};$r.Close();$v }
$venues=@(Venues 'レース情報'); $hasShutuba=$venues.Count -gt 0
if(-not $hasShutuba){ $venues=@(Venues 'コンピ指数') }
$conn.Close()

if($venues.Count -eq 0){
  $msg="{0} の出馬表/コンピ指数が未取得です。jra-fetch-shutuba / fetch-compi を先に。" -f $Date
  if($Notify){ . (Join-Path $tools 'mail-lib.ps1'); Send-Mail ("【中央競馬】本日の買い目 {0}: 対象なし" -f $Date) $msg }
  if($ExportTxt){ [IO.File]::WriteAllText($ExportTxt,$msg,[Text.UTF8Encoding]::new($true)) } else { Write-Output $msg }
  return
}
if(-not $hasShutuba){
  $note="※出馬表(レース情報)が未取得のため、jra-fetch-shutuba を先に実行してください(発走時刻順カードは出馬表が必要)。"
  if($ExportTxt){ [IO.File]::WriteAllText($ExportTxt,$note,[Text.UTF8Encoding]::new($true)) } else { Write-Output $note }
  if($Notify){ . (Join-Path $tools 'mail-lib.ps1'); Send-Mail ("【中央競馬】本日の買い目 {0}: 出馬表未取得" -f $Date) $note }
  return
}

# 各場で -NotifyFull を実行 → レースブロック(先頭が "●|sortkey|見出し")に分割して収集
$blocks=New-Object System.Collections.Generic.List[object]
foreach($v in $venues){
  # 同一プロセスで直接呼ぶ(子プロセス越しの ● 文字化け回避・高速)。Write-Host(=== ヘッダ)は$linesに入らない。
  $lines = if($WithResult){ & $card -Date $Date -Venue $v -NotifyFull -WithResult 2>$null }else{ & $card -Date $Date -Venue $v -NotifyFull 2>$null }
  $cur=$null
  foreach($ln in $lines){
    $s="$ln"
    if($s -like '●|*'){
      if($cur){ $blocks.Add($cur) }
      $p=$s -split '\|',3   # ●, sortkey, 見出し
      $cur=[pscustomobject]@{ key=$p[1]; head=('● '+$p[2]); rows=New-Object System.Collections.Generic.List[string] }
    } elseif($cur -and $s.Trim() -ne ''){
      $cur.rows.Add($s)
    }
  }
  if($cur){ $blocks.Add($cur) }
}

# 発走時刻順に束ねて本文化(地方競馬と同じ体裁)
$L=New-Object System.Collections.Generic.List[string]
$L.Add(("==== {0} 中央競馬 {1}(発走時刻順) ====" -f $Date,$(if($WithResult){'全馬・買い目+確定着順【振り返り】'}else{'全馬・買い目'})))
if($WithResult){ $L.Add("各行の先頭=確定着順(--=取消/中止/除外)。印◎が1〜3着なら軸的中。") }
$L.Add("◎=軸 ○=相手 △=押さえ 消=消 / 印の右=調教矢印(↗上昇 →平行 ↘下降 ・データ無) / 補足=コンピ順位(指数) / 人気 / JRAフラグ")
$L.Add("フラグ: 堅軸=堅い本命 / 強弱=コンピ指数80+/67- / 安(安★)=コンピ安定上位(3走平均指数も高い) / 信=コンピ指数2走連続上昇(信頼,複勝+5〜7pt) / ↗↗=調教3走持続上昇 / 危・注危=危険軸 / 格=格上挑戦 / ▼降=コンピ2走下降 / ▽調=調教短評ネガ / ▽話=厩舎の話コメント悪化(前走強気→今走弱気) / ▼人=人気先行コンピ薄 / ▽後▽逃=脚質割引")
$L.Add("")
foreach($b in ($blocks | Sort-Object key)){
  $L.Add($b.head)
  foreach($r in $b.rows){ $L.Add($r) }
  $L.Add("")
}
$text=($L -join "`r`n")

if($ExportTxt){ [IO.File]::WriteAllText($ExportTxt,$text,[Text.UTF8Encoding]::new($true)); Write-Host ("生成: {0} ({1}ブロック)" -f $ExportTxt,$blocks.Count) }
if($Notify){
  . (Join-Path $tools 'mail-lib.ps1')
  $subj= if($WithResult){ "【中央競馬】買い目+着順 振り返り {0} ({1})" -f $Date,($venues -join '/') }else{ "【中央競馬】本日の買い目 {0} ({1})" -f $Date,($venues -join '/') }
  Send-Mail $subj $text
  Write-Host "メール送信しました。"
}
if(-not $ExportTxt -and -not $Notify){ Write-Output $text }
