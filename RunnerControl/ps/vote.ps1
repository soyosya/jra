# 買目ページ(IPAT投票Lite風)からの投票実行(JSON)。カート(複数買い目)をIpatVote BetsLoader形式CSV(複数行)に変換しIpatVoteを起動。
#  各買い目=CSV1行: date,venue,race,bettype,method,axis,partners(|区切り),stake,f1,f2,f3。IpatVoteが行ごとに式別/方式を判定して投票。
#  DryRun=同期実行し試算を返す。ConfirmStop/Auto=デタッチ起動。★IPAT実DOMセレクタ較正後に実動・未較正は安全中断([[jra-ipat-vote]])。
param([string]$Venue='',[int]$Race=0,[string]$Mode='DryRun',[string]$CartPath='',[switch]$AllowDup)
$OutputEncoding=[Console]::OutputEncoding=[System.Text.Encoding]::UTF8
$ErrorActionPreference='Stop'
function Out-Json($o){ $o | ConvertTo-Json -Compress }
try{
  if([string]::IsNullOrWhiteSpace($Venue) -or $Race -le 0){ Out-Json @{ ok=$false; msg='venue/race が必要です' }; return }
  if($Mode -notin @('DryRun','ConfirmStop','Auto')){ $Mode='DryRun' }
  if([string]::IsNullOrWhiteSpace($CartPath) -or -not (Test-Path $CartPath)){ Out-Json @{ ok=$false; msg='買い目(カート)が見つかりません' }; return }
  $cart=@(Get-Content $CartPath -Raw -Encoding UTF8 | ConvertFrom-Json)
  if($cart.Count -eq 0){ Out-Json @{ ok=$false; msg='買い目が空です' }; return }
  # ★ガード: 実投票はIpatVote稼働中(ランナー投票/別の手動投票)と衝突するため拒否(DryRunは許可)
  if($Mode -ne 'DryRun' -and @(Get-Process IpatVote -ErrorAction SilentlyContinue).Count -gt 0){ Out-Json @{ ok=$false; msg='投票処理中(IpatVote稼働中)です。完了を待って再実行してください。' }; return }
  $date=(Get-Date -Format 'yyyy-MM-dd'); $ymd=(Get-Date -Format 'yyyyMMdd')
  $exe='C:\jra\IpatVote\bin\Release\net10.0\IpatVote.exe'
  if(-not (Test-Path $exe)){ Out-Json @{ ok=$false; msg=('IpatVote.exe 未検出: '+$exe) }; return }
  # C2: 重複投票ガード(実投票時のみ)。当該レースで既に投票完了の同一買目(式別×馬番集合・順不同ユニーク)をカートから除外。-AllowDupで無視(上乗せ投票)。
  if($Mode -ne 'DryRun' -and -not $AllowDup){
    $done=@{}
    try{
      $cs2=(Get-Content 'C:\jra\共通\appsettings.json' -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
      $cn2=New-Object System.Data.SqlClient.SqlConnection $cs2; $cn2.Open(); $c2=$cn2.CreateCommand()
      $c2.CommandText="SELECT 式別 bt,軸馬番 ax,相手馬番 pt,組番 kb FROM dbo.IPAT投票履歴 WHERE 開催日=@d AND 開催場所=@v AND レース番号=@r AND 結果=N'投票完了'"  # ★ASCIIエイリアス必須(pwsh7で$row['日本語列']パースエラー回避)
      [void]$c2.Parameters.AddWithValue('@d',$date);[void]$c2.Parameters.AddWithValue('@v',$Venue);[void]$c2.Parameters.AddWithValue('@r',$Race)
      $dt2=New-Object System.Data.DataTable;(New-Object System.Data.SqlClient.SqlDataAdapter $c2).Fill($dt2)|Out-Null
      foreach($row in $dt2.Rows){ $nums=(([regex]::Matches("$($row.ax) $($row.pt) $($row.kb)",'\d+')|ForEach-Object{[int]$_.Value}|Sort-Object -Unique) -join ','); $done["$($row.bt)|$nums"]=$true }
      $cn2.Close()
    }catch{}
    if($done.Count -gt 0){
      $before=$cart.Count
      $cart=@($cart | Where-Object{ $b=$_; $alln=@(); if($b.axis){$alln+=[int]$b.axis}; foreach($f in 'partners','box','f1','f2','f3'){ if($b.$f){ $alln+=@($b.$f|ForEach-Object{[int]$_}) } }; $key="$([string]$b.bettype)|"+(($alln|Sort-Object -Unique) -join ','); -not $done.ContainsKey($key) })
      if($cart.Count -eq 0){ Out-Json @{ ok=$false; msg=('全ての買い目が既に投票完了です(重複投票ガード・除外'+$before+'件)') }; return }
    }
  }
  # カート→CSV(IpatVote BetsLoader形式・★無引用符=jra-export-bets同様。Export-Csvは引用符を付けBetsLoaderが解釈不可)
  $lines=New-Object System.Collections.Generic.List[string]
  $lines.Add('date,venue,race,bettype,method,axis,partners,stake,f1,f2,f3,multi')
  foreach($b in $cart){
    $bt=[string]$b.bettype; $mJp=[string]$b.method; $single=($bt -in @('単勝','複勝'))
    $axis=''; $partners=''; $f1='';$f2='';$f3=''; $mlt= if($b.multi){'1'}else{''}
    if($single){ $axis=[string][int]$b.axis }
    elseif($mJp -eq 'ボックス'){ $partners=((@($b.box)|ForEach-Object{[int]$_}) -join '|') }
    elseif($mJp -eq 'フォーメーション'){ $f1=((@($b.f1)|ForEach-Object{[int]$_}) -join '|'); $f2=((@($b.f2)|ForEach-Object{[int]$_}) -join '|'); $f3=((@($b.f3)|ForEach-Object{[int]$_}) -join '|') }
    else { $axis=[string][int]$b.axis; $partners=((@($b.partners)|ForEach-Object{[int]$_}) -join '|') }
    $lines.Add(($date,$Venue,$Race,$bt,$mJp,$axis,$partners,[int]$b.stake,$f1,$f2,$f3,$mlt) -join ',')
  }
  $tmp=Join-Path $env:TEMP 'rc-vote'; New-Item -ItemType Directory -Force -Path $tmp | Out-Null
  $csv=Join-Path $tmp ("vote_{0}_{1}_{2}.csv" -f $ymd,$Venue,$Race)
  [IO.File]::WriteAllLines($csv,$lines,(New-Object Text.UTF8Encoding($false)))
  $cnt=$cart.Count
  $ipatArgs=@($csv,'--mode',$Mode,'--date',$date,'--mode-label','手動')   # C1: /buyme投票は手動分類(ランナーAuto収支と分離)
  if($Mode -eq 'DryRun'){
    $prev=[Console]::OutputEncoding; $out=''
    try{ [Console]::OutputEncoding=[System.Text.Encoding]::UTF8; $out=(& $exe @ipatArgs 2>&1 | Out-String) } finally { [Console]::OutputEncoding=$prev }
    Out-Json @{ ok=$true; mode='DryRun'; count=$cnt; output=$out }
  } else {
    $since=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')   # この投票で新たに記録される行をポーリングで識別する基準時刻(サーバ時刻)
    Start-Process -FilePath $exe -ArgumentList $ipatArgs -WindowStyle Hidden | Out-Null
    $note= if($Mode -eq 'ConfirmStop'){'確認停止: サーバのIPATブラウザで内容確認→購入を人が操作。※IPAT実DOM較正後に実動・未較正は安全中断。'}else{'★Auto=無人で実投票。※IPAT実DOM較正後に実動・未較正は安全中断。'}
    Out-Json @{ ok=$true; mode=$Mode; count=$cnt; since=$since; msg=('投票処理を開始しました（'+$Mode+'・'+$cnt+'件）。'+$note) }
  }
}catch{ Out-Json @{ ok=$false; msg=('エラー: '+$_.Exception.Message) } }
