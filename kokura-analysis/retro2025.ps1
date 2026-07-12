# 昨年同開催(2025-06-28 小倉)全12Rの予想vs結果 突合分析。決着型(四角)/コンピ軸/人気軸/jra-card軸の成否。
[Console]::OutputEncoding=[Text.Encoding]::UTF8
$D='2025-06-28'; $V=[char]0x5c0f+[char]0x5009
$cs='Server=192.168.168.81\SQLEXPRESS;Database=中央競馬;User Id=sa;Password=Hanasaki#2093;TrustServerCertificate=True;Connect Timeout=30'
$cn=New-Object System.Data.SqlClient.SqlConnection $cs;$cn.Open()
function Q($sql){ $c=$cn.CreateCommand();$c.CommandText=$sql;$c.CommandTimeout=300;$dt=New-Object System.Data.DataTable;(New-Object System.Data.SqlClient.SqlDataAdapter $c).Fill($dt)|Out-Null;,$dt.Rows }

# jra-card 軸(EXPORT) と ベイズ確度(6>&1ヘッダ)
$axisOf=@{}
$export = & 'C:\jra\tools\jra-card.ps1' -Date $D -Venue $V -ExportBets -ExportN 5 2>$null | Out-String
foreach($ln in ($export -split "`n")){ if($ln -match '^EXPORT\|(\d+)\|'){ $r=[int]$Matches[1]; $f=$ln.Trim() -split '\|'; if($f.Count -ge 4){ $axisOf[$r]=[int]($f[3] -replace '\D') } } }
$tierOf=@{}; $fukuOf=@{}
$full = & 'C:\jra\tools\jra-card.ps1' -Date $D -Venue $V 2>$null 6>&1 | Out-String
foreach($ln in ($full -split "`n")){ if($ln -match '^--- (\d+)R '){ $r=[int]$Matches[1]; if($ln -match '軸確度:(\S+?)[\s\]]'){$tierOf[$r]=$Matches[1]}; if($ln -match '複勝確率:([0-9]+)%'){$fukuOf[$r]=$Matches[1]} } }

"=== 2025-06-28 小倉 全12R 予想vs結果 突合 ==="
"R  距離種別 条件        確度   軸(着)  コ1位(着) 1人気(着)  決着1-3着[馬番/四角/コ/人気]                 型"
'-'*118
$rows=@()
foreach($rno in 1..12){
  $meta=Q "SELECT TOP 1 距離 dist,コース種別 sf,条件 jk FROM dbo.レース情報 WHERE 開催日='$D' AND 開催場所=N'$V' AND レース番号=$rno"
  if($meta.Count -eq 0){continue}
  $dist=[int]$meta[0].dist; $sf=[string]$meta[0].sf; $jk=([string]$meta[0].jk)
  $field=[int](Q "SELECT COUNT(*) n FROM dbo.競走結果 WHERE 開催日='$D' AND 開催場所=N'$V' AND レース番号=$rno AND TRY_CONVERT(int,着順)>0")[0].n
  # 全馬(着/馬番/四角/コ/人気)
  $all=Q @"
SELECT TRY_CONVERT(int,k.着順) ch,k.馬番 no,TRY_CONVERT(int,k.四コーナー) c4, cp.指数順位 ord, o.人気 pop
FROM dbo.競走結果 k
LEFT JOIN (SELECT 馬番,指数順位,ROW_NUMBER() OVER(PARTITION BY 馬番 ORDER BY 取得日時 DESC) sn FROM dbo.コンピ指数 WHERE 開催日='$D' AND 開催場所=N'$V' AND レース番号=$rno) cp ON cp.馬番=k.馬番 AND cp.sn=1
LEFT JOIN (SELECT 馬番,人気,ROW_NUMBER() OVER(PARTITION BY 馬番 ORDER BY 日時 DESC) sn FROM dbo.リアルタイムオッズ WHERE 開催日='$D' AND 開催場所=N'$V' AND レース番号=$rno) o ON o.馬番=k.馬番 AND o.sn=1
WHERE k.開催日='$D' AND k.開催場所=N'$V' AND k.レース番号=$rno AND TRY_CONVERT(int,k.着順)>0
"@
  $byNo=@{}; foreach($a in $all){ $byNo[[int]$a.no]=$a }
  $top3=@($all | Where-Object{ $_.ch -le 3 } | Sort-Object ch)
  # 決着型: 1-3着の平均四角/頭数
  $c4s=@($top3 | Where-Object{ $_.c4 -ne $null -and "$($_.c4)" -ne '' } | ForEach-Object{ [int]$_.c4 })
  $avgc4= if($c4s.Count){ ($c4s|Measure-Object -Average).Average }else{ 0 }
  $ratio= if($field){ $avgc4/$field }else{0}
  $kata= if($ratio -le 0 -and $c4s.Count -eq 0){'?'}elseif($ratio -le 0.33){'前残り'}elseif($ratio -ge 0.55){'差し'}else{'中位'}
  # コ1位/1人気/軸の着
  $co1=($all|Where-Object{ "$($_.ord)" -eq '1' }|Select-Object -First 1); $co1ch= if($co1){[int]$co1.ch}else{0}; $co1no= if($co1){[int]$co1.no}else{0}
  $pp1=($all|Where-Object{ "$($_.pop)" -eq '1' }|Select-Object -First 1); $pp1ch= if($pp1){[int]$pp1.ch}else{0}; $pp1no= if($pp1){[int]$pp1.no}else{0}
  $axno= if($axisOf.ContainsKey($rno)){$axisOf[$rno]}else{0}; $axch= if($axno -and $byNo.ContainsKey($axno)){[int]$byNo[$axno].ch}else{99}
  $t3str=($top3 | ForEach-Object{ $b=$_; "{0}着{1}(四{2}/コ{3}/{4}人)" -f $b.ch,$b.no,"$($b.c4)","$($b.ord)","$($b.pop)" }) -join ' '
  $tier= if($tierOf.ContainsKey($rno)){$tierOf[$rno]}else{'-'}; $fk= if($fukuOf.ContainsKey($rno)){$fukuOf[$rno]}else{''}
  "{0,2} {1,4}{2,-2}{3,-9} {4,-4}{5,3} 軸{6,2}(着{7}) コ1={8,2}(着{9}) 人1={10,2}(着{11})  {12,-44} {13}" -f $rno,$dist,$sf,$jk.Substring(0,[Math]::Min(9,$jk.Length)),$tier,$fk,$axno,$(if($axch -eq 99){'-'}else{$axch}),$co1no,$co1ch,$pp1no,$pp1ch,$t3str,$kata
  $rows += [pscustomobject]@{r=$rno;dist=$dist;sf=$sf;jk=$jk;tier=$tier;field=$field;axno=$axno;axch=$axch;co1ch=$co1ch;pp1ch=$pp1ch;kata=$kata;ratio=$ratio}
}
'-'*118
# 集計
$n=$rows.Count
$axHit=@($rows|Where-Object{$_.axch -le 3}).Count
$co1Hit=@($rows|Where-Object{$_.co1ch -ge 1 -and $_.co1ch -le 3}).Count
$pp1Hit=@($rows|Where-Object{$_.pp1ch -ge 1 -and $_.pp1ch -le 3}).Count
$mae=@($rows|Where-Object{$_.kata -eq '前残り'}).Count; $sashi=@($rows|Where-Object{$_.kata -eq '差し'}).Count; $chu=@($rows|Where-Object{$_.kata -eq '中位'}).Count
"集計({0}R): jra-card軸複勝{1}/{2}  コンピ1位複勝{3}/{2}  1番人気複勝{4}/{2}" -f $n,$axHit,$n,$co1Hit,$pp1Hit
"決着型: 前残り{0} / 中位{1} / 差し{2}" -f $mae,$chu,$sashi
# 種別×型
"ダ前残り={0} ダ差し={1} 芝前残り={2} 芝差し={3}" -f @($rows|Where-Object{$_.sf -like '*ダ*' -and $_.kata -eq '前残り'}).Count,@($rows|Where-Object{$_.sf -like '*ダ*' -and $_.kata -eq '差し'}).Count,@($rows|Where-Object{$_.sf -like '*芝*' -and $_.kata -eq '前残り'}).Count,@($rows|Where-Object{$_.sf -like '*芝*' -and $_.kata -eq '差し'}).Count
$cn.Close()
