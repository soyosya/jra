# 日次深掘り振り返りツール(絶対ルール[[keiba-daily-retro-granularity]]用・再利用可能)。
# 指定日の全レースについて: 全着順(脚質)/ペース(先行頭数)/予想突合(jra軸/コ1位/1人気)/払戻/勝ち馬・2着の前走 を一括出力。
param([Parameter(Mandatory)][string]$Date,[string]$Venue='小倉',[int]$MaxR=12)
[Console]::OutputEncoding=[Text.Encoding]::UTF8
$cs='Server=192.168.168.81\SQLEXPRESS;Database=中央競馬;User Id=sa;Password=Hanasaki#2093;TrustServerCertificate=True;Connect Timeout=30'
$cn=New-Object System.Data.SqlClient.SqlConnection $cs;$cn.Open()
function Q($sql){ $c=$cn.CreateCommand();$c.CommandText=$sql;$c.CommandTimeout=300;$dt=New-Object System.Data.DataTable;(New-Object System.Data.SqlClient.SqlDataAdapter $c).Fill($dt)|Out-Null;,$dt.Rows }
function Prev($nm){ $p=Q @"
SELECT TOP 2 CONVERT(varchar(10),k.開催日,23) d,ri.距離 dist,ri.コース種別 sf,TRY_CONVERT(int,k.着順) ch,TRY_CONVERT(int,k.四コーナー) c4,
 (SELECT COUNT(*) FROM dbo.競走結果 kk WHERE kk.開催日=k.開催日 AND kk.開催場所=k.開催場所 AND kk.レース番号=k.レース番号 AND TRY_CONVERT(int,kk.着順)>0) fld
FROM dbo.競走結果 k LEFT JOIN dbo.レース情報 ri ON ri.開催日=k.開催日 AND ri.開催場所=k.開催場所 AND ri.レース番号=k.レース番号 AND ri.馬番=k.馬番
WHERE k.馬名=N'$($nm.Replace("'","''"))' AND k.開催日<'$Date' AND TRY_CONVERT(int,k.着順)>0 ORDER BY k.開催日 DESC,k.レース番号 DESC
"@
 ($p|ForEach-Object{ $ps= if("$($_.c4)" -ne '' -and $_.fld){ $rt=[double]$_.c4/[double]$_.fld; if($_.c4 -eq 1){'逃'}elseif($rt -le 0.3){'先'}elseif($rt -le 0.6){'中'}else{'後'} }else{'?'}; "$($_.dist)$($_.sf)$($_.ch)着四$($_.c4)($ps)" }) -join ' / ' }

# jra-card 軸(EXPORT) + ベイズ確度(6>&1)
$axisOf=@{}; $export=& 'C:\jra\tools\jra-card.ps1' -Date $Date -Venue $Venue -ExportBets -ExportN 5 2>$null | Out-String
foreach($ln in ($export -split "`n")){ if($ln -match '^EXPORT\|(\d+)\|'){ $r=[int]$Matches[1]; $f=$ln.Trim() -split '\|'; if($f.Count -ge 4){ $axisOf[$r]=[int]($f[3] -replace '\D') } } }
$tierOf=@{};$fukuOf=@{}; $full=& 'C:\jra\tools\jra-card.ps1' -Date $Date -Venue $Venue 2>$null 6>&1 | Out-String
foreach($ln in ($full -split "`n")){ if($ln -match '^--- (\d+)R '){ $r=[int]$Matches[1]; if($ln -match '軸確度:(\S+?)[\s\]]'){$tierOf[$r]=$Matches[1]}; if($ln -match '複勝確率:([0-9]+)%'){$fukuOf[$r]=$Matches[1]} } }

Write-Output "########## $Date $Venue 全${MaxR}R 深掘りデータ ##########"
foreach($rno in 1..$MaxR){
  $meta=Q "SELECT TOP 1 距離 dist,コース種別 sf,条件 jk FROM dbo.レース情報 WHERE 開催日='$Date' AND 開催場所=N'$Venue' AND レース番号=$rno"
  if($meta.Count -eq 0){ continue }
  $dist=[int]$meta[0].dist;$sf=[string]$meta[0].sf;$jk=[string]$meta[0].jk
  $all=Q @"
SELECT TRY_CONVERT(int,k.着順) ch,k.馬番 no,k.馬名 nm,TRY_CONVERT(int,k.四コーナー) c4,cp.指数順位 ord,cp.指数 idx,o.人気 pop,o.単勝オッズ tan
FROM dbo.競走結果 k
LEFT JOIN (SELECT 馬番,指数順位,指数,ROW_NUMBER() OVER(PARTITION BY 馬番 ORDER BY 取得日時 DESC) sn FROM dbo.コンピ指数 WHERE 開催日='$Date' AND 開催場所=N'$Venue' AND レース番号=$rno) cp ON cp.馬番=k.馬番 AND cp.sn=1
LEFT JOIN (SELECT 馬番,人気,単勝オッズ,ROW_NUMBER() OVER(PARTITION BY 馬番 ORDER BY 日時 DESC) sn FROM dbo.リアルタイムオッズ WHERE 開催日='$Date' AND 開催場所=N'$Venue' AND レース番号=$rno) o ON o.馬番=k.馬番 AND o.sn=1
WHERE k.開催日='$Date' AND k.開催場所=N'$Venue' AND k.レース番号=$rno AND TRY_CONVERT(int,k.着順)>0 ORDER BY ch
"@
  $field=$all.Count; $byNo=@{}; foreach($a in $all){ $byNo[[int]$a.no]=$a }
  # 決着型
  $t3=@($all|Where-Object{$_.ch -le 3}); $c4s=@($t3|Where-Object{"$($_.c4)" -ne ''}|ForEach-Object{[int]$_.c4})
  $ratio= if($c4s.Count -and $field){ (($c4s|Measure-Object -Average).Average)/$field }else{0}
  $kata= if($c4s.Count -eq 0){'?'}elseif($ratio -le 0.33){'前残り'}elseif($ratio -ge 0.55){'差し'}else{'中位'}
  # ペース(前走脚質: この日の全出走馬)
  $hana=0;$sen=0
  foreach($a in $all){ $pv=Q "SELECT TOP 1 TRY_CONVERT(int,kk.四コーナー) pc4,(SELECT COUNT(*) FROM dbo.競走結果 k3 WHERE k3.開催日=kk.開催日 AND k3.開催場所=kk.開催場所 AND k3.レース番号=kk.レース番号 AND TRY_CONVERT(int,k3.着順)>0) fld FROM dbo.競走結果 kk WHERE kk.馬名=N'$(([string]$a.nm).Replace("'","''"))' AND kk.開催日<'$Date' AND TRY_CONVERT(int,kk.着順)>0 ORDER BY kk.開催日 DESC,kk.レース番号 DESC"
    if($pv.Count -and "$($pv[0].pc4)" -ne '' -and $pv[0].fld){ if([int]$pv[0].pc4 -eq 1){$hana++}; if([double]$pv[0].pc4/[double]$pv[0].fld -le 0.3){$sen++} } }
  $ax= if($axisOf.ContainsKey($rno)){$axisOf[$rno]}else{0}
  $co1=($all|Where-Object{"$($_.ord)" -eq '1'}|Select-Object -First 1); $pp1=($all|Where-Object{"$($_.pop)" -eq '1'}|Select-Object -First 1)
  function ChOf($no){ if($no -and $byNo.ContainsKey([int]$no)){[int]$byNo[[int]$no].ch}else{'-'} }
  $tier= if($tierOf.ContainsKey($rno)){$tierOf[$rno]}else{'-'}; $fk= if($fukuOf.ContainsKey($rno)){$fukuOf[$rno]}else{''}
  Write-Output ""
  Write-Output ("===== {0}R {1}{2} {3} ({4}頭) 確度{5}/ベイズ{6}% 決着{7} =====" -f $rno,$sf,$dist,$jk,$field,$tier,$fk,$kata)
  Write-Output ("予想: jra軸{0}(着{1}) / コ1位{2}(着{3}) / 1人気{4}(着{5})  ペース:前走ハナ{6}先行{7}/{8}頭" -f $ax,(ChOf $ax),$(if($co1){$co1.no}else{'-'}),(ChOf $(if($co1){$co1.no}else{0})),$(if($pp1){$pp1.no}else{'-'}),(ChOf $(if($pp1){$pp1.no}else{0})),$hana,$sen,$field)
  foreach($a in $all){ $ps= if("$($a.c4)" -ne '' -and $field){ $rt=[double]$a.c4/[double]$field; if($a.c4 -eq 1){'逃'}elseif($rt -le 0.33){'先'}elseif($rt -le 0.66){'中'}else{'後'} }else{'?'}
    Write-Output ("  {0,2}着 馬番{1,2} {2,-14} 四角{3,2}({4}) コ{5,2} 指{6} {7,2}人気 {8}倍" -f $a.ch,$a.no,$a.nm,"$($a.c4)",$ps,"$($a.ord)","$($a.idx)","$($a.pop)",$a.tan) }
  $pay=Q "SELECT 馬券,組番,金額 FROM dbo.払戻金 WHERE 開催日='$Date' AND 開催場所=N'$Venue' AND レース番号=$rno AND 馬券 IN (N'単勝',N'複勝',N'馬連',N'ワイド',N'三連複')"
  Write-Output ("  払戻: " + (($pay|ForEach-Object{ "$($_.馬券)$($_.組番)=$($_.金額)" }) -join ' '))
  foreach($cc in 1,2,3){ $wx=($all|Where-Object{$_.ch -eq $cc}|Select-Object -First 1); if($wx){ Write-Output ("  ${cc}着前走: " + (Prev ([string]$wx.nm))) } }
}
$cn.Close()
