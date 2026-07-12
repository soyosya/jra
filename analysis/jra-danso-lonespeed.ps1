<#
  単騎速×分散の交差をサンプル拡大して検定(全JRA2022-26)。軸(コ1)限定でなく「フィールドの単騎速馬」をそのコンピ帯別に評価。
  仮説: 指数が平坦(混戦)ほど単騎速の展開優位が過小評価され効く=単騎速リフト(単騎速馬の複勝率-同コンピ帯同分散帯ベース)が混戦で最大か。
  分散帯(堅/中/混戦)×コンピ帯(コ1/コ2-3/コ4-6/コ7+)で 単騎速馬 vs ベース(全馬)の複勝率/単複回収を年別に。leak無(コンピ/脚質=事前)。
#>
[Console]::OutputEncoding=[Text.Encoding]::UTF8
$connStr=(Get-Content (Join-Path $PSScriptRoot '..\共通\appsettings.json') -Raw -Encoding UTF8 | ConvertFrom-Json).ConnectionStrings.DefaultConnection
$cn=New-Object System.Data.SqlClient.SqlConnection $connStr;$cn.Open();$c=$cn.CreateCommand();$c.CommandTimeout=600
function Q($sql){ $c.CommandText=$sql; $r=$c.ExecuteReader(); $t=New-Object System.Data.DataTable; $t.Load($r); ,$t }
$sw=[Diagnostics.Stopwatch]::StartNew()
$rows=Q "SELECT k.馬名 nm,k.開催場所 v,CONVERT(varchar(10),k.開催日,23) d,k.レース番号 r,k.馬番 no,TRY_CONVERT(int,k.着順) ch,TRY_CONVERT(int,k.四コーナー) c4 FROM dbo.競走結果 k WHERE k.開催日>='2020-06-01' AND TRY_CONVERT(int,k.着順)>0"
$fld=@{}; foreach($x in $rows.Rows){ $k="$($x.v)|$($x.d)|$($x.r)"; if($fld.ContainsKey($k)){$fld[$k]++}else{$fld[$k]=1} }
$byHorse=@{}
foreach($x in $rows.Rows){ $nm=[string]$x.nm; if(-not $byHorse.ContainsKey($nm)){ $byHorse[$nm]=New-Object System.Collections.Generic.List[object] }
  $n=$fld["$($x.v)|$($x.d)|$($x.r)"]
  $sty= if($x.c4 -is [DBNull] -or $n -le 1){ '' } else { $c4=[int]$x.c4; $rat=$c4/[double]$n; if($c4 -le 1){'逃'}elseif($rat -le 0.34){'先'}elseif($rat -le 0.66){'差'}else{'追'} }
  $byHorse[$nm].Add([pscustomobject]@{ d=[string]$x.d;r=[int]$x.r;sty=$sty }) }
foreach($nm in @($byHorse.Keys)){ $byHorse[$nm]=@($byHorse[$nm]|Sort-Object d,r) }
function PrevStyle($nm,$d){ if(-not $byHorse.ContainsKey($nm)){return ''}; $h=$byHorse[$nm]; for($i=$h.Count-1;$i -ge 0;$i--){ if($h[$i].d -lt $d -and $h[$i].sty -ne ''){ return $h[$i].sty } }; return '' }
$cprk=@{}; $cpv=@{}; foreach($x in (Q "SELECT 開催場所 v,CONVERT(varchar(10),開催日,23) d,レース番号 r,馬名 nm,指数順位 rk,CAST(指数 AS int) val FROM (SELECT 開催場所,開催日,レース番号,馬名,指数順位,指数,ROW_NUMBER() OVER(PARTITION BY 開催場所,開催日,レース番号,馬名 ORDER BY 取得日時 DESC) sn FROM dbo.コンピ指数 WHERE 開催日>='2022-01-01' AND 指数順位 IS NOT NULL AND 指数 IS NOT NULL) z WHERE sn=1").Rows){ $k="$($x.v)|$($x.d)|$($x.r)|$($x.nm)"; $cprk[$k]=[int]$x.rk; $cpv[$k]=[int]$x.val }
$tan=@{};$fuku=@{}; foreach($x in (Q "SELECT 開催場所 v,CONVERT(varchar(10),開催日,23) d,レース番号 r,馬券 bk,組番 kb,TRY_CAST(金額 AS int) kin FROM dbo.払戻金 WHERE 開催日>='2022-01-01' AND 馬券 IN (N'単勝',N'複勝')").Rows){ $no=0; if([int]::TryParse(("$($x.kb)").Trim(),[ref]$no)){ $kk="$($x.v)|$($x.d)|$($x.r)|$no"; if("$($x.bk)" -eq '単勝'){$tan[$kk]=[int]$x.kin}else{$fuku[$kk]=[int]$x.kin} } }
Write-Host ("履歴馬{0} コンピ{1}  [{2:N0}s]" -f $byHorse.Count,$cprk.Count,$sw.Elapsed.TotalSeconds)
$races=@{}
foreach($x in $rows.Rows){ if($x.d -lt '2022-01-01'){continue}; $rk="$($x.v)|$($x.d)|$($x.r)"; $ck="$rk|$($x.nm)"; if(-not $cprk.ContainsKey($ck)){continue}
  if(-not $races.ContainsKey($rk)){ $races[$rk]=New-Object System.Collections.Generic.List[object] }
  $races[$rk].Add([pscustomobject]@{ nm=[string]$x.nm; no=[int]$x.no; ch=[int]$x.ch; rk=$cprk[$ck]; val=$cpv[$ck]; pstyle=(PrevStyle ([string]$x.nm) ([string]$x.d)) }) }
function SD($arr){ if($arr.Count -lt 2){return 0}; $m=($arr|Measure-Object -Average).Average; $s=0; foreach($z in $arr){ $s+=($z-$m)*($z-$m) }; [math]::Sqrt($s/$arr.Count) }
$acc=@{}
function Add($k,$t3,$win,$tp,$fp){ if(-not $acc.ContainsKey($k)){ $acc[$k]=@{n=0;t3=0;win=0;inv=0;tan=0;fuk=0} }; $a=$acc[$k]; $a.n++; if($t3){$a.t3++}; if($win){$a.win++}; $a.inv+=100; $a.tan+=$tp; $a.fuk+=$fp }
function AddY($k,$yr,$t3,$win,$tp,$fp){ Add $k $t3 $win $tp $fp; Add "$k|$yr" $t3 $win $tp $fp }
function CB($rk){ if($rk -eq 1){'コ1'}elseif($rk -le 3){'コ2-3'}elseif($rk -le 6){'コ4-6'}else{'コ7+'} }
foreach($rk in $races.Keys){ $R=$races[$rk]; if($R.Count -lt 8){ continue }; $yr=($rk -split '\|')[1].Substring(0,4)
  $vals=@(($R|Sort-Object rk)|ForEach-Object{$_.val}); $sd=SD @($vals|Select-Object -First 8); $sdB= if($sd -lt 9){'混戦'}elseif($sd -lt 13){'中'}else{'堅'}
  $speed=@($R|Where-Object{ $_.pstyle -eq '逃' -or $_.pstyle -eq '先' }); $lone= if($speed.Count -eq 1){$speed[0].nm}else{''}
  foreach($h in $R){ $cb=CB $h.rk; $t3=($h.ch -le 3); $win=($h.ch -eq 1); $kk="$rk|$($h.no)"
    $tp= if($win -and $tan.ContainsKey($kk)){$tan[$kk]}else{0}; $fp= if($t3 -and $fuku.ContainsKey($kk)){$fuku[$kk]}else{0}
    AddY "base|$sdB|$cb" $yr $t3 $win $tp $fp
    if($lone -eq $h.nm){ AddY "lone|$sdB|$cb" $yr $t3 $win $tp $fp } } }
$cn.Close()
function P($a,$b){ if($b){$a/$b}else{0} }
function Row($sdB,$cb){ $L=$acc["lone|$sdB|$cb"]; $B=$acc["base|$sdB|$cb"]; if(-not $B){return}
  $lt3= if($L){P $L.t3 $L.n}else{0}; $bt3=P $B.t3 $B.n; $lift= if($L){($lt3-$bt3)*100}else{$null}
  $ln= if($L -and $L.n -ge 20){ $ty=''; foreach($y in 2022..2026){ $b=$acc["lone|$sdB|$cb|$y"]; if($b -and $b.n -ge 5){ $ty+=(" {0}:{1:P0}(n{2})" -f $y,(P $b.t3 $b.n),$b.n) } }
      "  単騎速{0,-5} n={1,4} 複勝{2,6:P1}(base{3,6:P1} 差{4,5:+0.0;-0.0}pt) 単回収{5,6:P1} 複回収{6,6:P1}`n        年別複勝{7}" -f $cb,$L.n,$lt3,$bt3,$lift,(P $L.tan $L.inv),(P $L.fuk $L.inv),$ty }
    else{ "  単騎速{0,-5} n={1,4} (少)  base複勝{2:P1}(n{3})" -f $cb,$(if($L){$L.n}else{0}),$bt3,$B.n }
  Write-Host $ln }
Write-Host "`n===== 単騎速リフト×分散帯(サンプル拡大・全JRA2022-26) ====="
Write-Host "  (単騎速馬の複勝率 - 同分散帯同コンピ帯の全馬ベース。仮説=混戦で差が最大なら指数平坦で単騎速が過小評価)"
foreach($sdB in '堅','中','混戦'){ Write-Host "`n■ 分散$sdB"; foreach($cb in 'コ1','コ2-3','コ4-6','コ7+'){ Row $sdB $cb } }
Write-Host "`n===== ★単騎速×コンピ帯 単勝/複勝回収の年別頑健性(分散中+混戦プール・堅は稀のため除外) ====="
foreach($cb in 'コ1','コ2-3','コ4-6'){
  $tot=@{n=0;inv=0;tan=0;fuk=0;t3=0}; $yr=@{}; foreach($y in 2022..2026){ $yr["$y"]=@{n=0;inv=0;tan=0} }
  foreach($s in '中','混戦'){ $b=$acc["lone|$s|$cb"]; if($b){ $tot.n+=$b.n;$tot.inv+=$b.inv;$tot.tan+=$b.tan;$tot.fuk+=$b.fuk;$tot.t3+=$b.t3 }
    foreach($y in 2022..2026){ $by=$acc["lone|$s|$cb|$y"]; if($by){ $yr["$y"].n+=$by.n;$yr["$y"].inv+=$by.inv;$yr["$y"].tan+=$by.tan } } }
  if($tot.inv -gt 0){ $ln=("  単騎速{0,-5} n={1,4} 複勝{2:P1} 単回収{3:P1} 複回収{4:P1}  単年別:" -f $cb,$tot.n,(P $tot.t3 $tot.n),(P $tot.tan $tot.inv),(P $tot.fuk $tot.inv))
    foreach($y in 2022..2026){ $a=$yr["$y"]; if($a.inv -gt 0){ $ln+=(" {0}:{1:P0}(n{2})" -f $y,($a.tan/$a.inv),$a.n) } }
    Write-Host $ln } }
Write-Host ("`n[{0:N0}s]" -f $sw.Elapsed.TotalSeconds)
