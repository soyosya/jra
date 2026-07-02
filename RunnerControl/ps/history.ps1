# 投票履歴(dbo.IPAT投票履歴=ランナーの全投票)をJSONで出力。/api/history用。読み取り専用。
# 的中列が無いため 的中=(確定済=1 AND 払戻金額>0) で導出。
# ★pwsh→RunPsのパイプで日本語(結果/式別/場名)がCP932化け→不正JSONになるため、stdoutをUTF-8に固定。
$OutputEncoding=[Console]::OutputEncoding=[System.Text.Encoding]::UTF8
$ErrorActionPreference='SilentlyContinue'
$cs=(Get-Content 'C:\jra\共通\appsettings.json' -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
$rows=@()
try{
  $cn=New-Object System.Data.SqlClient.SqlConnection $cs; $cn.Open()
  try{
    $cmd=$cn.CreateCommand()
    $cmd.CommandText=@"
SELECT TOP 300 投票日時,開催日,開催場所,レース番号,式別,
  ISNULL(軸馬番,'') 軸馬番, ISNULL(相手馬番,'') 相手馬番,
  ISNULL(点数,0) 点数, ISNULL(一点金額,0) 一点金額, ISNULL(投票金額,0) 投票金額,
  ISNULL(モード,'') モード, ISNULL(結果,'') 結果, ISNULL(確定済,0) 確定済,
  ISNULL(払戻金額,0) 払戻金額, ISNULL(取得元,'') 取得元
FROM dbo.IPAT投票履歴 ORDER BY 投票日時 DESC
"@
    $dt=New-Object System.Data.DataTable; (New-Object System.Data.SqlClient.SqlDataAdapter $cmd).Fill($dt)|Out-Null
    foreach($r in $dt.Rows){
      $done=[int]$r.確定済; $pay=[int]$r.払戻金額; $hit= if($done -eq 1 -and $pay -gt 0){1}else{0}
      $src= if("$($r.取得元)" -match '手動|manual'){'manual'}else{'runner'}
      $rows += [ordered]@{
        dt=$(try{([datetime]$r.投票日時).ToString('MM/dd HH:mm')}catch{"$($r.投票日時)"})
        date=$(try{([datetime]$r.開催日).ToString('MM/dd')}catch{''})
        fdate=$(try{([datetime]$r.開催日).ToString('yyyy-MM-dd')}catch{''})
        venue="$($r.開催場所)"; race=[int]$r.レース番号; type="$($r.式別)"
        axis="$($r.軸馬番)"; opp="$($r.相手馬番)"
        pts=[int]$r.点数; unit=[int]$r.一点金額; amt=[int]$r.投票金額
        mode="$($r.モード)"; result="$($r.結果)"; done=$done; hit=$hit; pay=$pay
        src=$src
      }
    }
  } finally { $cn.Close() }
}catch{}
@($rows) | ConvertTo-Json -Depth 5 -Compress -AsArray
