<#
.SYNOPSIS
  h2h(走破時計の共通相手着差)に「近走クラス水準」を合成したclass補正版を、過去レースで検証。
.DESCRIPTION
  走破時計着差h2hはレース内の相対差のみで絶対的なクラス(格)を捉えず、下級大差勝ちを過大・一流の僅差勝ちを過小評価する。
  各馬の近走クラス水準(条件+競走名グレードで 新馬1〜GI9)を別スコア化し Z(h2h)+λ*Z(class) で合成。
  プレーンh2h / class補正 の最上位馬の複勝率・単回収を、対象レースのクラス帯別に比較。
.EXAMPLE
  .\h2h-class-backtest.ps1 -Venue 東京 -TestFrom 2023-07-01 -TestTo 2023-12-31 -Lambda 0.5
#>
[CmdletBinding()]
param(
  [string]$Venue='東京', [string]$TestFrom='2023-07-01', [string]$TestTo='2023-12-31',
  [int]$RecentN=5, [int]$RecentDays=183, [int]$MinCompare=4, [double]$CapPct=8.0, [double]$Lambda=0.5
)
$ErrorActionPreference='Stop'
$appsettings = Join-Path $PSScriptRoot '..\共通\appsettings.json'
$connStr = (Get-Content $appsettings -Raw -Encoding UTF8 | ConvertFrom-Json).ConnectionStrings.DefaultConnection
$conn = New-Object System.Data.SqlClient.SqlConnection($connStr); $conn.Open()
function Q([string]$sql,[hashtable]$p){ $c=$conn.CreateCommand(); $c.CommandTimeout=600; $c.CommandText=$sql; foreach($k in $p.Keys){[void]$c.Parameters.AddWithValue($k,$p[$k])}
  $r=$c.ExecuteReader(); $o=@(); while($r.Read()){ $h=@{}; for($i=0;$i -lt $r.FieldCount;$i++){$h[$r.GetName($i)]=$r.GetValue($i)}; $o+=[PSCustomObject]$h }; $r.Close(); return ,$o }
function Median($a){ $s=@($a|Sort-Object); $n=$s.Count; if($n -eq 0){return $null}; if($n%2 -eq 1){return [double]$s[[int](($n-1)/2)]}; return ([double]$s[$n/2-1]+[double]$s[$n/2])/2.0 }
function ZMap($m){ $v=@($m.Values); $z=@{}; if($v.Count -eq 0){return $z}; $mn=($v|Measure-Object -Average).Average
  $sd= if($v.Count -gt 1){[Math]::Sqrt((($v|ForEach-Object{($_-$mn)*($_-$mn)})|Measure-Object -Sum).Sum/($v.Count-1))}else{0}
  foreach($k in $m.Keys){ $z[$k]= if($sd -gt 0){($m[$k]-$mn)/$sd}else{0.0} }; return $z }

$clsCase = @"
CASE WHEN 競走名 LIKE '%(GIII)%' THEN 7 WHEN 競走名 LIKE '%(GII)%' THEN 8 WHEN 競走名 LIKE '%(GI)%' THEN 9
 WHEN 競走名 LIKE '%(L)%' OR 競走名 LIKE '%(OP)%' OR 条件 LIKE N'%オープン%' THEN 6
 WHEN 条件 LIKE N'%3勝%' THEN 5 WHEN 条件 LIKE N'%2勝%' THEN 4 WHEN 条件 LIKE N'%1勝%' THEN 3
 WHEN 条件 LIKE N'%未勝利%' THEN 2 WHEN 条件 LIKE N'%新馬%' THEN 1 ELSE 3 END
"@
try {
  $histFrom=([datetime]$TestFrom).AddDays(-$RecentDays).ToString('yyyy-MM-dd')
  Write-Host "ロード中..."
  # レースクラス(場|日|R -> level) 全場・履歴
  $rc=@{}; foreach($x in (Q "SELECT DISTINCT 開催場所,開催日,レース番号, $clsCase AS lv FROM レース情報 WHERE 開催日>=@h AND 開催日<=@t AND 条件 NOT LIKE N'%障害%'" @{'@h'=$histFrom;'@t'=$TestTo})){
    $rc["$([string]$x.開催場所)|$(([datetime]$x.開催日).ToString('yyyy-MM-dd'))|$([int]$x.レース番号)"]=[int]$x.lv }
  # 競走結果(時計/着順) 全場・履歴
  $res=@{}   # raceKey -> @{ 馬名->@{t;着} }
  foreach($x in (Q "SELECT 開催場所,開催日,レース番号,馬名,着順,走破時計 FROM 競走結果 WHERE 着順>0 AND 走破時計>0 AND 開催日>=@h AND 開催日<=@t AND 開催場所 NOT LIKE '%ば'" @{'@h'=$histFrom;'@t'=$TestTo})){
    $k="$([string]$x.開催場所)|$(([datetime]$x.開催日).ToString('yyyy-MM-dd'))|$([int]$x.レース番号)"; if(-not $res.ContainsKey($k)){$res[$k]=@{}}; $res[$k][[string]$x.馬名]=@{t=[double]$x.走破時計; c=[int]$x.着順} }
  # 各馬の近走キー(時系列, 全場)
  $horseRaces=@{}  # 馬名 -> sorted list of @{k;d}
  foreach($k in $res.Keys){ $d=($k -split '\|')[1]; foreach($nm in $res[$k].Keys){ if(-not $horseRaces.ContainsKey($nm)){$horseRaces[$nm]=@()}; $horseRaces[$nm]+=@{k=$k; d=$d} } }
  foreach($nm in @($horseRaces.Keys)){ $horseRaces[$nm]=@($horseRaces[$nm]|Sort-Object d) }
  # 払戻(単勝) 対象場
  $tan=@{}; foreach($x in (Q "SELECT 開催日,レース番号,組番,金額 FROM 払戻金 WHERE 開催場所=@v AND 馬券=N'単勝' AND 開催日>=@f AND 開催日<=@t" @{'@v'=$Venue;'@f'=$TestFrom;'@t'=$TestTo})){
    $tan["$(([datetime]$x.開催日).ToString('yyyy-MM-dd'))|$([int]$x.レース番号)|$([int]$x.組番)"]=[double]$x.金額 }

  # 対象レース(検証期間・対象場・障害除外)
  $targets=Q "SELECT DISTINCT 開催日,レース番号 FROM レース情報 WHERE 開催場所=@v AND 開催日>=@f AND 開催日<=@t AND 条件 NOT LIKE N'%障害%' ORDER BY 開催日,レース番号" @{'@v'=$Venue;'@f'=$TestFrom;'@t'=$TestTo}

  $stat=@{}  # method|band -> @{n;fuku;win;ret}
  function Add($method,$band,$placed,$won,$ret){ foreach($b in @($band,'全体')){ $kk="$method|$b"; if(-not $stat.ContainsKey($kk)){$stat[$kk]=@{n=0;f=0;w=0;r=0.0}}; $stat[$kk].n++; if($placed){$stat[$kk].f++}; if($won){$stat[$kk].w++; $stat[$kk].r+=$ret} } }

  foreach($tg in $targets){
    $d=([datetime]$tg.開催日).ToString('yyyy-MM-dd'); $rno=[int]$tg.レース番号
    $tkey="$Venue|$d|$rno"; if(-not $res.ContainsKey($tkey)){continue}
    $field=@($res[$tkey].Keys)
    if($field.Count -lt 5){continue}
    $tgBand= if($rc.ContainsKey($tkey)){ $lv=$rc[$tkey]; if($lv -ge 6){'高(OP+)'}elseif($lv -eq 5){'中(3勝)'}else{'低(2勝-)'} } else {'?'}
    # 各馬の近走margins + classScore
    $mavg=@{}; $cls=@{}
    foreach($a in $field){
      $rs=@($horseRaces[$a] | Where-Object { $_.d -lt $d -and $_.d -ge $histFrom } )
      $rs=@($rs | Select-Object -Last $RecentN)
      $tmp=@{}; $lvs=@()
      foreach($rr in $rs){ $m=$res[$rr.k]; if(-not $m.ContainsKey($a)){continue}; $ta=$m[$a].t; $wt=($m.Values|ForEach-Object{$_.t}|Measure-Object -Minimum).Minimum; if($wt -le 0){continue}
        if($rc.ContainsKey($rr.k)){ $lvs+=$rc[$rr.k] }
        foreach($x in $m.Keys){ if($x -eq $a){continue}; $rel=($m[$x].t-$ta)/$wt*100.0; if($rel -gt $CapPct){$rel=$CapPct}elseif($rel -lt -$CapPct){$rel=-$CapPct}; if(-not $tmp.ContainsKey($x)){$tmp[$x]=New-Object System.Collections.Generic.List[double]}; $tmp[$x].Add($rel) } }
      $mm=@{}; foreach($x in $tmp.Keys){ $mm[$x]=Median $tmp[$x] }; $mavg[$a]=$mm
      if($lvs.Count -gt 0){ $cls[$a]=($lvs|Measure-Object -Average).Average }
    }
    # pairwise h2h
    $fset=@{}; $field|ForEach-Object{$fset[$_]=$true}
    function PairM($a,$b){ $vv=@(); if($mavg[$a].ContainsKey($b)){$vv+=$mavg[$a][$b]}; if($mavg[$b].ContainsKey($a)){$vv+=(-1.0*$mavg[$b][$a])}; if($vv.Count -gt 0){return (($vv|Measure-Object -Average).Average)}
      $common=@($mavg[$a].Keys|Where-Object{$mavg[$b].ContainsKey($_) -and $_ -ne $a -and $_ -ne $b}); if($common.Count -eq 0){return $null}
      $fc=@($common|Where-Object{$fset.ContainsKey($_)}); $use= if($fc.Count -gt 0){$fc}else{$common}; $est=foreach($c in $use){ $mavg[$a][$c]-$mavg[$b][$c] }; return (Median $est) }
    $h2h=@{}; $ncmp=@{}
    foreach($a in $field){ $ms=@(); foreach($b in $field){ if($a -ne $b){ $m=PairM $a $b; if($null -ne $m){$ms+=$m} } }; if($ms.Count -ge $MinCompare){ $h2h[$a]=($ms|Measure-Object -Average).Average; $ncmp[$a]=$ms.Count } }
    if($h2h.Count -lt 2){continue}
    $zh=ZMap $h2h
    $clsForZ=@{}; foreach($a in $h2h.Keys){ if($cls.ContainsKey($a)){$clsForZ[$a]=$cls[$a]} }
    $zc=ZMap $clsForZ
    # 選定: plain h2h / class補正(blend)
    $sel=@{}
    $sel['plain']=($h2h.GetEnumerator()|Sort-Object Value -Descending|Select-Object -First 1).Key
    $blend=@{}; foreach($a in $h2h.Keys){ $blend[$a]= $zh[$a] + $Lambda*$(if($zc.ContainsKey($a)){$zc[$a]}else{0.0}) }
    $sel['class']=($blend.GetEnumerator()|Sort-Object Value -Descending|Select-Object -First 1).Key
    foreach($method in @('plain','class')){ $pick=$sel[$method]; $info=$res[$tkey][$pick]; $placed=($info.c -le 3); $won=($info.c -eq 1)
      # 単勝払戻: 組番=該当馬の馬番。馬番は競走結果に無いのでレース情報から引く必要→簡易に着1なら配当探索
      $ret=0.0; if($won){ # 馬番探索
        $bn=Q "SELECT TOP 1 馬番 FROM 競走結果 WHERE 開催場所=@v AND 開催日=@d AND レース番号=@r AND 馬名=@h" @{'@v'=$Venue;'@d'=$d;'@r'=$rno;'@h'=$pick}
        if($bn.Count -gt 0){ $tk="$d|$rno|$([int]$bn[0].馬番)"; if($tan.ContainsKey($tk)){ $ret=$tan[$tk] } } }
      Add $method $tgBand $placed $won $ret }
  }

  Write-Host ("=== h2h class補正BT  {0}  {1}〜{2}  λ={3} ===" -f $Venue,$TestFrom,$TestTo,$Lambda)
  Write-Host ("方式      クラス帯      n   勝率   複勝率  単回収")
  foreach($method in @('plain','class')){ foreach($b in @('全体','高(OP+)','中(3勝)','低(2勝-)')){ $kk="$method|$b"; if($stat.ContainsKey($kk)){ $s=$stat[$kk]
    $win= if($s.n){100.0*$s.w/$s.n}else{0}; $fuku= if($s.n){100.0*$s.f/$s.n}else{0}; $ret= if($s.n){100.0*$s.r/($s.n*100)}else{0}
    Write-Host ("{0,-9} {1,-12} {2,4}  {3,5:N1}%  {4,5:N1}%  {5,6:N1}%" -f $method,$b,$s.n,$win,$fuku,$ret) } } }
}
finally { $conn.Close() }
