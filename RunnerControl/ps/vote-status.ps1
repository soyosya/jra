# 手動投票の成否ポーリング用。指定レースで since 以降に記録されたIPAT投票履歴を結果別に集計+IpatVote稼働中フラグを返す。
#  /api/vote-status から呼ぶ。doVote()が投票開始後にポーリングして「投票処理中→投票完了/失敗」を表示する。
param([string]$Venue='',[int]$Race=0,[string]$Since='')
$OutputEncoding=[Console]::OutputEncoding=[System.Text.Encoding]::UTF8
function Out-Json($o){ $o | ConvertTo-Json -Compress }
try{
  $running = @(Get-Process IpatVote -ErrorAction SilentlyContinue).Count -gt 0
  $done=0;$fail=0;$closed=0;$skip=0;$total=0; $rows=@()
  if($Venue -ne '' -and $Race -gt 0){
    $cs=(Get-Content 'C:\jra\共通\appsettings.json' -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
    $cn=New-Object System.Data.SqlClient.SqlConnection $cs; $cn.Open(); $c=$cn.CreateCommand()
    $sinceClause= if($Since -ne ''){ ' AND 投票日時 >= @s' }else{ ' AND 投票日時 >= DATEADD(MINUTE,-20,SYSDATETIME())' }
    $c.CommandText="SELECT 式別 bt,方式 mt,結果 rs,投票金額 amt FROM dbo.IPAT投票履歴 WHERE 開催日=CONVERT(date,GETDATE()) AND 開催場所=@v AND レース番号=@r AND 取得元=N'手動'" + $sinceClause + " ORDER BY 投票日時"
    [void]$c.Parameters.AddWithValue('@v',$Venue);[void]$c.Parameters.AddWithValue('@r',$Race); if($Since -ne ''){ [void]$c.Parameters.AddWithValue('@s',$Since) }
    $dt=New-Object System.Data.DataTable;(New-Object System.Data.SqlClient.SqlDataAdapter $c).Fill($dt)|Out-Null; $cn.Close()
    foreach($x in $dt.Rows){ $total++; $rs="$($x.rs)"
      if($rs -eq '投票完了'){$done++}elseif($rs -match '失敗'){$fail++}elseif($rs -match '締切'){$closed++}elseif($rs -match '見送り'){$skip++}
      $rows+=[ordered]@{ bt="$($x.bt)"; mt="$($x.mt)"; rs=$rs; amt=[int]$x.amt } }
  }
  Out-Json @{ ok=$true; running=$running; total=$total; done=$done; fail=$fail; closed=$closed; skip=$skip; rows=$rows }
}catch{ Out-Json @{ ok=$false; running=$false; msg=('エラー: '+$_.Exception.Message) } }
