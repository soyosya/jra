# 今日のレース一覧(JSON)。JRA版。発走時刻順に 軸/軸確度/状態/自動投票/取りやめ を返す。/races用・読み取り専用。
$OutputEncoding=[Console]::OutputEncoding=[System.Text.Encoding]::UTF8
$ErrorActionPreference='SilentlyContinue'
$cs=(Get-Content 'C:\jra\共通\appsettings.json' -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
$date=(Get-Date -Format 'yyyy-MM-dd'); $ymd=(Get-Date -Format 'yyyyMMdd')
# レース単位 自動投票ON/OFF + 取りやめ 制御ファイル(JRA=C:\jra\RunnerControl)
$ctlFile='C:\jra\RunnerControl\race-autovote.json'; $disabledSet=@{}
try{ if(Test-Path $ctlFile){ $cj=Get-Content $ctlFile -Raw -Encoding UTF8|ConvertFrom-Json; if($cj -and "$($cj.date)" -eq $date){ foreach($dk in @($cj.disabled)){ if($dk){$disabledSet["$dk"]=$true} } } } }catch{}
$cancelFile='C:\jra\RunnerControl\race-cancel.json'; $cancelSet=@{}
try{ if(Test-Path $cancelFile){ $kj=Get-Content $cancelFile -Raw -Encoding UTF8|ConvertFrom-Json; if($kj -and "$($kj.date)" -eq $date){ foreach($kk in @($kj.cancelled)){ if($kk){$cancelSet["$kk"]=$true} } } } }catch{}
# 買目CSV(印=軸)
$axisOf=@{}; $betCsv="C:\temp\ipat_bets_$ymd.csv"; $hasCache=Test-Path $betCsv
if($hasCache){ foreach($b in (Import-Csv $betCsv -Encoding UTF8)){ if("$($b.axis)" -ne ''){ $axisOf["$($b.venue)|$([int]$b.race)"]=@{axis=[int]$b.axis; bt=[string]$b.bettype} } } }
$races=@()
try{
  $cn=New-Object System.Data.SqlClient.SqlConnection $cs; $cn.Open()
  function Q($sql){ $c=$cn.CreateCommand(); $c.CommandText=$sql; [void]$c.Parameters.AddWithValue('@d',$date); $dt=New-Object System.Data.DataTable;(New-Object System.Data.SqlClient.SqlDataAdapter $c).Fill($dt)|Out-Null; ,$dt }
  # レース構成(発走/頭数)+軸馬名
  $meta=Q "SELECT 開催場所 v,レース番号 r,MIN(発走時刻) post,COUNT(DISTINCT 馬番) n FROM dbo.レース情報 WHERE 開催日=@d GROUP BY 開催場所,レース番号"
  $nameOf=@{}; foreach($x in (Q "SELECT 開催場所 v,レース番号 r,馬番 u,馬名 nm FROM dbo.レース情報 WHERE 開催日=@d").Rows){ $nameOf["$($x.v)|$([int]$x.r)|$([int]$x.u)"]="$($x.nm)" }
  $fin=@{}; foreach($x in (Q "SELECT DISTINCT 開催場所 v,レース番号 r FROM dbo.競走結果 WHERE 開催日=@d AND 着順>0").Rows){ $fin["$($x.v)|$([int]$x.r)"]=$true }
  $voted=@{}; foreach($x in (Q "SELECT DISTINCT 開催場所 v,レース番号 r FROM dbo.IPAT投票履歴 WHERE 開催日=@d AND 結果=N'投票完了'").Rows){ $voted["$($x.v)|$([int]$x.r)"]=$true }
  # コンピ(軸確度算出用): レース×順位の指数
  $idxRace=@{}; foreach($x in (Q "SELECT 開催場所 v,レース番号 r,指数順位 rk,指数 idx FROM (SELECT *,ROW_NUMBER() OVER(PARTITION BY 開催場所,レース番号,馬番 ORDER BY 取得日時 DESC) sn FROM dbo.コンピ指数 WHERE 開催日=@d AND 指数順位 IS NOT NULL) t WHERE sn=1").Rows){ $k="$($x.v)|$([int]$x.r)"; if(-not $idxRace.ContainsKey($k)){$idxRace[$k]=@{}}; if($x.idx -isnot [DBNull]){$idxRace[$k][[int]$x.rk]=[int]$x.idx} }
  $cn.Close()
  foreach($m in $meta.Rows){
    $v=[string]$m.v; $r=[int]$m.r; $k="$v|$r"
    $post= if($m.post -isnot [DBNull]){([datetime]$m.post).ToString('HH:mm')}else{''}
    # 軸確度(g12/range16/idx1)
    $conf=''; $iv=$idxRace[$k]
    if($iv -and $iv.ContainsKey(1) -and $iv.ContainsKey(2)){ $g12=$iv[1]-$iv[2]; $r16= if($iv.ContainsKey(6)){$iv[1]-$iv[6]}else{$null}; $conf= if($g12 -ge 10 -or ($null -ne $r16 -and $r16 -ge 33) -or $iv[1] -ge 88){'鉄板'}elseif($g12 -le 4 -and $iv[1] -lt 76){'警戒'}else{'標準'} }
    $ax=0; $kind=''; if($axisOf.ContainsKey($k)){ $ax=$axisOf[$k].axis; $kind=$axisOf[$k].bt }
    $axName= if($ax -gt 0 -and $nameOf.ContainsKey("$k|$ax")){$nameOf["$k|$ax"]}else{''}
    $races+=[ordered]@{
      venue=$v; race=$r; post=$post; n=[int]$m.n
      axis=$ax; axisName=$axName; conf=$conf; seg=''; kind=$kind; mxtag=''
      voted=$(if($voted.ContainsKey($k)){$true}else{$false})
      finished=$(if($fin.ContainsKey($k)){$true}else{$false})
      autovote=$(if($disabledSet.ContainsKey($k)){$false}else{$true})
      cancelled=$(if($cancelSet.ContainsKey($k)){$true}else{$false})
    }
  }
  $races=@($races | Sort-Object @{e={$_.post}},@{e={$_.venue}},@{e={$_.race}})
}catch{}
[ordered]@{ date=$date; hasCache=$hasCache; count=$races.Count; races=@($races) } | ConvertTo-Json -Depth 5 -Compress
