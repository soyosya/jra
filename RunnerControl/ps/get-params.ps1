# runner-params.json から現在のパラメータをJSON出力(/api/params GET)。未保存なら既定値。
$OutputEncoding=[Console]::OutputEncoding=[System.Text.Encoding]::UTF8  # パイプ経由の日本語(mode等)CP932化け防止
$paramsPath='C:\jra\RunnerControl\runner-params.json'
$def=[ordered]@{ mode='通知のみ'; betType='ワイド'; partners=3; stake=100; lead=40; interval=20; voteWithin=25; frontFlat=0; changeLeadMin=30; changeInterval=3; oddsInterval=5; noMail=$false }
if(Test-Path $paramsPath){
  try{
    $j=Get-Content $paramsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach($k in @($def.Keys)){ if($null -ne $j.$k){ $def[$k]=$j.$k } }
  }catch{}
}
$def | ConvertTo-Json -Compress
