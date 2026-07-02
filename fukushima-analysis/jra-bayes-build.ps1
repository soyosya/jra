# h2h順位を含む特徴量CSVを生成。競走結果を全ロード→インメモリでh2h再現(blendと同一: recent5/183日, ±8%clip, 共通相手Median, 降順順位)。
# 出力 C:\jra\fukushima-analysis\jra_bayes_feat.csv : yr,rb,ps,idx,ib,cb,hr,hb,fuku
param([int]$PerYearCap=1200, [int]$RecentN=5, [int]$RecentDays=183)
$ErrorActionPreference='Stop'
$sw=[System.Diagnostics.Stopwatch]::StartNew()
$cs=(Get-Content 'C:\jra\共通\appsettings.json' -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
function Median($lst){ $n=$lst.Count; if($n -eq 0){return $null}; $s=[double[]]($lst|Sort-Object); if($n%2 -eq 1){return $s[[int](($n-1)/2)]}; return ($s[$n/2-1]+$s[$n/2])/2.0 }

# ---- 1) 対象レース(2022+,非ばんえい,コンピ有)を列挙→年別サンプル ----
$cn=New-Object System.Data.SqlClient.SqlConnection $cs; $cn.Open()
$c=$cn.CreateCommand(); $c.CommandTimeout=600
$c.CommandText=@"
SELECT 開催場所 v, CONVERT(varchar(10),開催日,23) d, レース番号 r, YEAR(開催日) yr
FROM (SELECT DISTINCT 開催場所,開催日,レース番号 FROM dbo.コンピ指数 WHERE 開催日>='2022-01-01' AND 開催場所 NOT LIKE '%ば') t
ORDER BY d, v, r
"@
$rd=$c.ExecuteReader()
$byYear=@{}
while($rd.Read()){
  $yr=[int]$rd['yr']; if(-not $byYear.ContainsKey($yr)){$byYear[$yr]=New-Object System.Collections.Generic.List[object]}
  $byYear[$yr].Add(("{0}|{1}|{2}" -f $rd['v'],$rd['d'],$rd['r']))
}
$rd.Close()
$sampled=New-Object System.Collections.Generic.HashSet[string]
$raceYr=@{}
foreach($yr in ($byYear.Keys|Sort-Object)){
  $lst=$byYear[$yr]; $cnt=$lst.Count; $step=[math]::Max(1,[int][math]::Floor($cnt/[double]$PerYearCap))
  $take=0
  for($i=0;$i -lt $cnt;$i+=$step){ [void]$sampled.Add($lst[$i]); $raceYr[$lst[$i]]=$yr; $take++ }
  Write-Host ("  {0}: 母数{1} → サンプル{2} (step{3})" -f $yr,$cnt,$take,$step)
}
Write-Host ("サンプル対象レース計: {0}  [{1:N1}s]" -f $sampled.Count,$sw.Elapsed.TotalSeconds)

# ---- 2) 競走結果 全ロード → hist / rmap ----
$c2=$cn.CreateCommand(); $c2.CommandTimeout=1200
$c2.CommandText=@"
SELECT 開催場所 v, CONVERT(varchar(10),開催日,23) d, レース番号 r, 馬名 h,
  TRY_CONVERT(int,着順) ch, TRY_CONVERT(float,走破時計) t, TRY_CONVERT(int,四コーナー) c4
FROM dbo.競走結果
WHERE 開催日>='2021-06-01' AND 着順>0 AND 走破時計>0 AND 開催場所 NOT LIKE '%ば'
"@
$rd2=$c2.ExecuteReader()
$hist=@{}    # 馬名 -> List of object[] @(dnum,dstr,v,r,t,c4,ch)
$rmap=@{}    # key -> @{t=@{馬名->time}; win; cnt}
$rows=0
while($rd2.Read()){
  $v=[string]$rd2['v']; $d=[string]$rd2['d']; $r=[int]$rd2['r']; $h=[string]$rd2['h']
  if($rd2['t'] -is [DBNull]){continue}
  $t=[double]$rd2['t']; $ch=if($rd2['ch'] -is [DBNull]){0}else{[int]$rd2['ch']}
  $c4=if($rd2['c4'] -is [DBNull]){0}else{[int]$rd2['c4']}
  $dnum=[int]($d -replace '-','')
  $key="$v|$d|$r"
  if(-not $hist.ContainsKey($h)){$hist[$h]=New-Object System.Collections.Generic.List[object]}
  $hist[$h].Add(@($dnum,$d,$v,$r,$t,$c4,$ch))
  $rm=$rmap[$key]; if($null -eq $rm){ $rm=@{t=@{}; win=[double]::MaxValue; cnt=0}; $rmap[$key]=$rm }
  $rm.t[$h]=$t; if($t -lt $rm.win){$rm.win=$t}; $rm.cnt++
  $rows++
}
$rd2.Close()
Write-Host ("競走結果ロード: {0}行 / 馬{1} / レース{2}  [{3:N1}s]" -f $rows,$hist.Count,$rmap.Count,$sw.Elapsed.TotalSeconds)
# hist を日付降順ソート
foreach($k in @($hist.Keys)){ $hist[$k]=[System.Collections.Generic.List[object]]@($hist[$k] | Sort-Object @{e={$_[0]}} -Descending) }
Write-Host ("hist降順ソート完了  [{0:N1}s]" -f $sw.Elapsed.TotalSeconds)

# ---- 3) コンピ(最新スナップ) サンプル対象のみ ----
$c3=$cn.CreateCommand(); $c3.CommandTimeout=1200
$c3.CommandText=@"
WITH lat AS (SELECT 開催日,開催場所,レース番号,MAX(取得日時) mx FROM dbo.コンピ指数 WHERE 開催日>='2022-01-01' GROUP BY 開催日,開催場所,レース番号)
SELECT k.開催場所 v, CONVERT(varchar(10),k.開催日,23) d, k.レース番号 r, k.馬名 h, k.指数順位 rk, k.指数 idx
FROM dbo.コンピ指数 k JOIN lat l ON k.開催日=l.開催日 AND k.開催場所=l.開催場所 AND k.レース番号=l.レース番号 AND k.取得日時=l.mx
"@
$rd3=$c3.ExecuteReader()
$compi=@{}   # key -> @{馬名->@(rank,idx)}
while($rd3.Read()){
  $key=("{0}|{1}|{2}" -f $rd3['v'],$rd3['d'],$rd3['r'])
  if(-not $sampled.Contains($key)){continue}
  $cm=$compi[$key]; if($null -eq $cm){$cm=@{}; $compi[$key]=$cm}
  $hh=[string]$rd3['h']; $rk=[int]$rd3['rk']; $ix=[double]$rd3['idx']
  $cm[$hh]=@($rk,$ix)
}
$rd3.Close(); $cn.Close()
Write-Host ("コンピ(サンプル分)ロード: {0}レース  [{1:N1}s]" -f $compi.Count,$sw.Elapsed.TotalSeconds)

# ---- 4) 各サンプルレースでh2h算出→特徴量 ----
$out=New-Object System.Collections.Generic.List[string]
$out.Add('yr,rb,ps,idx,ib,cb,hr,hb,fuku')
$done=0; $emit=0
foreach($key in $sampled){
  $done++
  $rmTarget=$rmap[$key]; if($null -eq $rmTarget -or $rmTarget.cnt -lt 8){ continue }
  $cm=$compi[$key]; if($null -eq $cm){ continue }
  $parts=$key.Split('|'); $tv=$parts[0]; $td=$parts[1]; $tdnum=[int]($td -replace '-','')
  $tdmin=[int]( ([datetime]$td).AddDays(-$RecentDays).ToString('yyyyMMdd') )
  $field=@($rmTarget.t.Keys)
  $fieldSet=@{}; $field|ForEach-Object{$fieldSet[$_]=$true}
  # recentKeys per horse
  $recent=@{}
  foreach($a in $field){
    $hl=$hist[$a]; if($null -eq $hl){ $recent[$a]=@(); continue }
    $ks=New-Object System.Collections.Generic.List[string]; $cc=0
    foreach($e in $hl){ $dn=$e[0]; if($dn -ge $tdnum){continue}; if($dn -lt $tdmin){break}; $ks.Add(("{0}|{1}|{2}" -f $e[2],$e[1],$e[3])); $cc++; if($cc -ge $RecentN){break} }
    $recent[$a]=$ks
  }
  # mavg[a][x]=Median(clip rel)
  $mavg=@{}
  foreach($a in $field){
    $mavg[$a]=@{}; $tmp=@{}
    foreach($kk in $recent[$a]){
      $rr=$rmap[$kk]; if($null -eq $rr -or -not $rr.t.ContainsKey($a)){continue}
      $ta=$rr.t[$a]; $wt=$rr.win; if($wt -le 0){continue}
      foreach($x in $rr.t.Keys){ if($x -eq $a){continue}
        $rel=($rr.t[$x]-$ta)/$wt*100.0; if($rel -gt 8){$rel=8}elseif($rel -lt -8){$rel=-8}
        if(-not $tmp.ContainsKey($x)){$tmp[$x]=New-Object System.Collections.Generic.List[double]}; $tmp[$x].Add($rel) }
    }
    foreach($x in $tmp.Keys){ $mavg[$a][$x]=Median $tmp[$x] }
  }
  $h2h=@{}
  foreach($a in $field){
    $ms=New-Object System.Collections.Generic.List[double]
    foreach($b in $field){ if($a -eq $b){continue}
      $vv=New-Object System.Collections.Generic.List[double]
      if($mavg[$a].ContainsKey($b)){$vv.Add($mavg[$a][$b])}
      if($mavg[$b].ContainsKey($a)){$vv.Add(-1.0*$mavg[$b][$a])}
      if($vv.Count -gt 0){ $ms.Add((($vv|Measure-Object -Average).Average)); continue }
      $common=@($mavg[$a].Keys | Where-Object { $mavg[$b].ContainsKey($_) -and $_ -ne $a -and $_ -ne $b })
      if($common.Count -eq 0){continue}
      $fc=@($common|Where-Object{$fieldSet.ContainsKey($_)}); $use= if($fc.Count -gt 0){$fc}else{$common}
      $est=New-Object System.Collections.Generic.List[double]; foreach($co in $use){ $est.Add($mavg[$a][$co]-$mavg[$b][$co]) }
      $ms.Add((Median $est))
    }
    if($ms.Count -ge 1){ $h2h[$a]=($ms|Measure-Object -Average).Average }
  }
  $h2hRk=@{}; $i=1; foreach($kv in ($h2h.GetEnumerator()|Sort-Object Value -Descending)){ $h2hRk[$kv.Key]=$i; $i++ }
  # feature rows
  $yr=$raceYr[$key]
  foreach($a in $field){
    $cinfo=$cm[$a]; if($null -eq $cinfo){ continue }
    $rank=$cinfo[0]; $idx=$cinfo[1]
    $chCur=$rmTarget.t.ContainsKey($a)  # always true
    # 現走着順
    $curCh=0; $hl=$hist[$a]
    # find current race entry chaku
    if($hl){ foreach($e in $hl){ if($e[0] -eq $tdnum -and $e[2] -eq $tv -and ([int]$e[3]) -eq [int]$parts[2]){ $curCh=$e[6]; break } } }
    if($curCh -le 0){ continue }
    $fuku= if($curCh -le 3){1}else{0}
    $rb= if($rank -eq 1){1}elseif($rank -le 3){2}elseif($rank -le 6){3}else{4}
    # prevStyle / prevChaku = 直前レース
    $ps=0; $cb=0
    if($hl){
      foreach($e in $hl){ if($e[0] -ge $tdnum){continue}
        $pk=("{0}|{1}|{2}" -f $e[2],$e[1],$e[3]); $prm=$rmap[$pk]; $pc4=$e[5]; $pch=$e[6]
        if($prm -and $prm.cnt -gt 0 -and $pc4 -gt 0){
          $rat=$pc4/[double]$prm.cnt
          $ps= if($pc4 -eq 1){1}elseif($rat -le 0.33){2}elseif($rat -le 0.66){3}else{4}
        } else { $ps=0 }
        $cb= if($pch -le 0){0}elseif($pch -le 3){1}elseif($pch -le 6){2}else{3}
        break
      }
    }
    $ib= if($idx -ge 85){4}elseif($idx -ge 80){3}elseif($idx -ge 75){2}else{1}
    $hr= if($h2hRk.ContainsKey($a)){$h2hRk[$a]}else{0}
    $hb= if($hr -eq 0){0}elseif($hr -eq 1){1}elseif($hr -le 3){2}elseif($hr -le 6){3}else{4}
    $out.Add(("{0},{1},{2},{3},{4},{5},{6},{7},{8}" -f $yr,$rb,$ps,$idx,$ib,$cb,$hr,$hb,$fuku))
    $emit++
  }
  if($done % 500 -eq 0){ Write-Host ("  ...{0}/{1} races, {2}行  [{3:N1}s]" -f $done,$sampled.Count,$emit,$sw.Elapsed.TotalSeconds); [Console]::Out.Flush() }
  if($done % 2000 -eq 0){ [System.IO.File]::WriteAllLines('C:\jra\fukushima-analysis\jra_bayes_feat.csv',$out) }  # 途中フラッシュ(部分データ保全)
}
[System.IO.File]::WriteAllLines('C:\jra\fukushima-analysis\jra_bayes_feat.csv',$out)
Write-Host ("=== 完了: {0}行 → C:\jra\fukushima-analysis\jra_bayes_feat.csv  [{1:N1}s] ===" -f $emit,$sw.Elapsed.TotalSeconds)
