# 役割: メール送信の共通関数。資格情報は secrets.local.json(git追跡外)。
# 送信方式の優先順:
#   ① Microsoft Graph API (推奨・MFA/Security Defaults はそのまま): GraphTenantId / GraphClientId / GraphClientSecret が揃っていれば使用。
#      送信元= MailFrom(既定 MailUser)。宛先= MailTo(既定 MailUser, 複数は ; , 区切り)。アプリに Mail.Send(Application) + 管理者同意 が必要。
#   ② SMTP AUTH (smtp.office365.com:587 等): MailUser / MailPass。テナントで SMTP AUTH 有効 & Security Defaults 無効が前提。
# 使い方: . (Join-Path $PSScriptRoot 'mail-lib.ps1'); Send-Mail "件名" "本文"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

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
    $payload = @{ message=@{ subject=$Subject; body=@{ contentType='Text'; content=$Body }; toRecipients=$rcpts }; saveToSentItems=$true } | ConvertTo-Json -Depth 8
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
    $msg.Subject=$Subject; $msg.Body=$Body; $msg.SubjectEncoding=[Text.Encoding]::UTF8; $msg.BodyEncoding=[Text.Encoding]::UTF8
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
