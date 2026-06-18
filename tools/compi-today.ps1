<#
.SYNOPSIS
  コンピ指数で「当日の買い目」を出します。OOS検証で残った最良ロジックを実装:
  頭数≤FieldMax かつ Harville期待的中≥EhMin のレースに限り、軸=コンピ1位/相手=コンピ2..(Partners+1)位へ
  3連複(軸1-相手Partners頭)を推奨。リアルタイムオッズがあれば人気/単勝も併記し「コンピ上位×人気薄」を妙味印で表示。

.DESCRIPTION
  - コンピ順位別勝率は CalFrom〜CalTo(=対象日の前日まで)で較正→Harville期待的中に使用(リーク防止)。
  - 頭数 = その日のコンピ掲載頭数。軸/相手は最新スナップショットの指数順。
  - 3連複 相手3頭=3点(既定)。出力はレースごとの推奨買い目 + 任意で -ExportCsv。
  ばんえい除外。馬同定=馬番。

.PARAMETER Date 対象日(既定=今日)。 CalFrom/CalTo 較正期間。 FieldMax/EhMin 選別閾値。 Partners 相手頭数。 Venue 場フィルタ。 ExportCsv 出力先。
#>
[CmdletBinding()]
param(
  [string]$Date = (Get-Date).ToString('yyyy-MM-dd'),
  [string]$CalFrom = '2024-01-01',
  [string]$CalTo = '',
  [int]$FieldMax = 8,
  [double]$EhMin = 0.55,
  [int]$Partners = 3,
  [string]$Venue = '',
  [string]$ExportCsv = '',
  [switch]$Verify   # 着順と三連複払戻で推奨買い目の的中/回収を検証(過去日用)
)
$ErrorActionPreference = 'Stop'
$appsettings = Join-Path $PSScriptRoot '..\共通\appsettings.json'
$connStr = (Get-Content $appsettings -Raw -Encoding UTF8 | ConvertFrom-Json).ConnectionStrings.DefaultConnection
$conn = New-Object System.Data.SqlClient.SqlConnection($connStr); $conn.Open()
$targetDt=[datetime]$Date
if($CalTo -eq ''){ $CalTo = $targetDt.AddDays(-1).ToString('yyyy-MM-dd') }

try {
  # ===== 較正データ(過去): コンピ順位別勝率 =====
  $cmd=$conn.CreateCommand(); $cmd.CommandTimeout=600
  $cmd.CommandText=@"
WITH s AS (SELECT k.開催日,k.開催場所,k.レース番号,k.馬番,k.指数,kk.着順,
    ROW_NUMBER() OVER(PARTITION BY k.開催日,k.開催場所,k.レース番号,k.馬番 ORDER BY k.取得日時 DESC) rn
  FROM コンピ指数 k JOIN 競走結果 kk ON kk.開催場所=k.開催場所 AND kk.開催日=k.開催日 AND kk.レース番号=k.レース番号 AND kk.馬番=k.馬番
  WHERE k.開催日>=@cf AND k.開催日<=@ct AND k.指数 IS NOT NULL AND kk.着順>0 AND k.開催場所 NOT LIKE '%ば')
SELECT 開催場所,開催日,レース番号,馬番,指数,着順 FROM s WHERE rn=1
"@
  [void]$cmd.Parameters.AddWithValue('@cf',$CalFrom);[void]$cmd.Parameters.AddWithValue('@ct',$CalTo)
  $r=$cmd.ExecuteReader(); $hist=@{}
  while($r.Read()){ $key='{0}|{1:yyyy-MM-dd}|{2}' -f $r.GetString(0),$r.GetDateTime(1),$r.GetInt32(2)
    if(-not $hist.ContainsKey($key)){ $hist[$key]=@{} }; $hist[$key][[int]$r.GetInt32(3)]=@{ shisu=[int]$r.GetInt32(4); chaku=[int]$r.GetInt32(5) } }
  $r.Close()
  $MR=20; $cnt=@(0)*($MR+1); $w=@(0)*($MR+1)
  foreach($key in $hist.Keys){ $R=@($hist[$key].GetEnumerator()|Sort-Object @{e={$_.Value.shisu};Descending=$true},@{e={[int]$_.Key};Descending=$false}|ForEach-Object{[int]$_.Key})
    for($i=0;$i -lt $R.Count -and ($i+1) -le $MR;$i++){ $cnt[$i+1]++; if($hist[$key][$R[$i]].chaku -eq 1){$w[$i+1]++} } }
  $winRate=@(0.0)*($MR+1); for($i=1;$i -le $MR;$i++){ if($cnt[$i] -gt 0){ $winRate[$i]=[double]$w[$i]/$cnt[$i] } }

  # ===== 対象日のコンピ(最新スナップショット) =====
  $venSql = if($Venue -ne ''){ "AND 開催場所=@v" } else { "AND 開催場所 NOT LIKE '%ば'" }
  $cmd=$conn.CreateCommand(); $cmd.CommandTimeout=300
  $cmd.CommandText=@"
WITH s AS (SELECT 開催場所,開催日,レース番号,馬番,馬名,指数,ROW_NUMBER() OVER(PARTITION BY 開催日,開催場所,レース番号,馬番 ORDER BY 取得日時 DESC) rn
  FROM コンピ指数 WHERE 開催日=@d AND 指数 IS NOT NULL $venSql)
SELECT 開催場所,レース番号,馬番,馬名,指数 FROM s WHERE rn=1
"@
  [void]$cmd.Parameters.AddWithValue('@d',$targetDt); if($Venue -ne ''){ [void]$cmd.Parameters.AddWithValue('@v',$Venue) }
  $r=$cmd.ExecuteReader(); $today=@{}
  while($r.Read()){ $rk='{0}|{1}' -f $r.GetString(0),$r.GetInt32(1)
    if(-not $today.ContainsKey($rk)){ $today[$rk]=@{} }; $today[$rk][[int]$r.GetInt32(2)]=@{ nm=$r.GetString(3); shisu=[int]$r.GetInt32(4) } }
  $r.Close()

  # ===== 当日オッズ(あれば): リアルタイムオッズ最新 =====
  $odds=@{}
  $cmd=$conn.CreateCommand(); $cmd.CommandTimeout=120
  $cmd.CommandText=@"
WITH o AS (SELECT 開催場所,レース番号,馬番,単勝オッズ,人気,ROW_NUMBER() OVER(PARTITION BY 開催場所,レース番号,馬番 ORDER BY 日時 DESC) rn
  FROM リアルタイムオッズ WHERE 開催日=@d)
SELECT 開催場所,レース番号,馬番,単勝オッズ,人気 FROM o WHERE rn=1
"@
  [void]$cmd.Parameters.AddWithValue('@d',$targetDt)
  try { $r=$cmd.ExecuteReader(); while($r.Read()){ $rk='{0}|{1}' -f $r.GetString(0),$r.GetInt32(1)
      if(-not $odds.ContainsKey($rk)){ $odds[$rk]=@{} }
      $odds[$rk][[int]$r.GetInt32(2)]=@{ tan= if($r.IsDBNull(3)){$null}else{[double]$r.GetValue(3)}; pop= if($r.IsDBNull(4)){$null}else{[int]$r.GetValue(4)} } }; $r.Close() } catch {}

  # ===== 検証用(過去日): 着順 + 三連複払戻 =====
  $kekka=@{}; $fuku=@{}
  if($Verify){
    $cmd=$conn.CreateCommand(); $cmd.CommandTimeout=120
    $cmd.CommandText="SELECT 開催場所,レース番号,馬番,着順 FROM 競走結果 WHERE 開催日=@d AND 着順>0"
    [void]$cmd.Parameters.AddWithValue('@d',$targetDt); $r=$cmd.ExecuteReader()
    while($r.Read()){ $rk='{0}|{1}' -f $r.GetString(0),$r.GetInt32(1); if(-not $kekka.ContainsKey($rk)){$kekka[$rk]=@{}}; $kekka[$rk][[int]$r.GetInt32(2)]=[int]$r.GetInt32(3) }; $r.Close()
    $cmd=$conn.CreateCommand(); $cmd.CommandTimeout=120
    $cmd.CommandText="SELECT 開催場所,レース番号,組番,金額 FROM 払戻金 WHERE 馬券=N'三連複' AND 開催日=@d"
    [void]$cmd.Parameters.AddWithValue('@d',$targetDt); $r=$cmd.ExecuteReader()
    while($r.Read()){ $rk='{0}|{1}' -f $r.GetString(0),$r.GetInt32(1); $k=([string]$r.GetValue(2)).Trim(); if($k -eq ''){continue}
      $norm=(($k -split '-'|ForEach-Object{[int]$_}|Sort-Object) -join '-'); if(-not $fuku.ContainsKey($rk)){$fuku[$rk]=@{}}; $fuku[$rk][$norm]=[double]$r.GetValue(3) }; $r.Close()
  }
  $conn.Close()

  if($today.Count -eq 0){ Write-Host "対象日のコンピ指数がありません。先に fetch-compi で取得してください: $Date"; return }

  function TrioProb3([double]$pa,[double]$pb,[double]$pc){
    $perm=@(@($pa,$pb,$pc),@($pa,$pc,$pb),@($pb,$pa,$pc),@($pb,$pc,$pa),@($pc,$pa,$pb),@($pc,$pb,$pa)); $tot=0.0
    foreach($q in $perm){ $d1=1.0-$q[0]; if($d1 -le 0){continue}; $d2=1.0-$q[0]-$q[1]; if($d2 -le 0){continue}; $tot += $q[0]*($q[1]/$d1)*($q[2]/$d2) }; return $tot }
  function PairsIdx([int]$n){ $o=@(); for($i=0;$i -lt $n;$i++){ for($j=$i+1;$j -lt $n;$j++){ $o+=,@($i,$j) } }; return ,$o }

  Write-Host ("=== コンピ買い目 {0}{1} (選別: 頭数≤{2} & 期待的中≥{3} / 軸→相手{4}頭 3連複) ===" -f $Date,$(if($Venue){" "+$Venue}else{''}),$FieldMax,$EhMin,$Partners)
  Write-Host ("較正: {0}〜{1} (コンピ順位別勝率)" -f $CalFrom,$CalTo)
  $exp=@(); $nrec=0; $vHit=0; $vRet=0.0; $vStake=0.0; $vN=0
  foreach($rk in ($today.Keys|Sort-Object)){
    $field=$today[$rk]; $n=$field.Count
    $R=@($field.GetEnumerator()|Sort-Object @{e={$_.Value.shisu};Descending=$true},@{e={[int]$_.Key};Descending=$false}|ForEach-Object{[int]$_.Key})
    if($R.Count -lt 5){ continue }   # 期待的中フィルタは相手4頭ベース(検証EhMin=0.55に整合)。買い目の相手はPartners頭。
    $axis=$R[0]
    $praw=@{}; $sf=0.0
    foreach($u in $R){ $rk2=([array]::IndexOf($R,$u))+1; $pr= if($rk2 -ge 1 -and $rk2 -le $MR){$winRate[$rk2]}else{0.005}; if($pr -le 0){$pr=0.005}; $praw[$u]=$pr; $sf+=$pr }
    if($sf -le 0){$sf=1}; $pax=[double]$praw[$axis]/$sf
    $opp4=@($R[1..4])
    $eh=0.0; foreach($pr in (PairsIdx 4)){ $pi=[double]$praw[$opp4[$pr[0]]]/$sf; $pj=[double]$praw[$opp4[$pr[1]]]/$sf; $eh += TrioProb3 $pax $pi $pj }
    $opp=@($R[1..$Partners])   # 買い目用の相手(3連複の相手Partners頭)
    $pass = ($n -le $FieldMax -and $eh -ge $EhMin)
    $parts=$rk.Split('|'); $ven=$parts[0]; $rno=$parts[1]
    if(-not $pass){ continue }
    $nrec++

    # 人気薄印(オッズがあれば): 軸が1番人気でない、または軸単勝オッズ高め
    $oflag=''
    if($odds.ContainsKey($rk) -and $odds[$rk].ContainsKey($axis) -and $null -ne $odds[$rk][$axis].pop){
      $ap=$odds[$rk][$axis].pop; $at=$odds[$rk][$axis].tan
      if($ap -ge 3){ $oflag=" ★妙味(軸{0}番人気 単{1})" -f $ap,$at } else { $oflag=" (軸{0}番人気)" -f $ap }
    }
    $axName=$field[$axis].nm; $axS=$field[$axis].shisu
    $oppStr=($opp|ForEach-Object{ "{0}({1})" -f $_,$field[$_].shisu }) -join ' '
    # 3連複 軸-相手Partners = C(P,2)点
    $combos=@(); foreach($pr in (PairsIdx $Partners)){ $combos+= ("{0}-{1}-{2}" -f $axis,$opp[$pr[0]],$opp[$pr[1]]) }
    Write-Host ("`n{0} {1}R 頭{2} 期待的中{3}%{4}" -f $ven,$rno,$n,([Math]::Round(100*$eh,1)),$oflag)
    Write-Host ("  軸 {0} {1}(指{2})  相手 {3}" -f $axis,$axName,$axS,$oppStr)
    Write-Host ("  3連複{0}点: {1}" -f $combos.Count,($combos -join ' / '))
    foreach($cb in $combos){ $exp+=[PSCustomObject]@{ 日付=$Date; 場=$ven; レース=$rno; 券種='3連複'; 組番=$cb; 軸=$axis; 期待的中=[Math]::Round($eh,3) } }

    if($Verify -and $kekka.ContainsKey($rk)){
      $vN++; $vStake += 100.0*$combos.Count
      $top=@{}; foreach($u in $kekka[$rk].Keys){ $c=$kekka[$rk][$u]; if($c -ge 1 -and $c -le 3){ $top[$c]=$u } }
      if($top.ContainsKey(1) -and $top.ContainsKey(2) -and $top.ContainsKey(3)){
        $set=@($top[1],$top[2],$top[3]); $oppSet2=@{}; $opp|ForEach-Object{$oppSet2[$_]=$true}
        $hit = (($set -contains $axis) -and (@($set|Where-Object{$oppSet2.ContainsKey($_)}).Count -eq 2))
        $ret=0.0; if($hit){ $sk=(($set|ForEach-Object{[int]$_}|Sort-Object) -join '-'); if($fuku.ContainsKey($rk) -and $fuku[$rk].ContainsKey($sk)){ $ret=$fuku[$rk][$sk] } }
        $vRet += $ret
        $res= if($hit){ "★的中 配当{0}円 (着順 {1}-{2}-{3})" -f $ret,$top[1],$top[2],$top[3] } else { "不的中 (着順 {0}-{1}-{2})" -f $top[1],$top[2],$top[3] }
        if($hit){$vHit++}
        Write-Host ("  → {0}" -f $res)
      }
    }
  }
  Write-Host ("`n推奨レース数: {0} / 全{1}レース" -f $nrec,$today.Count)
  if($Verify -and $vN -gt 0){
    Write-Host ("`n===== 検証({0}) =====" -f $Date)
    Write-Host ("  対象 {0}レース / 的中 {1} ({2}%) / 投資 {3:N0}円 / 払戻 {4:N0}円 / 回収率 {5}%" -f `
      $vN,$vHit,([Math]::Round(100.0*$vHit/$vN,1)),$vStake,$vRet,([Math]::Round(100.0*$vRet/$vStake,1)))
  }
  if($Verify){ Write-Host ("VERIFYRAW|compi|{0}|{1}|{2}|{3}" -f $vN,$vHit,[int]$vStake,[int]$vRet) }
  if($ExportCsv -ne '' -and $exp.Count -gt 0){ $exp | Export-Csv -Path $ExportCsv -NoTypeInformation -Encoding UTF8; Write-Host ("買い目CSVを出力: {0} ({1}点)" -f $ExportCsv,$exp.Count) }
}
finally { if($conn.State -eq 'Open'){ $conn.Close() } }
