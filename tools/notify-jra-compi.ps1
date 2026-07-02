<#
.SYNOPSIS
  中央競馬: 出馬表(レース情報)未取得の前日でも、コンピ指数(+厩舎の話の印/調教矢印)で全レースの軸/相手をメール通知する。
.DESCRIPTION
  前日はレース情報(出馬表)を取り込む手段が無く jra-card は動かないため、前向きに取得できる
  コンピ指数(軸の強信号)を主軸に、厩舎の話の印・調教の矢印を添えて買目を出す。
    軸 = コンピ1位 / 相手 = コンピ2・3位。指数の絶対水準で 80+=堅(強), <=67=弱 を注記
    (検証: コンピ1位でも指数80+は複勝72%、60台は41%)。厩舎の話◎・調教矢印↗も併記。
  事前に fetch-compi/fetch-danwa/fetch-cyokyo を当日分実行しておくこと。
.PARAMETER Date    既定=翌日(明日)。
.PARAMETER DryRun  送信せず本文を標準出力に表示。
#>
[CmdletBinding()]
param([string]$Date=((Get-Date).AddDays(1).ToString('yyyy-MM-dd')),[switch]$DryRun)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'mail-lib.ps1')
$cs=(Get-Content (Join-Path $PSScriptRoot '..\共通\appsettings.json') -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
$conn=New-Object System.Data.SqlClient.SqlConnection($cs);$conn.Open()
function Q($sql,$p){ $c=$conn.CreateCommand();$c.CommandText=$sql;foreach($k in $p.Keys){[void]$c.Parameters.AddWithValue($k,$p[$k])};$r=$c.ExecuteReader();$o=@();while($r.Read()){$row=[ordered]@{};for($i=0;$i -lt $r.FieldCount;$i++){$row[$r.GetName($i)]=$r.GetValue($i)};$o+=[pscustomobject]$row};$r.Close();,$o }

$venues=@(Q "SELECT DISTINCT 開催場所 FROM コンピ指数 WHERE 開催日=@d ORDER BY 開催場所" @{'@d'=$Date} | ForEach-Object { $_.開催場所 })
if($venues.Count -eq 0){
  $subj="【中央競馬】明日の買目 {0}: コンピ指数未取得" -f $Date
  $body="{0} のコンピ指数が未取得です。fetch-compi --date {0} を先に実行してください。" -f $Date
  if($DryRun){ "$subj`n`n$body" } else { Send-Mail $subj $body; "送信: $subj" }; $conn.Close(); return
}

$body  = "中央競馬 明日の買目  {0}`n" -f $Date
$body += "コンピ指数ベース(出馬表未取得のため簡易版)。軸=コンピ1位/相手=2・3位。`n"
$body += "指数: 80+=堅★ / <=67=弱▲(同じ1位でも複勝72%↔41%)。◎=厩舎の話自信、↗=調教上向き。`n`n"
foreach($v in $venues){
  $rows=Q @"
SELECT c.レース番号 r,c.馬番 no,c.馬名 nm,c.指数 idx,c.指数順位 rk,d.印 danwa,cy.矢印 ya
FROM (SELECT *,ROW_NUMBER() OVER(PARTITION BY レース番号,馬番 ORDER BY 取得日時 DESC) rn FROM コンピ指数 WHERE 開催日=@d AND 開催場所=@v) c
OUTER APPLY (SELECT TOP 1 印 FROM 厩舎の話 x WHERE x.開催日=@d AND x.開催場所=@v AND x.レース番号=c.レース番号 AND x.馬番=c.馬番 ORDER BY 取得日時 DESC) d
OUTER APPLY (SELECT TOP 1 矢印 FROM 調教 y WHERE y.開催日=@d AND y.開催場所=@v AND y.レース番号=c.レース番号 AND y.馬番=c.馬番 ORDER BY 取得日時 DESC) cy
WHERE c.rn=1 AND c.指数順位<=3 ORDER BY c.レース番号,c.指数順位
"@ @{'@d'=$Date;'@v'=$v}
  $body += "■ {0}`n" -f $v
  foreach($g in ($rows | Group-Object r)){
    $line=""
    foreach($x in ($g.Group | Sort-Object rk)){
      $mk=""
      if([int]$x.idx -ge 80){$mk+="★"} elseif([int]$x.idx -le 67){$mk+="▲"}
      if("$($x.danwa)" -eq '◎'){$mk+="◎"}
      if("$($x.ya)" -match '↗|↑'){$mk+="↗"}
      $tag= if([int]$x.rk -eq 1){"軸"}else{"$($x.rk)"}
      $line += "  {0}:{1}{2}(指{3}{4})" -f $tag,$x.no,$x.nm.Substring(0,[Math]::Min(6,$x.nm.Length)),$x.idx,$mk
    }
    $body += ("{0,2}R{1}`n" -f [int]$g.Name,$line)
  }
  $body += "`n"
}
$conn.Close()
$subj="【中央競馬】明日の買目 {0} ({1})" -f $Date,($venues -join '/')
if($DryRun){ "----- 件名 -----`n$subj`n`n----- 本文 -----`n$body" }
else { Send-Mail $subj $body; "送信しました: $subj" }
