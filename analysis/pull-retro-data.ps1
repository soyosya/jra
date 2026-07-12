# 深掘り振り返り用データ一括出力。-Date -Venue で メタ/上位3着(コンピ順位・四角)/払戻(単複ワイド三連複)/人気 をテキスト表示。
param([Parameter(Mandatory=$true)][string]$Date,[Parameter(Mandatory=$true)][string]$Venue)
$cs=(Get-Content 'C:\jra\共通\appsettings.json' -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
function Q($sql){ $cn=New-Object System.Data.SqlClient.SqlConnection $cs; $cn.Open(); $c=$cn.CreateCommand(); $c.CommandText=$sql; $dt=New-Object System.Data.DataTable; [void](New-Object System.Data.SqlClient.SqlDataAdapter $c).Fill($dt); $cn.Close(); ,$dt }
$d=$Date; $v=$Venue
Write-Output "########## $v $d ##########"
Write-Output "===メタ(距離/種別/条件/競走名/馬場/天候/頭数)==="
Q "SELECT レース番号 R, MAX(距離) 距離, MAX(コース種別) 種, MAX(条件) 条件, MAX(競走名) 競走名, MAX(馬場) 馬場, MAX(天候) 天候, COUNT(*) 頭数 FROM dbo.レース情報 WHERE 開催日='$d' AND 開催場所=N'$v' GROUP BY レース番号 ORDER BY レース番号" | Format-Table -AutoSize
Write-Output "===上位3着(着順/馬番/コンピ順位コ/四コーナー四)==="
Q "SELECT k.レース番号 R,k.着順,k.馬番,c.指数順位 コ,k.四コーナー 四 FROM dbo.競走結果 k LEFT JOIN dbo.コンピ指数 c ON c.開催日=k.開催日 AND c.開催場所=k.開催場所 AND c.レース番号=k.レース番号 AND c.馬番=k.馬番 WHERE k.開催日='$d' AND k.開催場所=N'$v' AND k.着順 BETWEEN 1 AND 3 ORDER BY k.レース番号,k.着順" | Format-Table -AutoSize
Write-Output "===払戻(単勝/複勝/ワイド/三連複)==="
Q "SELECT レース番号 R,馬券,組番,CAST(金額 AS int) 金額 FROM dbo.払戻金 WHERE 開催日='$d' AND 開催場所=N'$v' AND 馬券 IN (N'単勝',N'複勝',N'ワイド',N'三連複') ORDER BY レース番号, CASE 馬券 WHEN N'単勝' THEN 1 WHEN N'複勝' THEN 2 WHEN N'ワイド' THEN 3 ELSE 4 END" | Format-Table -AutoSize
Write-Output "===勝ち馬の調教矢印/厩舎印(参考)==="
Q "SELECT k.レース番号 R,k.馬番,ch.矢印,LEFT(ISNULL(ch.追い切り短評,''),18) 調短 FROM dbo.競走結果 k LEFT JOIN dbo.調教 ch ON ch.開催日=k.開催日 AND ch.開催場所=k.開催場所 AND ch.レース番号=k.レース番号 AND ch.馬番=k.馬番 WHERE k.開催日='$d' AND k.開催場所=N'$v' AND k.着順=1 ORDER BY k.レース番号" | Format-Table -AutoSize
