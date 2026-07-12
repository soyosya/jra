# 対象レースの番組属性抽出: 条件(年齢/斤量方式)・競走種類(一般/特別/重賞)・一着賞金
param([string]$Out='C:\keiba\analysis\samecond_race_attr.csv')
[Console]::OutputEncoding=[System.Text.Encoding]::UTF8
$ErrorActionPreference='Stop'
. 'C:\keiba\tools\keiba-common.ps1'
$cn=New-Object System.Data.SqlClient.SqlConnection (Get-KeibaConnString); $cn.Open()
$c=$cn.CreateCommand(); $c.CommandTimeout=1800
$c.CommandText=@"
SET NOCOUNT ON;
SELECT ri.開催日 d, ri.開催場所 v, ri.レース番号 r,
       MAX(ri.条件) cond, MAX(ri.一着賞金) prize,
       MAX(ISNULL(vk.種類,N'')) shubetsu
FROM dbo.レース情報 ri
LEFT JOIN (SELECT 開催日,開催場所,レース番号, MAX(競走種類) 種類 FROM dbo.vw_競走結果統合 GROUP BY 開催日,開催場所,レース番号) vk
  ON vk.開催日=ri.開催日 AND vk.開催場所=ri.開催場所 AND vk.レース番号=ri.レース番号
WHERE ri.開催日 BETWEEN '2022-01-01' AND '2026-07-09' AND ri.開催場所<>N'帯広ば'
GROUP BY ri.開催日, ri.開催場所, ri.レース番号
"@
$dt=New-Object System.Data.DataTable
(New-Object System.Data.SqlClient.SqlDataAdapter $c).Fill($dt)|Out-Null
$cn.Close()
$sw=New-Object System.IO.StreamWriter($Out,$false,[System.Text.Encoding]::UTF8)
$sw.WriteLine('開催日,開催場所,レース番号,age,kin,shubetsu,prize')
foreach($row in $dt.Rows){
  $cond=[string]$row.cond
  $age=$(if($cond -match '2歳'){'2歳'}elseif($cond -match '3歳以上'){'3歳以上'}elseif($cond -match '3歳'){'3歳'}elseif($cond -match '4歳以上'){'4歳以上'}else{'他'})
  $kin=$(if($cond -match 'ハンデ'){'ハンデ'}elseif($cond -match '別定'){'別定'}elseif($cond -match '定量'){'定量'}else{'他'})
  $sh=[string]$row.shubetsu
  if($sh -eq ''){ $sh='一般' }
  $pz=$(if($row.prize -is [DBNull]){''}else{[long]$row.prize})
  $sw.WriteLine(('{0},{1},{2},{3},{4},{5},{6}' -f ([datetime]$row.d).ToString('yyyy-MM-dd'),$row.v,[int]$row.r,$age,$kin,$sh,$pz))
}
$sw.Close()
Write-Host ("DONE {0}行 -> {1}" -f $dt.Rows.Count,$Out)
