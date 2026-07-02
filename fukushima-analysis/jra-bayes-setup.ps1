# 地方ベイズのビルダー/モデルをJRA(中央競馬DB)版に複製
$jcs=(Get-Content 'C:\jra\共通\appsettings.json' -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
# --- ビルダー ---
$b=Get-Content 'C:\temp\bayes-h2h-build.ps1' -Raw -Encoding UTF8
# 接続文字列行を中央競馬へ
$b=$b -replace '(?m)^\s*\$cs=\(Get-Content[^\r\n]*', ('$cs=''' + $jcs + '''')
# 出力先
$b=$b -replace [regex]::Escape('C:\temp\bayes_feat.csv'), 'C:\temp\jra_bayes_feat.csv'
[IO.File]::WriteAllText('C:\temp\jra-bayes-build.ps1',$b,(New-Object Text.UTF8Encoding($false)))
# --- モデル ---
$m=Get-Content 'C:\temp\bayes-model.ps1' -Raw -Encoding UTF8
$m=$m -replace [regex]::Escape('C:\temp\bayes_feat.csv'), 'C:\temp\jra_bayes_feat.csv'
[IO.File]::WriteAllText('C:\temp\jra-bayes-model.ps1',$m,(New-Object Text.UTF8Encoding($false)))
'--- 作成完了。置換確認(ビルダー) ---'
Select-String -Path 'C:\temp\jra-bayes-build.ps1' -Pattern 'Database=中央競馬|jra_bayes_feat|appsettings|\$cs=' | ForEach-Object{ '  L'+$_.LineNumber+': '+($_.Line.Trim().Substring(0,[Math]::Min(72,$_.Line.Trim().Length))) }
