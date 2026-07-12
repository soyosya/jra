<#
  消し馬の確度向上=ネガティブ要素の総ざらい(全JRA2022-26)。コンピ帯統制で「その要素があると複勝率が明確に落ちる(=コンピ過大評価)」を年別頑健に検定。
  対象コンピ帯=C1/C2-3/C4-6(消しは上位で価値)。生存(採用候補)=signal複勝率<base複勝率が全年 かつ 総delta<=-4pt かつ n>=100。
  候補: 競合先行(単騎速の逆)/斤量増/前走大敗/昇級初戦/休み明け/距離大幅変更/大外多頭/高齢。leak無(コンピ/条件=事前,前走=過去)。
#>
[Console]::OutputEncoding=[Text.Encoding]::UTF8
$connStr=(Get-Content (Join-Path $PSScriptRoot '..\共通\appsettings.json') -Raw -Encoding UTF8 | ConvertFrom-Json).ConnectionStrings.DefaultConnection
$cn=New-Object System.Data.SqlClient.SqlConnection $connStr;$cn.Open();$c=$cn.CreateCommand();$c.CommandTimeout=600
function Q($sql){ $c.CommandText=$sql; $r=$c.ExecuteReader(); $t=New-Object System.Data.DataTable; $t.Load($r); ,$t }
$sw=[Diagnostics.Stopwatch]::StartNew()

# 競走結果+レース情報 結合(着順/四コーナー/距離/種別/斤量増減/一着賞金/枠/馬齢)
$rows=Q "SELECT k.馬名 nm,k.開催場所 v,CONVERT(varchar(10),k.開催日,23) d,k.レース番号 r,k.馬番 no,TRY_CONVERT(int,k.着順) ch,TRY_CONVERT(int,k.四コーナー) c4,TRY_CAST(ri.距離 AS int) dist,ri.コース種別 s,TRY_CONVERT(int,ri.斤量増減) kzo,TRY_CAST(ri.一着賞金 AS float) prize,TRY_CONVERT(int,ri.枠番) wk,TRY_CONVERT(int,ri.馬齢) age FROM dbo.競走結果 k JOIN dbo.レース情報 ri ON ri.開催場所=k.開催場所 AND ri.開催日=k.開催日 AND ri.レース番号=k.レース番号 AND ri.馬番=k.馬番 WHERE k.開催日>='2020-06-01' AND TRY_CONVERT(int,k.着順)>0"
$fld=@{}; foreach($x in $rows.Rows){ $k="$($x.v)|$($x.d)|$($x.r)"; if($fld.ContainsKey($k)){$fld[$k]++}else{$fld[$k]=1} }
$crk=@{}; foreach($x in (Q "SELECT 開催場所 v,CONVERT(varchar(10),開催日,23) d,レース番号 r,馬名 nm,指数順位 rk FROM (SELECT 開催場所,開催日,レース番号,馬名,指数順位,ROW_NUMBER() OVER(PARTITION BY 開催場所,開催日,レース番号,馬名 ORDER BY 取得日時 DESC) sn FROM dbo.コンピ指数 WHERE 開催日>='2022-01-01' AND 指数順位 IS NOT NULL) z WHERE sn=1").Rows){ $crk["$($x.v)|$($x.d)|$($x.r)|$($x.nm)"]=[int]$x.rk }

$byHorse=@{}
foreach($x in $rows.Rows){ $nm=[string]$x.nm; if(-not $byHorse.ContainsKey($nm)){ $byHorse[$nm]=New-Object System.Collections.Generic.List[object] }
  $n=$fld["$($x.v)|$($x.d)|$($x.r)"]
  $sty= if($x.c4 -is [DBNull] -or $n -le 1){ '' } else { $c4=[int]$x.c4; $rat=$c4/[double]$n; if($c4 -le 1){'逃'}elseif($rat -le 0.34){'先'}elseif($rat -le 0.66){'差'}else{'追'} }
  $byHorse[$nm].Add([pscustomobject]@{ v=[string]$x.v;d=[string]$x.d;r=[int]$x.r;no=[int]$x.no;ch=[int]$x.ch;sty=$sty;dist=$(if($x.dist -is [DBNull]){0}else{[int]$x.dist});field=$n;kzo=$(if($x.kzo -is [DBNull]){-999}else{[int]$x.kzo});prize=$(if($x.prize -is [DBNull]){0}else{[double]$x.prize});wk=$(if($x.wk -is [DBNull]){0}else{[int]$x.wk});age=$(if($x.age -is [DBNull]){0}else{[int]$x.age}) }) }
foreach($nm in @($byHorse.Keys)){ $byHorse[$nm]=@($byHorse[$nm]|Sort-Object d,r) }
Write-Host ("馬{0} コンピ{1}  [{2:N0}s]" -f $byHorse.Count,$crk.Count,$sw.Elapsed.TotalSeconds)

# 前走脚質(フィールド競合カウント用)を今走レース単位で集計
$races=@{}
foreach($nm in $byHorse.Keys){ $h=$byHorse[$nm]
  for($i=0;$i -lt $h.Count;$i++){ $cur=$h[$i]; if($cur.d -lt '2022-01-01'){continue}
    $rk="$($cur.v)|$($cur.d)|$($cur.r)"; if(-not $races.ContainsKey($rk)){ $races[$rk]=New-Object System.Collections.Generic.List[object] }
    $ps= if($i -ge 1){ for($j=$i-1;$j -ge 0;$j--){ if($h[$j].sty -ne ''){ $h[$j].sty; break } } }else{''}
    if($ps -is [array]){$ps=$ps[0]}; if($null -eq $ps){$ps=''}
    $races[$rk].Add([pscustomobject]@{ nm=$nm; idx=$i; pstyle=$ps }) } }

$acc=@{}
function Add($k,$t3){ if(-not $acc.ContainsKey($k)){ $acc[$k]=@{n=0;t3=0} }; $a=$acc[$k]; $a.n++; if($t3){$a.t3++} }
function CBand($rk){ if($rk -eq 1){'C1'}elseif($rk -le 3){'C2-3'}elseif($rk -le 6){'C4-6'}else{'C7+'} }
function Days($d1,$d2){ ([datetime]$d1 - [datetime]$d2).Days }

foreach($rk in $races.Keys){ $field=$races[$rk]; if($field.Count -lt 6){ continue }
  $speedCnt=@($field|Where-Object{ $_.pstyle -eq '逃' -or $_.pstyle -eq '先' }).Count
  foreach($fh in $field){ $h=$byHorse[$fh.nm]; $i=$fh.idx; $cur=$h[$i]
    $ck="$($cur.v)|$($cur.d)|$($cur.r)|$($fh.nm)"; if(-not $crk.ContainsKey($ck)){continue}
    $cb=CBand $crk[$ck]; $yr=$cur.d.Substring(0,4); $t3=($cur.ch -le 3)
    Add "BASE_${cb}" $t3; Add "BASE_${cb}|$yr" $t3
    $isSpeed=($fh.pstyle -eq '逃' -or $fh.pstyle -eq '先')
    $prev= if($i -ge 1){$h[$i-1]}else{$null}
    # 各ネガ要素
    $sig=@()
    if($isSpeed -and $speedCnt -ge 4){ $sig+='競合先行' }
    if($isSpeed -and $speedCnt -ge 6){ $sig+='競合先行6+' }
    if($cur.kzo -ne -999 -and $cur.kzo -ge 1){ $sig+='斤量増' }
    if($cur.kzo -ne -999 -and $cur.kzo -ge 2){ $sig+='斤量大増2+' }
    if($cur.age -ge 6){ $sig+='高齢6+' }
    if($cur.age -ge 7){ $sig+='高齢7+' }
    if($cur.wk -eq 8 -and $cur.field -ge 14){ $sig+='大外8枠×多頭' }
    if($prev){
      $pr=$prev.ch/[double]$prev.field
      if($pr -ge 0.7){ $sig+='前走大敗(下位3割)' }
      if($prev.ch -ge 10){ $sig+='前走2桁着' }
      if($cur.prize -gt 0 -and $prev.prize -gt 0 -and $cur.prize -ge 1.3*$prev.prize){ $sig+='昇級初戦' }
      $gap=Days $cur.d $prev.d
      if($gap -ge 70){ $sig+='休明70+' }
      if($gap -ge 120){ $sig+='休明120+' }
      $dd=$cur.dist-$prev.dist
      if([math]::Abs($dd) -ge 400){ $sig+='距離大変更400+' }
      if($dd -ge 400){ $sig+='延長400+' }
      if($dd -le -400){ $sig+='短縮400+' }
    }
    foreach($s in $sig){ Add "${s}_${cb}" $t3; Add "${s}_${cb}|$yr" $t3 }
  } }
$cn.Close()
function Pc($a,$b){ if($b){'{0,5:P1}' -f ($a/$b)}else{' — '} }
function Eval($sig,$cb){ $a=$acc["${sig}_${cb}"]; $base=$acc["BASE_${cb}"]; if(-not $a -or $a.n -lt 100){ return $null }
  $sr=$a.t3/$a.n; $br=$base.t3/$base.n; $delta=($sr-$br)*100
  $allNeg=$true; $ys=''
  foreach($y in 2022..2026){ $sy=$acc["${sig}_${cb}|$y"]; $by=$acc["BASE_${cb}|$y"]; if($sy -and $sy.n -ge 15 -and $by){ $d=($sy.t3/$sy.n)-($by.t3/$by.n); if($d -ge 0){$allNeg=$false}; $ys+=(" {0}:{1:+0.0;-0.0}pt(n{2})" -f $y,($d*100),$sy.n) } }
  return @{ n=$a.n; sr=$sr; br=$br; delta=$delta; allNeg=$allNeg; ys=$ys } }
$sigs='競合先行','競合先行6+','斤量増','斤量大増2+','高齢6+','高齢7+','大外8枠×多頭','前走大敗(下位3割)','前走2桁着','昇級初戦','休明70+','休明120+','距離大変更400+','延長400+','短縮400+'
Write-Host "`n===== 消し要素ハント: コンピ帯統制の複勝率デルタ(全JRA2022-26) ====="
foreach($cb in 'C1','C2-3','C4-6'){ $base=$acc["BASE_${cb}"]
  Write-Host ("`n■ [$cb] base複勝率 {0} (n{1})" -f (Pc $base.t3 $base.n),$base.n)
  foreach($s in $sigs){ $e=Eval $s $cb; if(-not $e){ continue }
    $flag= if($e.allNeg -and $e.delta -le -4){'★消し採用候補'}elseif($e.delta -le -3){'△負'}else{''}
    Write-Host ("   {0,-16} n={1,5} 複勝{2} (base{3} Δ{4,5:+0.0;-0.0}pt) {5}" -f $s,$e.n,(Pc $e.sr 1),(Pc $e.br 1),$e.delta,$flag)
    if($e.delta -le -3){ Write-Host ("        年別Δ{0}" -f $e.ys) } } }
Write-Host ("`n[{0:N0}s]" -f $sw.Elapsed.TotalSeconds)
