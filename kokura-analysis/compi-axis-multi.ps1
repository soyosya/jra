# コンピ1位1頭軸マルチ三連単・相手コンピ3,4,5,6 の当日成績検証
param([Parameter(Mandatory)][string]$Date,[string]$Partners='',[int]$AxisRank=0)
$mateStr = $Partners
if([string]::IsNullOrWhiteSpace($mateStr)){ $mateStr = "$env:MATE" }
if([string]::IsNullOrWhiteSpace($mateStr)){ $mateStr = '3,4,5,6' }
$mateRanks = @($mateStr -split '[,\s]+' | Where-Object{$_ -ne ''} | ForEach-Object{[int]$_})
if($AxisRank -le 0){ if("$env:AXIS" -match '^\d+$'){ $AxisRank=[int]$env:AXIS }else{ $AxisRank=1 } }
$mateRanks = @($mateRanks | Where-Object{ $_ -ne $AxisRank })   # 軸ランクは相手から除外
$cs='Server=192.168.168.81\SQLEXPRESS;Database=中央競馬;User Id=sa;Password=Hanasaki#2093;TrustServerCertificate=True;Connect Timeout=30'
$cn=New-Object System.Data.SqlClient.SqlConnection $cs;$cn.Open()
function Q($sql){ $c=$cn.CreateCommand();$c.CommandText=$sql;$c.CommandTimeout=300;$dt=New-Object System.Data.DataTable;(New-Object System.Data.SqlClient.SqlDataAdapter $c).Fill($dt)|Out-Null;,$dt.Rows }
$out=New-Object System.Collections.Generic.List[string]
$partnerRanks=@(3,4,5,6)

# 場一覧(結果あり)
$venues=Q "SELECT DISTINCT 開催場所 v FROM dbo.競走結果 WHERE 開催日='$Date' AND TRY_CONVERT(int,着順)>0"
$gCost=0.0;$gPay=0.0;$gRaces=0;$gHit=0
foreach($vr in $venues){
  $ven=[string]$vr.v
  $out.Add("========== $ven ==========")
  $vCost=0.0;$vPay=0.0;$vRaces=0;$vHit=0
  foreach($rno in 1..12){
    # 三連単払戻(=確定レースのみ)
    $pay=Q "SELECT 組番,金額 FROM dbo.払戻金 WHERE 開催日='$Date' AND 開催場所=N'$ven' AND レース番号=$rno AND 馬券=N'三連単'"
    if($pay.Count -eq 0){ continue }
    # コンピ順位→馬番
    $cp=Q "SELECT 馬番 uma,指数順位 ord FROM (SELECT 馬番,指数順位,ROW_NUMBER() OVER(PARTITION BY 馬番 ORDER BY 取得日時 DESC) sn FROM dbo.コンピ指数 WHERE 開催日='$Date' AND 開催場所=N'$ven' AND レース番号=$rno) t WHERE sn=1"
    if($cp.Count -eq 0){ $out.Add(("{0,2}R  コンピ指数なし→対象外" -f $rno)); continue }
    $rank2uma=@{}; foreach($x in $cp){ if("$($x.ord)" -ne ''){ $rank2uma[[int]$x.ord]=[int]$x.uma } }
    if(-not $rank2uma.ContainsKey($AxisRank)){ $out.Add(("{0,2}R  コンピ{1}位不明→対象外" -f $rno,$AxisRank)); continue }
    $axis=$rank2uma[$AxisRank]
    $mateNos=@(); foreach($pr in $mateRanks){ if($rank2uma.ContainsKey($pr)){ $mateNos+=$rank2uma[$pr] } }
    $k=$mateNos.Count
    if($k -lt 2){ $out.Add(("{0,2}R  相手不足({1}頭)→対象外" -f $rno,$k)); continue }
    $points=3*$k*($k-1)          # 1頭軸マルチ三連単の点数
    $cost=$points*100.0
    # 着順1-3
    $res=Q "SELECT TRY_CONVERT(int,着順) ch,馬番 uma FROM dbo.競走結果 WHERE 開催日='$Date' AND 開催場所=N'$ven' AND レース番号=$rno AND TRY_CONVERT(int,着順) IN (1,2,3) ORDER BY TRY_CONVERT(int,着順)"
    if($res.Count -lt 3){ $out.Add(("{0,2}R  着順3頭そろわず→対象外" -f $rno)); continue }
    $w1=[int]($res|Where-Object{$_.ch -eq 1}|Select-Object -First 1).uma
    $w2=[int]($res|Where-Object{$_.ch -eq 2}|Select-Object -First 1).uma
    $w3=[int]($res|Where-Object{$_.ch -eq 3}|Select-Object -First 1).uma
    $top3=@($w1,$w2,$w3)
    # 的中判定: 軸が3着内 かつ 残り2頭がともに相手(コ3-6)
    $hit=$false; $hitPay=0.0
    if($top3 -contains $axis){
      $others=@($top3|Where-Object{$_ -ne $axis})
      $allP=$true; foreach($o in $others){ if($mateNos -notcontains $o){ $allP=$false } }
      # 軸が複数該当することはない。others=2頭
      if($allP -and $others.Count -eq 2){ $hit=$true }
    }
    if($hit){
      $key="$w1→$w2→$w3"
      $prow=$pay|Where-Object{ ([string]$_.組番) -replace '\s','' -eq $key }|Select-Object -First 1
      if(-not $prow){ $prow=$pay|Select-Object -First 1 }
      $hitPay=[double]($prow.金額)
    }
    $vCost+=$cost;$vRaces++;$vPay+=$hitPay; if($hit){$vHit++}
    $mark= if($hit){"★的中 配当$([int]$hitPay)円"}else{"×"}
    $out.Add(("{0,2}R  軸コ{1}={2,2} 相手[{3}] 着順{4}→{5}→{6}  点{7} 投{8}  {9}  収支{10:+#,##0;-#,##0;0}" -f $rno,$AxisRank,$axis,($mateNos -join ','),$w1,$w2,$w3,$points,[int]$cost,$mark,($hitPay-$cost)))
  }
  $vroi= if($vCost){100.0*$vPay/$vCost}else{0}
  $out.Add(("― $ven 計: {0}R 的中{1}  投資{2:#,##0} 払戻{3:#,##0} 回収率{4:0.0}% 収支{5:+#,##0;-#,##0;0}" -f $vRaces,$vHit,$vCost,$vPay,$vroi,($vPay-$vCost)))
  $out.Add("")
  $gCost+=$vCost;$gPay+=$vPay;$gRaces+=$vRaces;$gHit+=$vHit
}
$groi= if($gCost){100.0*$gPay/$gCost}else{0}
$out.Add("========================================")
$out.Add(("【総合】$Date 全場 {0}R 的中{1}  投資{2:#,##0}円 払戻{3:#,##0}円 回収率{4:0.0}% 収支{5:+#,##0;-#,##0;0}円" -f $gRaces,$gHit,$gCost,$gPay,$groi,($gPay-$gCost)))
$cn.Close()
$dst='C:\jra\kokura-analysis\compi-axis-multi-result.txt'
Set-Content -Path $dst -Value ($out -join "`r`n") -Encoding UTF8
Write-Output "書込: $dst ($($out.Count)行)"
