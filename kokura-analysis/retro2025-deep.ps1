# 2025-06-28 小倉 各レースの「なぜ」分析用: 1-3着の詳細+1着/2着の前2走(距離/種別/脚質=四角/着)。
[Console]::OutputEncoding=[Text.Encoding]::UTF8
$D='2025-06-28'; $V=[char]0x5c0f+[char]0x5009
$cs='Server=192.168.168.81\SQLEXPRESS;Database=中央競馬;User Id=sa;Password=Hanasaki#2093;TrustServerCertificate=True;Connect Timeout=30'
$cn=New-Object System.Data.SqlClient.SqlConnection $cs;$cn.Open()
function Q($sql){ $c=$cn.CreateCommand();$c.CommandText=$sql;$c.CommandTimeout=300;$dt=New-Object System.Data.DataTable;(New-Object System.Data.SqlClient.SqlDataAdapter $c).Fill($dt)|Out-Null;,$dt.Rows }
function Prev($nm){
  $p=Q @"
SELECT TOP 2 CONVERT(varchar(10),k.開催日,23) d,k.開催場所 v,k.レース番号 r,TRY_CONVERT(int,k.着順) ch,TRY_CONVERT(int,k.四コーナー) c4,ri.距離 dist,ri.コース種別 sf,
 (SELECT COUNT(*) FROM dbo.競走結果 kk WHERE kk.開催日=k.開催日 AND kk.開催場所=k.開催場所 AND kk.レース番号=k.レース番号 AND TRY_CONVERT(int,kk.着順)>0) fld
FROM dbo.競走結果 k LEFT JOIN dbo.レース情報 ri ON ri.開催日=k.開催日 AND ri.開催場所=k.開催場所 AND ri.レース番号=k.レース番号 AND ri.馬番=k.馬番
WHERE k.馬名=N'$nm' AND k.開催日<'$D' AND TRY_CONVERT(int,k.着順)>0 ORDER BY k.開催日 DESC,k.レース番号 DESC
"@
  ($p | ForEach-Object{ $pos= if("$($_.c4)" -ne '' -and $_.fld){ if([int]$_.c4 -le [Math]::Ceiling([int]$_.fld*0.33)){'先'}elseif([int]$_.c4 -le [Math]::Ceiling([int]$_.fld*0.66)){'中'}else{'後'} }else{'?'}; "{0}{1}{2}着(四{3}={4})" -f $_.dist,$_.sf,$_.ch,"$($_.c4)",$pos }) -join ' / '
}
foreach($rno in 1..12){
  $meta=Q "SELECT TOP 1 距離 dist,コース種別 sf,条件 jk FROM dbo.レース情報 WHERE 開催日='$D' AND 開催場所=N'$V' AND レース番号=$rno"
  if($meta.Count -eq 0){continue}
  $fld=[int](Q "SELECT COUNT(*) n FROM dbo.競走結果 WHERE 開催日='$D' AND 開催場所=N'$V' AND レース番号=$rno AND TRY_CONVERT(int,着順)>0")[0].n
  "===== {0}R {1}{2} {3} ({4}頭) =====" -f $rno,[int]$meta[0].dist,[string]$meta[0].sf,[string]$meta[0].jk,$fld
  $t3=Q @"
SELECT TRY_CONVERT(int,k.着順) ch,k.馬番 no,k.馬名 nm,TRY_CONVERT(int,k.四コーナー) c4,k.走破時計 t,cp.指数順位 ord,cp.指数 idx,o.人気 pop
FROM dbo.競走結果 k
LEFT JOIN (SELECT 馬番,指数順位,指数,ROW_NUMBER() OVER(PARTITION BY 馬番 ORDER BY 取得日時 DESC) sn FROM dbo.コンピ指数 WHERE 開催日='$D' AND 開催場所=N'$V' AND レース番号=$rno) cp ON cp.馬番=k.馬番 AND cp.sn=1
LEFT JOIN (SELECT 馬番,人気,ROW_NUMBER() OVER(PARTITION BY 馬番 ORDER BY 日時 DESC) sn FROM dbo.リアルタイムオッズ WHERE 開催日='$D' AND 開催場所=N'$V' AND レース番号=$rno) o ON o.馬番=k.馬番 AND o.sn=1
WHERE k.開催日='$D' AND k.開催場所=N'$V' AND k.レース番号=$rno AND TRY_CONVERT(int,k.着順) BETWEEN 1 AND 3 ORDER BY ch
"@
  foreach($x in $t3){
    $pos= if("$($x.c4)" -ne '' -and $fld){ if([int]$x.c4 -le [Math]::Ceiling($fld*0.33)){'先行'}elseif([int]$x.c4 -le [Math]::Ceiling($fld*0.66)){'中団'}else{'後方'} }else{'?'}
    "{0}着 {1} 四角{2}({3}) コ{4}位 指{5} {6}人気 走破{7}" -f $x.ch,$x.nm,"$($x.c4)",$pos,"$($x.ord)","$($x.idx)","$($x.pop)",$x.t
    if($x.ch -le 2){ "     前走: " + (Prev ([string]$x.nm)) }
  }
}
$cn.Close()
