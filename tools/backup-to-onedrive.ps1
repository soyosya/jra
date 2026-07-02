<#
.SYNOPSIS
  本番(C:\jra) → OneDrive(...\ドキュメント\JRA) へバックアップミラー(10分間隔タスク)。
  ★本番はローカルC:\jra。OneDriveはバックアップ用(編集してもタスクは本番を見ない)。
  各サブフォルダを robocopy /MIR、ルート直下ファイルはコピー。.git/obj/.vs/*.pdb 除外。
#>
$ErrorActionPreference='Continue'
$src='C:\jra'
$dst='C:\Users\suzukih\OneDrive - 株式会社創陽社\ドキュメント\JRA'
$logDir='C:\temp\jra-log'; New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$log=Join-Path $logDir ("backup_{0}.log" -f (Get-Date -Format 'yyyy-MM-dd'))
function L($m){ $line="[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'),$m; Write-Host $line; try{ Add-Content -LiteralPath $log -Value $line -Encoding UTF8 }catch{} }
if(-not (Test-Path $src)){ L "本番C:\jraが見つかりません→中止"; exit 1 }
if(-not (Test-Path $dst)){ L "OneDrive宛先が見つかりません→中止"; exit 1 }
L "===== バックアップ開始 C:\jra → OneDrive(JRA) ====="
$err=0
foreach($d in (Get-ChildItem $src -Directory)){
  if($d.Name -in '.git','obj','.vs'){ continue }
  robocopy "$src\$($d.Name)" "$dst\$($d.Name)" /MIR /XD .git obj .vs /XF *.pdb /R:1 /W:1 /NFL /NDL /NP /NJH /NJS /MT:16 | Out-Null
  $rc=$LASTEXITCODE
  L ("  {0,-20} robocopy={1} {2}" -f $d.Name,$rc,$(if($rc -lt 8){'OK'}else{'★失敗'; $err++}))
}
foreach($f in (Get-ChildItem $src -File)){
  try{ Copy-Item $f.FullName (Join-Path $dst $f.Name) -Force }catch{ L "  ルートファイル $($f.Name) コピー失敗: $($_.Exception.Message)"; $err++ }
}
L ("===== バックアップ完了 (エラー {0}) =====" -f $err)
exit $(if($err -gt 0){1}else{0})
