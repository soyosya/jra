<#
  コンピ断層(隣接順位の指数値段差)と指数分散(SD)で特徴が出るか調査(全JRA2022-26)。
  断層位置=上位で最大段差が何位-何位間か(=抜けている頭数=コンテンダー数)。分散=上位8頭指数のSD(競争度)。
  各層で 軸(コ1)複勝/勝率・波乱率(コ4+が1着/3着内)・単複馬連(コ1-2)三連複(コ1-2-3)回収を年別に。realized払戻・leak無(コンピ=事前)。
#>
[Console]::OutputEncoding=[Text.Encoding]::UTF8
$connStr=(Get-Content (Join-Path $PSScriptRoot '..\共通\appsettings.json') -Raw -Encoding UTF8 | ConvertFrom-Json).ConnectionStrings.DefaultConnection
$cn=New-Object System.Data.SqlClient.SqlConnection $connStr;$cn.Open();$c=$cn.CreateCommand();$c.CommandTimeout=600
function Q($sql){ $c.CommandText=$sql; $r=$c.ExecuteReader(); $t=New-Object System.Data.DataTable; $t.Load($r); ,$t }
$sw=[Diagnostics.Stopwatch]::StartNew()
function PK($a,$b){ if([int]$a -le [int]$b){"$([int]$a)-$([int]$b)"}else{"$([int]$b)-$([int]$a)"} }
function TK($a,$b,$cc){ (@([int]$a,[int]$b,[int]$cc)|Sort-Object) -join '-' }

$ch=@{}; foreach($x in (Q "SELECT 開催場所 v,CONVERT(varchar(10),開催日,23) d,レース番号 r,馬番 no,TRY_CONVERT(int,着順) c FROM dbo.競走結果 WHERE 開催日>='2022-01-01' AND TRY_CONVERT(int,着順)>0").Rows){ $ch["$($x.v)|$($x.d)|$($x.r)|$($x.no)"]=[int]$x.c }
# コンピ: 馬名→(順位,指数値)。競走結果の馬名で馬番へ
$cprk=@{}; $cpv=@{}; foreach($x in (Q "SELECT 開催場所 v,CONVERT(varchar(10),開催日,23) d,レース番号 r,馬名 nm,指数順位 rk,CAST(指数 AS int) val FROM (SELECT 開催場所,開催日,レース番号,馬名,指数順位,指数,ROW_NUMBER() OVER(PARTITION BY 開催場所,開催日,レース番号,馬名 ORDER BY 取得日時 DESC) sn FROM dbo.コンピ指数 WHERE 開催日>='2022-01-01' AND 指数順位 IS NOT NULL AND 指数 IS NOT NULL) z WHERE sn=1").Rows){ $k="$($x.v)|$($x.d)|$($x.r)|$($x.nm)"; $cprk[$k]=[int]$x.rk; $cpv[$k]=[int]$x.val }
$tan=@{};$fuku=@{};$wide=@{};$umaren=@{};$trio=@{}
foreach($x in (Q "SELECT 開催場所 v,CONVERT(varchar(10),開催日,23) d,レース番号 r,馬券 bk,組番 kb,TRY_CAST(金額 AS int) kin FROM dbo.払戻金 WHERE 開催日>='2022-01-01' AND 馬券 IN (N'単勝',N'複勝',N'ワイド',N'馬連',N'三連複')").Rows){ $rk="$($x.v)|$($x.d)|$($x.r)"; $bk="$($x.bk)"; $nums=@([regex]::Matches("$($x.kb)","\d+")|ForEach-Object{[int]$_.Value})
  if($bk -eq '三連複' -and $nums.Count -ge 3){ $trio["$rk|$(TK $nums[0] $nums[1] $nums[2])"]=[int]$x.kin }
  elseif($bk -in @('ワイド','馬連') -and $nums.Count -ge 2){ $key="$rk|$(PK $nums[0] $nums[1])"; if($bk -eq 'ワイド'){$wide[$key]=[int]$x.kin}else{$umaren[$key]=[int]$x.kin} }
  elseif($nums.Count -ge 1){ $key="$rk|$($nums[0])"; if($bk -eq '単勝'){$tan[$key]=[int]$x.kin}elseif($bk -eq '複勝'){$fuku[$key]=[int]$x.kin} } }
Write-Host ("着順{0} コンピ{1} 三連複{2}  [{3:N0}s]" -f $ch.Count,$cprk.Count,$trio.Count,$sw.Elapsed.TotalSeconds)

# レース組立(馬名で結合): 馬番/着順/順位/指数値
$nmrows=Q "SELECT 開催場所 v,CONVERT(varchar(10),開催日,23) d,レース番号 r,馬番 no,馬名 nm FROM dbo.競走結果 WHERE 開催日>='2022-01-01' AND TRY_CONVERT(int,着順)>0"
$races=@{}
foreach($x in $nmrows.Rows){ $rk="$($x.v)|$($x.d)|$($x.r)"; $ck="$rk|$($x.nm)"; if(-not $cprk.ContainsKey($ck)){continue}
  if(-not $races.ContainsKey($rk)){ $races[$rk]=New-Object System.Collections.Generic.List[object] }
  $races[$rk].Add([pscustomobject]@{ no=[int]$x.no; rk=$cprk[$ck]; val=$cpv[$ck] }) }

function SD($arr){ if($arr.Count -lt 2){return 0}; $m=($arr|Measure-Object -Average).Average; $s=0; foreach($z in $arr){ $s+=($z-$m)*($z-$m) }; [math]::Sqrt($s/$arr.Count) }
$acc=@{}
function Add($k,$axT3,$axWin,$ups3,$upW,$tp,$fp,$uh,$ur,$th,$tr){ if(-not $acc.ContainsKey($k)){ $acc[$k]=@{n=0;t3=0;win=0;ups3=0;upw=0;inv=0;tan=0;fuk=0;uh=0;uret=0;th=0;tret=0} }
  $a=$acc[$k]; $a.n++; if($axT3){$a.t3++}; if($axWin){$a.win++}; if($ups3){$a.ups3++}; if($upW){$a.upw++}; $a.inv+=100; $a.tan+=$tp; $a.fuk+=$fp; if($uh){$a.uh++;$a.uret+=$ur}; if($th){$a.th++;$a.tret+=$tr} }
function AddY($k,$yr,$a1,$a2,$a3,$a4,$a5,$a6,$a7,$a8,$a9,$a10){ Add $k $a1 $a2 $a3 $a4 $a5 $a6 $a7 $a8 $a9 $a10; Add "$k|$yr" $a1 $a2 $a3 $a4 $a5 $a6 $a7 $a8 $a9 $a10 }

foreach($rk in $races.Keys){ $R=$races[$rk]; if($R.Count -lt 8){ continue }; $yr=($rk -split '\|')[1].Substring(0,4)
  $byrk=@($R|Sort-Object rk); $vals=@($byrk|ForEach-Object{$_.val})
  # 断層位置=上位(1..5位間)で最大段差
  $maxg=-1; $dpos=1; $lim=[math]::Min(5,$vals.Count-1); for($i=0;$i -lt $lim;$i++){ $g=$vals[$i]-$vals[$i+1]; if($g -gt $maxg){ $maxg=$g; $dpos=$i+1 } }   # k=1→1-2位間
  $dansoB= if($maxg -lt 4){'断層なし(混戦)'}else{("断層{0}-{1}位間" -f $dpos,($dpos+1))}
  # 指数分散(上位8頭SD)
  $sd=SD @($vals | Select-Object -First 8)
  $sdB= if($sd -lt 9){'分散小(混戦)'}elseif($sd -lt 13){'分散中'}else{'分散大(堅)'}
  $g12=$vals[0]-$vals[1]; $r16= if($vals.Count -ge 6){$vals[0]-$vals[5]}else{$null}
  # 軸=コ1、コ2、コ3の馬番
  $a1=$byrk[0]; $a2=$byrk[1]; $a3= if($byrk.Count -ge 3){$byrk[2]}else{$null}
  $axCh=$ch["$rk|$($a1.no)"]; if($null -eq $axCh){continue}
  $axT3=($axCh -le 3); $axWin=($axCh -eq 1)
  # 波乱=コ4+が1着/3着内
  $winner=$R|Where-Object{ $ch.ContainsKey("$rk|$($_.no)") -and $ch["$rk|$($_.no)"] -eq 1 }|Select-Object -First 1
  $upW= ($winner -and $winner.rk -ge 4); $ups3=(@($R|Where-Object{ $_.rk -ge 4 -and $ch.ContainsKey("$rk|$($_.no)") -and $ch["$rk|$($_.no)"] -le 3 }).Count -ge 1)
  # 払戻
  $tp= if($axWin -and $tan.ContainsKey("$rk|$($a1.no)")){$tan["$rk|$($a1.no)"]}else{0}
  $fp= if($axT3 -and $fuku.ContainsKey("$rk|$($a1.no)")){$fuku["$rk|$($a1.no)"]}else{0}
  # 馬連コ1-2
  $t1=$R|Where-Object{ $ch.ContainsKey("$rk|$($_.no)") -and $ch["$rk|$($_.no)"] -eq 1 }|Select-Object -First 1
  $t2=$R|Where-Object{ $ch.ContainsKey("$rk|$($_.no)") -and $ch["$rk|$($_.no)"] -eq 2 }|Select-Object -First 1
  $uh=$false;$ur=0; if($t1 -and $t2){ $pr=@($t1.no,$t2.no|Sort-Object); $ax12=@($a1.no,$a2.no|Sort-Object); if($pr[0] -eq $ax12[0] -and $pr[1] -eq $ax12[1]){ $k2="$rk|$(PK $a1.no $a2.no)"; if($umaren.ContainsKey($k2)){$uh=$true;$ur=$umaren[$k2]} } }
  # 三連複コ1-2-3
  $th=$false;$tr=0; if($a3){ $top3=@($R|Where-Object{ $ch.ContainsKey("$rk|$($_.no)") -and $ch["$rk|$($_.no)"] -le 3 }|ForEach-Object{$_.no}|Sort-Object); $ax123=@($a1.no,$a2.no,$a3.no|Sort-Object); if($top3.Count -eq 3 -and ($top3 -join ',') -eq ($ax123 -join ',')){ $k3="$rk|$(TK $a1.no $a2.no $a3.no)"; if($trio.ContainsKey($k3)){$th=$true;$tr=$trio[$k3]} } }
  foreach($kk in @($dansoB,$sdB)){ AddY $kk $yr $axT3 $axWin $ups3 $upW $tp $fp $uh $ur $th $tr }
}
$cn.Close()
function Pc($a,$b){ if($b){'{0,5:P1}' -f ($a/$b)}else{' — '} }
function Line($k){ $a=$acc[$k]; if(-not $a -or $a.n -lt 200){ return }
  Write-Host ("  {0,-16} {1,5}R | 軸複勝{2} 勝率{3} 波乱(コ4+3着内){4} | 単{5} 複{6} 馬連1-2 {7} 三連複123 {8}" -f $k,$a.n,(Pc $a.t3 $a.n),(Pc $a.win $a.n),(Pc $a.ups3 $a.n),(Pc $a.tan $a.inv),(Pc $a.fuk $a.inv),(Pc $a.uret $a.inv),(Pc $a.tret $a.inv)) }
Write-Host "`n===== コンピ断層位置別(全JRA2022-26) ====="
foreach($k in ($acc.Keys | Where-Object { $_ -like '断層*' -and $_ -notlike '*|*' } | Sort-Object)){ Line $k }
Write-Host "`n===== 指数分散(上位8頭SD)別 ====="
foreach($k in '分散大(堅)','分散中','分散小(混戦)'){ Line $k }
# 年別頑健性(見出しシグナル)
function YRow($k,$fld,$lbl){ $ln="  $lbl :"; foreach($y in 2022..2026){ $b=$acc["$k|$y"]; if($b -and $b.n -ge 30){ $v= if($fld -eq '三連複'){$b.tret/$b.inv}elseif($fld -eq '複'){$b.fuk/$b.inv}else{$b.uret/$b.inv}; $ln+=(" {0}:{1:P0}(n{2})" -f $y,$v,$b.n) } }; Write-Host $ln }
Write-Host "`n--- 年別頑健性: 断層位置×三連複123回収 ---"
foreach($k in '断層1-2位間','断層3-4位間','断層5-6位間'){ if($acc.ContainsKey($k)){ YRow $k '三連複' $k } }
Write-Host "--- 年別頑健性: 分散帯×複勝回収 ---"
foreach($k in '分散大(堅)','分散中','分散小(混戦)'){ YRow $k '複' $k }
Write-Host ("`n[{0:N0}s]" -f $sw.Elapsed.TotalSeconds)
