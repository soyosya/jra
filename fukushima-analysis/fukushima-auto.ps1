<#
  福島 自動予想ループのヘルパ。-Pending N で「レースNが確定したか」を判定し、
  確定なら N の結果(1-2-3着)＋次レース(N+1)のカード(出馬表/オッズ/jra-card軸相手/確度/複勝確率)を出力。
  未確定なら STATE=PENDING を返すだけ(高速)。確定検知の結果はJRA_ChangesLoopが3分毎にDB投入。
#>
param([Parameter(Mandatory)][int]$Pending, [string]$Date='2026-06-28', [string]$Venue='福島', [int]$MaxR=12)
[Console]::OutputEncoding=[Text.Encoding]::UTF8
$ErrorActionPreference='Stop'
$cs=(Get-Content 'C:\jra\共通\appsettings.json' -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
$cn=New-Object System.Data.SqlClient.SqlConnection $cs;$cn.Open()
function Q($sql,$r){ $c=$cn.CreateCommand();$c.CommandText=$sql;[void]$c.Parameters.AddWithValue('@d',$Date);[void]$c.Parameters.AddWithValue('@v',$Venue);[void]$c.Parameters.AddWithValue('@r',$r);$dt=New-Object System.Data.DataTable;(New-Object System.Data.SqlClient.SqlDataAdapter $c).Fill($dt)|Out-Null;,$dt.Rows }

# 1) Pending確定判定(着順>0が3頭以上で確定とみなす)
$fin=[int](Q 'SELECT COUNT(*) n FROM dbo.競走結果 WHERE 開催日=@d AND 開催場所=@v AND レース番号=@r AND TRY_CONVERT(int,着順)>0' $Pending)[0].n
if($fin -lt 3){ Write-Output "STATE=PENDING race=$Pending fin=$fin"; $cn.Close(); return }

Write-Output "STATE=CONFIRMED race=$Pending"
# 2) Pending結果(1-3着) コンピ順位/人気付き
$res=Q @'
SELECT TRY_CONVERT(int,k.着順) ch, k.馬番, k.馬名, c.指数順位 ord, o.人気, o.単勝オッズ
FROM dbo.競走結果 k
LEFT JOIN (SELECT 馬番,指数順位,ROW_NUMBER() OVER(PARTITION BY 馬番 ORDER BY 取得日時 DESC) sn FROM dbo.コンピ指数 WHERE 開催日=@d AND 開催場所=@v AND レース番号=@r) c ON c.馬番=k.馬番 AND c.sn=1
LEFT JOIN (SELECT 馬番,人気,単勝オッズ,ROW_NUMBER() OVER(PARTITION BY 馬番 ORDER BY 日時 DESC) sn FROM dbo.リアルタイムオッズ WHERE 開催日=@d AND 開催場所=@v AND レース番号=@r) o ON o.馬番=k.馬番 AND o.sn=1
WHERE k.開催日=@d AND k.開催場所=@v AND k.レース番号=@r AND TRY_CONVERT(int,k.着順) BETWEEN 1 AND 3
ORDER BY ch
'@ $Pending
Write-Output "RESULT race=$Pending :"
foreach($x in $res){ Write-Output ("  {0}着 馬番{1} {2} (コ{3}位/{4}人気/{5}倍)" -f $x.ch,$x.馬番,$x.馬名,$x.ord,$(if($x.人気 -is [DBNull]){'-'}else{$x.人気}),$(if($x.単勝オッズ -is [DBNull]){'-'}else{$x.単勝オッズ})) }

# 3) 次レース(N+1)のカード
$next=$Pending+1
if($next -gt $MaxR){ Write-Output "NONEXT (最終レース終了)"; $cn.Close(); return }
# 次レースにコンピ(出走馬)があるか
$hasNext=[int](Q 'SELECT COUNT(*) n FROM dbo.コンピ指数 WHERE 開催日=@d AND 開催場所=@v AND レース番号=@r' $next)[0].n
if($hasNext -lt 1){ Write-Output "NONEXT (race $next のコンピ無し)"; $cn.Close(); return }

Write-Output "NEXTCARD race=$next"
# 次レースの発走時刻/条件(通知ヘッダ用。メール本文に必ず発走時刻を入れる[[jra-auto-renotify]])
$nmeta=Q 'SELECT TOP 1 発走時刻,距離,コース種別,条件,競走名 FROM dbo.レース情報 WHERE 開催日=@d AND 開催場所=@v AND レース番号=@r' $next
$ntime= if($nmeta.Count -gt 0 -and $nmeta[0].発走時刻 -isnot [DBNull]){ ([datetime]$nmeta[0].発走時刻).ToString('HH:mm') }else{'-'}
Write-Output ("POST race=$next 発走時刻=$ntime")
$ent=Q @'
SELECT c.馬番, c.馬名, c.指数順位 ord, c.指数, o.人気, o.単勝オッズ
FROM (SELECT 馬番,馬名,指数順位,指数,ROW_NUMBER() OVER(PARTITION BY 馬番 ORDER BY 取得日時 DESC) sn FROM dbo.コンピ指数 WHERE 開催日=@d AND 開催場所=@v AND レース番号=@r) c
LEFT JOIN (SELECT 馬番,人気,単勝オッズ,ROW_NUMBER() OVER(PARTITION BY 馬番 ORDER BY 日時 DESC) sn FROM dbo.リアルタイムオッズ WHERE 開催日=@d AND 開催場所=@v AND レース番号=@r) o ON o.馬番=c.馬番 AND o.sn=1
WHERE c.sn=1 ORDER BY c.指数順位
'@ $next
Write-Output "出馬表(コ順/馬番/馬名/指数/単勝/人気):"
foreach($x in $ent){ Write-Output ("  {0,2} 馬番{1,2} {2,-18} 指{3} {4}倍 {5}人気" -f $x.ord,$x.馬番,$x.馬名,$x.指数,$(if($x.単勝オッズ -is [DBNull]){'-'}else{$x.単勝オッズ}),$(if($x.人気 -is [DBNull]){'-'}else{$x.人気})) }
$cn.Close()
Write-Output "(次レース $next の軸/相手/確度/複勝確率/買目は notify-jra-picks -Race $next の出力＋メールで取得)"
