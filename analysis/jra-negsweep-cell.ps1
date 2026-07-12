<#
  消し要素のセル別(種別×距離帯)ハント(全JRA2022-26)。プール検証([[jra-negsweep]])を場×距離方針([[keiba-local-ev-by-cell]])でセル分解。
  各セル×コンピ群(上位C1-3/中位C4-6)で、ネガ要素があると複勝率が何pt落ちるか+年別頑健性。プールでフラットな要素がセル特異的に効くかも検定。
  採用=全年で負 かつ 総delta<=-5pt(上位)/-4pt(中位) かつ n>=閾。leak無(コンピ/条件=事前,前走=過去)。
#>
[Console]::OutputEncoding=[Text.Encoding]::UTF8
$connStr=(Get-Content (Join-Path $PSScriptRoot '..\共通\appsettings.json') -Raw -Encoding UTF8 | ConvertFrom-Json).ConnectionStrings.DefaultConnection
$cn=New-Object System.Data.SqlClient.SqlConnection $connStr;$cn.Open();$c=$cn.CreateCommand();$c.CommandTimeout=600
function Q($sql){ $c.CommandText=$sql; $r=$c.ExecuteReader(); $t=New-Object System.Data.DataTable; $t.Load($r); ,$t }
$sw=[Diagnostics.Stopwatch]::StartNew()
function Band($d){ if($d -le 1400){'短'}elseif($d -le 1799){'マ'}elseif($d -le 2200){'中'}else{'長'} }

$rows=Q "SELECT k.馬名 nm,k.開催場所 v,CONVERT(varchar(10),k.開催日,23) d,k.レース番号 r,k.馬番 no,TRY_CONVERT(int,k.着順) ch,TRY_CONVERT(int,k.四コーナー) c4,TRY_CAST(ri.距離 AS int) dist,ri.コース種別 s,TRY_CONVERT(int,ri.斤量増減) kzo,TRY_CONVERT(int,ri.馬齢) age FROM dbo.競走結果 k JOIN dbo.レース情報 ri ON ri.開催場所=k.開催場所 AND ri.開催日=k.開催日 AND ri.レース番号=k.レース番号 AND ri.馬番=k.馬番 WHERE k.開催日>='2020-06-01' AND TRY_CONVERT(int,k.着順)>0"
$fld=@{}; foreach($x in $rows.Rows){ $k="$($x.v)|$($x.d)|$($x.r)"; if($fld.ContainsKey($k)){$fld[$k]++}else{$fld[$k]=1} }
$crk=@{}; foreach($x in (Q "SELECT 開催場所 v,CONVERT(varchar(10),開催日,23) d,レース番号 r,馬名 nm,指数順位 rk FROM (SELECT 開催場所,開催日,レース番号,馬名,指数順位,ROW_NUMBER() OVER(PARTITION BY 開催場所,開催日,レース番号,馬名 ORDER BY 取得日時 DESC) sn FROM dbo.コンピ指数 WHERE 開催日>='2022-01-01' AND 指数順位 IS NOT NULL) z WHERE sn=1").Rows){ $crk["$($x.v)|$($x.d)|$($x.r)|$($x.nm)"]=[int]$x.rk }

$byHorse=@{}
foreach($x in $rows.Rows){ $nm=[string]$x.nm; if(-not $byHorse.ContainsKey($nm)){ $byHorse[$nm]=New-Object System.Collections.Generic.List[object] }
  $n=$fld["$($x.v)|$($x.d)|$($x.r)"]
  $sty= if($x.c4 -is [DBNull] -or $n -le 1){ '' } else { $c4=[int]$x.c4; $rat=$c4/[double]$n; if($c4 -le 1){'逃'}elseif($rat -le 0.34){'先'}elseif($rat -le 0.66){'差'}else{'追'} }
  $surf= if("$($x.s)" -match 'ダ'){'ダ'}else{'芝'}
  $byHorse[$nm].Add([pscustomobject]@{ v=[string]$x.v;d=[string]$x.d;r=[int]$x.r;no=[int]$x.no;ch=[int]$x.ch;sty=$sty;surf=$surf;dist=$(if($x.dist -is [DBNull]){0}else{[int]$x.dist});field=$n;kzo=$(if($x.kzo -is [DBNull]){-999}else{[int]$x.kzo});age=$(if($x.age -is [DBNull]){0}else{[int]$x.age}) }) }
foreach($nm in @($byHorse.Keys)){ $byHorse[$nm]=@($byHorse[$nm]|Sort-Object d,r) }
Write-Host ("馬{0} コンピ{1}  [{2:N0}s]" -f $byHorse.Count,$crk.Count,$sw.Elapsed.TotalSeconds)

$races=@{}
foreach($nm in $byHorse.Keys){ $h=$byHorse[$nm]
  for($i=0;$i -lt $h.Count;$i++){ $cur=$h[$i]; if($cur.d -lt '2022-01-01'){continue}
    $rk="$($cur.v)|$($cur.d)|$($cur.r)"; if(-not $races.ContainsKey($rk)){ $races[$rk]=New-Object System.Collections.Generic.List[object] }
    $ps=''; if($i -ge 1){ for($j=$i-1;$j -ge 0;$j--){ if($h[$j].sty -ne ''){ $ps=$h[$j].sty; break } } }
    $races[$rk].Add([pscustomobject]@{ nm=$nm; idx=$i; pstyle=$ps }) } }

$acc=@{}
function Add($k,$t3){ if(-not $acc.ContainsKey($k)){ $acc[$k]=@{n=0;t3=0} }; $a=$acc[$k]; $a.n++; if($t3){$a.t3++} }
function Grp($rk){ if($rk -le 3){'上位'}elseif($rk -le 6){'中位'}else{'圏外'} }
function Days($d1,$d2){ ([datetime]$d1 - [datetime]$d2).Days }

foreach($rk in $races.Keys){ $field=$races[$rk]; if($field.Count -lt 6){ continue }
  $speedCnt=@($field|Where-Object{ $_.pstyle -eq '逃' -or $_.pstyle -eq '先' }).Count
  foreach($fh in $field){ $h=$byHorse[$fh.nm]; $i=$fh.idx; $cur=$h[$i]
    $ck="$($cur.v)|$($cur.d)|$($cur.r)|$($fh.nm)"; if(-not $crk.ContainsKey($ck)){continue}
    $grp=Grp $crk[$ck]; if($grp -eq '圏外'){continue}
    $cell="$($cur.surf)$(Band $cur.dist)"; $yr=$cur.d.Substring(0,4); $t3=($cur.ch -le 3)
    $base="$cell|$grp"; Add "BASE|$base" $t3; Add "BASE|$base|$yr" $t3
    $isSpeed=($fh.pstyle -eq '逃' -or $fh.pstyle -eq '先')
    $prev= if($i -ge 1){$h[$i-1]}else{$null}
    $sig=@()
    if($isSpeed -and $speedCnt -ge 6){ $sig+='競合先行6+' }
    if($isSpeed -and $speedCnt -ge 4){ $sig+='競合先行4+' }
    if($cur.kzo -ne -999 -and $cur.kzo -ge 2){ $sig+='斤量増2+' }
    if($cur.age -ge 7){ $sig+='高齢7+' }
    if($prev){
      if($prev.field -ge 6 -and ($prev.ch/[double]$prev.field) -ge 0.7){ $sig+='前敗' }
      $dd=$cur.dist-$prev.dist
      if($dd -ge 400){ $sig+='延長400+' }
      if($dd -le -400){ $sig+='短縮400+' }
      if($cur.surf -ne $prev.surf){ $sig+='種別替' }
      $gap=Days $cur.d $prev.d; if($gap -ge 120){ $sig+='長休120+' }
    }
    foreach($s in $sig){ Add "$s|$base" $t3; Add "$s|$base|$yr" $t3 }
  } }
$cn.Close()
function Pc($a,$b){ if($b){'{0,5:P1}' -f ($a/$b)}else{' — '} }
$sigs='前敗','長休120+','競合先行6+','競合先行4+','延長400+','短縮400+','種別替','斤量増2+','高齢7+'
function Eval($s,$base,$minN){ $a=$acc["$s|$base"]; $bs=$acc["BASE|$base"]; if(-not $a -or $a.n -lt $minN){ return $null }
  $sr=$a.t3/$a.n; $br=$bs.t3/$bs.n; $delta=($sr-$br)*100; $allNeg=$true; $ys=''
  foreach($y in 2022..2026){ $sy=$acc["$s|$base|$y"]; $by=$acc["BASE|$base|$y"]; if($sy -and $sy.n -ge 12 -and $by){ $dv=($sy.t3/$sy.n)-($by.t3/$by.n); if($dv -ge 0){$allNeg=$false}; $ys+=(" {0}:{1:+0;-0}(n{2})" -f $y,($dv*100),$sy.n) } }
  return @{ n=$a.n;delta=$delta;allNeg=$allNeg;ys=$ys } }
foreach($grp in '上位','中位'){ $minN= if($grp -eq '上位'){70}else{150}; $thr= if($grp -eq '上位'){-5}else{-4}
  Write-Host "`n============ コンピ$grp のセル別消し要素 (採用閾 Δ<=$thr pt & 全年負) ============"
  foreach($cell in 'ダ短','ダマ','ダ中','ダ長','芝短','芝マ','芝中','芝長'){ $base="$cell|$grp"; $bs=$acc["BASE|$base"]; if(-not $bs){continue}
    Write-Host ("`n■ [$cell/$grp] base複勝 {0} (n{1})" -f (Pc $bs.t3 $bs.n),$bs.n)
    foreach($s in $sigs){ $e=Eval $s $base $minN; if(-not $e){ continue }
      if($e.delta -gt -3){ continue }   # -3pt超は表示省略
      $flag= if($e.allNeg -and $e.delta -le $thr){'★採用'}else{'(非頑健/弱)'}
      Write-Host ("   {0,-10} n={1,4} Δ{2,5:+0.0;-0.0}pt {3}" -f $s,$e.n,$e.delta,$flag)
      Write-Host ("        年別{0}" -f $e.ys) } } }
Write-Host ("`n[{0:N0}s]" -f $sw.Elapsed.TotalSeconds)
