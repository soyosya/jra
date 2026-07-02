# 役割: メール送信の共通関数。資格情報は secrets.local.json(git追跡外)。
# 送信方式の優先順:
#   ① Microsoft Graph API (推奨・MFA/Security Defaults はそのまま): GraphTenantId / GraphClientId / GraphClientSecret が揃っていれば使用。
#      送信元= MailFrom(既定 MailUser)。宛先= MailTo(既定 MailUser, 複数は ; , 区切り)。アプリに Mail.Send(Application) + 管理者同意 が必要。
#   ② SMTP AUTH (smtp.office365.com:587 等): MailUser / MailPass。テナントで SMTP AUTH 有効 & Security Defaults 無効が前提。
# 使い方: . (Join-Path $PSScriptRoot 'mail-lib.ps1'); Send-Mail "件名" "本文"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ブランドロゴ(透過64)。存在すればHTMLメール+CIDインライン埋込、無ければプレーンテキストにフォールバック。
# ★64pxに縮小+imgにwidth/height属性明示(OutlookはheightのCSSを無視しネイティブ寸法で出すため小ファイル+属性の両方で確実に小さく表示・地方統一2026-06-24)。
$script:MailLogo = 'C:\jra\branding\icon-64.png'
function ConvertTo-HtmlBody([string]$Body){
  # 本文の整列(軸/相手の桁揃え)を保つため <pre>。HTMLエスケープ後にCIDロゴ付きヘッダで包む。
  $esc = ($Body -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;')
  # ★ロゴは本文の最後に配置・サイズは地方と同じ23pxに縮小(ユーザ要望2026-06-24・地方の調整を反映)。タイトルはテキストで先頭に維持。
  @"
<div style="font-family:'Yu Gothic UI',sans-serif;color:#1a2638">
<div style="border-bottom:2px solid #12264a;padding-bottom:6px;margin-bottom:8px">
<span style="font-size:16px;font-weight:700;color:#12264a;vertical-align:middle">Turfora &mdash; 中央競馬(JRA)</span>
</div>
<pre style="font-family:Consolas,'Yu Gothic UI',monospace;font-size:10pt;white-space:pre-wrap;margin:0">$esc</pre>
<img src="cid:turforalogo" alt="Turfora" width="64" height="64" style="width:64px;height:64px;display:block;margin:12px 0 0;border:0">
</div>
"@
}

function Get-MailSecrets {
  $p = Join-Path (Split-Path $PSScriptRoot -Parent) 'secrets.local.json'
  if(Test-Path $p){ try{ return (Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json) }catch{ return $null } }
  return $null
}

function Send-MailGraph($s,[string]$Subject,[string]$Body){
  $from = if($s.MailFrom){$s.MailFrom}else{$s.MailUser}
  $toRaw = if($s.MailTo){$s.MailTo}else{$s.MailUser}
  try{
    $tok = Invoke-RestMethod -Method POST -Uri ("https://login.microsoftonline.com/{0}/oauth2/v2.0/token" -f $s.GraphTenantId) -ContentType 'application/x-www-form-urlencoded' -Body @{
      client_id=$s.GraphClientId; client_secret=$s.GraphClientSecret; scope='https://graph.microsoft.com/.default'; grant_type='client_credentials' }
    $rcpts = @(); foreach($t in ($toRaw -split '[;,]')){ if($t.Trim() -ne ''){ $rcpts += @{ emailAddress=@{ address=$t.Trim() } } } }
    # ロゴがあればHTML+CIDインライン添付(Outlook/M365でbase64データURIはブロックされるためCIDが確実)。無ければプレーンテキスト。
    if(Test-Path $script:MailLogo){
      $cb = [Convert]::ToBase64String([IO.File]::ReadAllBytes($script:MailLogo))
      $msgObj = @{ subject=$Subject; body=@{ contentType='HTML'; content=(ConvertTo-HtmlBody $Body) }; toRecipients=$rcpts;
        attachments=@( @{ '@odata.type'='#microsoft.graph.fileAttachment'; name='turfora.png'; contentType='image/png'; contentBytes=$cb; isInline=$true; contentId='turforalogo' } ) }
    } else {
      $msgObj = @{ subject=$Subject; body=@{ contentType='Text'; content=$Body }; toRecipients=$rcpts }
    }
    $payload = @{ message=$msgObj; saveToSentItems=$true } | ConvertTo-Json -Depth 10
    $bytes=[System.Text.Encoding]::UTF8.GetBytes($payload)
    Invoke-RestMethod -Method POST -Uri ("https://graph.microsoft.com/v1.0/users/{0}/sendMail" -f $from) -Headers @{ Authorization=("Bearer "+$tok.access_token) } -ContentType 'application/json; charset=utf-8' -Body $bytes | Out-Null
    Write-Host "[mail/graph] 送信OK: $Subject"; return $true
  }catch{ Write-Host "[mail/graph] 送信失敗: $($_.Exception.Message)"; return $false }
}

function Send-MailSmtp($s,[string]$Subject,[string]$Body){
  $from = if($s.MailFrom){$s.MailFrom}else{$s.MailUser}
  $to   = if($s.MailTo){$s.MailTo}else{$s.MailUser}
  $smtp = if($s.MailSmtp){$s.MailSmtp}else{'smtp.office365.com'}
  $port = if($s.MailPort){[int]$s.MailPort}else{587}
  try{
    $msg = New-Object System.Net.Mail.MailMessage
    $msg.From = New-Object System.Net.Mail.MailAddress($from)
    foreach($t in ($to -split '[;,]')){ if($t.Trim() -ne ''){ $msg.To.Add($t.Trim()) } }
    $msg.Subject=$Subject; $msg.SubjectEncoding=[Text.Encoding]::UTF8; $msg.BodyEncoding=[Text.Encoding]::UTF8
    if(Test-Path $script:MailLogo){
      # HTML本文 + CIDインライン画像(LinkedResource)
      $av = [System.Net.Mail.AlternateView]::CreateAlternateViewFromString((ConvertTo-HtmlBody $Body),$null,'text/html')
      $lr = New-Object System.Net.Mail.LinkedResource($script:MailLogo,'image/png'); $lr.ContentId='turforalogo'; $lr.TransferEncoding=[System.Net.Mime.TransferEncoding]::Base64
      $av.LinkedResources.Add($lr); $msg.AlternateViews.Add($av); $msg.IsBodyHtml=$true
    } else { $msg.Body=$Body }
    $sc = New-Object System.Net.Mail.SmtpClient($smtp,$port); $sc.EnableSsl=$true
    $sc.Credentials = New-Object System.Net.NetworkCredential($s.MailUser,$s.MailPass)
    $sc.Send($msg); Write-Host "[mail/smtp] 送信OK: $Subject"; return $true
  }catch{ Write-Host "[mail/smtp] 送信失敗: $($_.Exception.Message)"; return $false }
}

# Teams 投稿(任意): secrets の TeamsWebhook(Power Automate Workflows の Webhook URL)があれば送る。ベストエフォート。
# Power Automate「Webhookアラートをチャネルに送信する」テンプレは Adaptive Card(message+attachments)形式を期待。
function Send-Teams($s,[string]$Subject,[string]$Body){
  if(-not $s.TeamsWebhook){ return }
  try{
    $bodyText = ($Body -replace "`r`n","`n")
    $card = @{ type='message'; attachments=@( @{
      contentType='application/vnd.microsoft.card.adaptive';
      content=@{ '$schema'='http://adaptivecards.io/schemas/adaptive-card.json'; type='AdaptiveCard'; version='1.4';
        body=@(
          @{ type='TextBlock'; text=$Subject; weight='Bolder'; size='Medium'; wrap=$true },
          @{ type='TextBlock'; text=$bodyText; wrap=$true }
        ) } } ) }
    $payload = $card | ConvertTo-Json -Depth 12
    $bytes=[System.Text.Encoding]::UTF8.GetBytes($payload)
    Invoke-RestMethod -Method POST -Uri $s.TeamsWebhook -ContentType 'application/json; charset=utf-8' -Body $bytes | Out-Null
    Write-Host "[teams] 投稿OK"
  }catch{ Write-Host "[teams] 投稿失敗: $($_.Exception.Message)" }
}

function Send-Mail([string]$Subject,[string]$Body){
  $s = Get-MailSecrets
  if(-not $s){ Write-Host "[mail] secrets.local.json なし→送信スキップ: $Subject"; return $false }
  $r=$false
  if($s.GraphTenantId -and $s.GraphClientId -and $s.GraphClientSecret){ $r=(Send-MailGraph $s $Subject $Body) }
  elseif($s.MailUser -and $s.MailPass){ $r=(Send-MailSmtp $s $Subject $Body) }
  else { Write-Host "[mail] Graph も SMTP も未設定→メール送信スキップ: $Subject" }
  Send-Teams $s $Subject $Body   # メールに加えて Teams にも(設定時のみ)
  return $r
}
