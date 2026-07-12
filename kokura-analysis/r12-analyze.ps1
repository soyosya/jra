[Console]::OutputEncoding=[Text.Encoding]::UTF8
$cs='Server=192.168.168.81\SQLEXPRESS;Database=中央競馬;User Id=sa;Password=Hanasaki#2093;TrustServerCertificate=True;'
$cn=New-Object System.Data.SqlClient.SqlConnection $cs;$cn.Open()
function Q($sql){ $c=$cn.CreateCommand();$c.CommandText=$sql;$dt=New-Object System.Data.DataTable;(New-Object System.Data.SqlClient.SqlDataAdapter $c).Fill($dt)|Out-Null;,$dt.Rows }
$D='2026-06-28'; $V=[char]0x5c0f+[char]0x5009  # 小倉
"=== 6/28 小倉 12R 着順詳細 ==="
$sql=@"
SELECT TRY_CONVERT(int,k.着順) ch, k.馬番 no, k.馬名 nm, k.四コーナー c4, k.走破時計 t,
  cp.指数順位 ord, cp.指数 idx, o.人気 pop, o.単勝オッズ tan
FROM dbo.競走結果 k
LEFT JOIN (SELECT 馬番,指数順位,指数,ROW_NUMBER() OVER(PARTITION BY 馬番 ORDER BY 取得日時 DESC) sn FROM dbo.コンピ指数 WHERE 開催日='$D' AND 開催場所=N'$V' AND レース番号=12) cp ON cp.馬番=k.馬番 AND cp.sn=1
LEFT JOIN (SELECT 馬番,人気,単勝オッズ,ROW_NUMBER() OVER(PARTITION BY 馬番 ORDER BY 日時 DESC) sn FROM dbo.リアルタイムオッズ WHERE 開催日='$D' AND 開催場所=N'$V' AND レース番号=12) o ON o.馬番=k.馬番 AND o.sn=1
WHERE k.開催日='$D' AND k.開催場所=N'$V' AND k.レース番号=12 AND TRY_CONVERT(int,k.着順)>0
ORDER BY ch
"@
foreach($x in (Q $sql)){ "{0,2}着 馬番{1,2} {2,-16} 四角[{3,-9}] 時計{4} コ{5,2}位 指{6} {7,2}人気 {8}倍" -f $x.ch,$x.no,$x.nm,"$($x.c4)",$x.t,$x.ord,$x.idx,$x.pop,$x.tan }

"`n=== 上位3頭(7/13/12)の前3走(脚質=四角/着順/指数) ==="
foreach($no in 7,13,12){
  $nm=(Q "SELECT TOP 1 馬名 FROM dbo.競走結果 WHERE 開催日='$D' AND 開催場所=N'$V' AND レース番号=12 AND 馬番=$no")[0].馬名
  "--- 馬番$no $nm ---"
  $pr=@"
SELECT TOP 3 CONVERT(varchar(10),k.開催日,23) d, k.開催場所 v, k.レース番号 r, TRY_CONVERT(int,k.着順) ch, k.四コーナー c4, k.走破時計 t, ri.距離 dist, ri.コース種別 sf
FROM dbo.競走結果 k LEFT JOIN dbo.レース情報 ri ON ri.開催日=k.開催日 AND ri.開催場所=k.開催場所 AND ri.レース番号=k.レース番号 AND ri.馬番=k.馬番
WHERE k.馬名=N'$nm' AND k.開催日<'$D' AND TRY_CONVERT(int,k.着順)>0 ORDER BY k.開催日 DESC, k.レース番号 DESC
"@
  foreach($p in (Q $pr)){ "   {0} {1}{2}R {3}{4} {5}着 四角[{6}] {7}" -f $p.d,$p.v,$p.r,$p.dist,$p.sf,$p.ch,"$($p.c4)",$p.t }
}
$cn.Close()
