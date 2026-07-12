<#
  コンピ分散(序列の明確さ)×脚質(展開の序列)の交差で特徴が出るか(全JRA2022-26)。
  仮説: 指数が混戦(分散小)ほど脚質(前残り/単騎速)の展開優位が過小評価され効く。堅い(分散大)ほど脚質は無関係。
  軸=コンピ1位。軸の前走脚質(逃/先/差/追=四コーナー/頭数)・単騎速(先行馬1頭のみ)を分散帯で層別。軸複勝/勝率/単複回収・波乱を年別。leak無。
#>
[Console]::OutputEncoding=[Text.Encoding]::UTF8
$connStr=(Get-Content (Join-Path $PSScriptRoot '..\共通\appsettings.json') -Raw -Encoding UTF8 | ConvertFrom-Json).ConnectionStrings.DefaultConnection
$cn=New-Object System.Data.SqlClient.SqlConnection $connStr;$cn.Open();$c=$cn.CreateCommand();$c.CommandTimeout=600
function Q($sql){ $c.CommandText=$sql; $r=$c.ExecuteReader(); $t=New-Object System.Data.DataTable; $t.Load($r); ,$t }
$sw=[Diagnostics.Stopwatch]::StartNew()

# 競走結果(着順/四コーナー) 全期間(履歴の脚質用)
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
$ch=@{}; foreach($x in $rows.Rows){ if($x.d -ge '2022-01-01'){ $ch["$($x.v)|$($x.d)|$($x.r)|$($x.no)"]=[int]$x.ch } }
Write-Host ("履歴馬{0} コンピ{1}  [{2:N0}s]" -f $byHorse.Count,$cprk.Count,$sw.Elapsed.TotalSeconds)

$races=@{}
foreach($x in $rows.Rows){ if($x.d -lt '2022-01-01'){continue}; $rk="$($x.v)|$($x.d)|$($x.r)"; $ck="$rk|$($x.nm)"; if(-not $cprk.ContainsKey($ck)){continue}
  if(-not $races.ContainsKey($rk)){ $races[$rk]=New-Object System.Collections.Generic.List[object] }
  $races[$rk].Add([pscustomobject]@{ nm=[string]$x.nm; no=[int]$x.no; ch=[int]$x.ch; rk=$cprk[$ck]; val=$cpv[$ck]; pstyle=(PrevStyle ([string]$x.nm) ([string]$x.d)) }) }

function SD($arr){ if($arr.Count -lt 2){return 0}; $m=($arr|Measure-Object -Average).Average; $s=0; foreach($z in $arr){ $s+=($z-$m)*($z-$m) }; [math]::Sqrt($s/$arr.Count) }
$acc=@{}
function Add($k,$t3,$win,$up3,$tp,$fp){ if(-not $acc.ContainsKey($k)){ $acc[$k]=@{n=0;t3=0;win=0;up3=0;inv=0;tan=0;fuk=0} }; $a=$acc[$k]; $a.n++; if($t3){$a.t3++}; if($win){$a.win++}; if($up3){$a.up3++}; $a.inv+=100; $a.tan+=$tp; $a.fuk+=$fp }
function AddY($k,$yr,$t3,$win,$up3,$tp,$fp){ Add $k $t3 $win $up3 $tp $fp; Add "$k|$yr" $t3 $win $up3 $tp $fp }
foreach($rk in $races.Keys){ $R=$races[$rk]; if($R.Count -lt 8){ continue }; $yr=($rk -split '\|')[1].Substring(0,4)
  $byr=@($R|Sort-Object rk); $vals=@($byr|ForEach-Object{$_.val})
  $sd=SD @($vals|Select-Object -First 8); $sdB= if($sd -lt 9){'混戦'}elseif($sd -lt 13){'中'}else{'堅'}
  $ax=$byr[0]; $axCh=$ch["$rk|$($ax.no)"]; if($null -eq $axCh){continue}
  $axT3=($axCh -le 3); $axWin=($axCh -eq 1)
  $winner=$R|Where-Object{ $ch.ContainsKey("$rk|$($_.no)") -and $ch["$rk|$($_.no)"] -eq 1 }|Select-Object -First 1
  $up3=(@($R|Where-Object{ $_.rk -ge 4 -and $ch.ContainsKey("$rk|$($_.no)") -and $ch["$rk|$($_.no)"] -le 3 }).Count -ge 1)
  $tp= if($axWin -and $tan.ContainsKey("$rk|$($ax.no)")){$tan["$rk|$($ax.no)"]}else{0}
  $fp= if($axT3 -and $fuku.ContainsKey("$rk|$($ax.no)")){$fuku["$rk|$($ax.no)"]}else{0}
  $axSty= if($ax.pstyle -ne ''){$ax.pstyle}else{'?'}
  $speed=@($R|Where-Object{ $_.pstyle -eq '逃' -or $_.pstyle -eq '先' }); $lone= if($speed.Count -eq 1){$speed[0].nm}else{''}
  $axLone=($lone -eq $ax.nm); $axSpeed=($ax.pstyle -eq '逃' -or $ax.pstyle -eq '先')
  # 集計
  AddY "分散$sdB" $yr $axT3 $axWin $up3 $tp $fp
  if($axSty -ne '?'){ AddY "分散$sdB×軸$axSty" $yr $axT3 $axWin $up3 $tp $fp }
  $grp= if($axLone){'軸単騎速'}elseif($axSpeed){'軸先行(競合)'}else{'軸差し追'}
  AddY "分散$sdB×$grp" $yr $axT3 $axWin $up3 $tp $fp
}
$cn.Close()
function Pc($a,$b){ if($b){'{0,5:P1}' -f ($a/$b)}else{' — '} }
function Line($k,$lbl){ $a=$acc[$k]; if(-not $a -or $a.n -lt 120){ Write-Host ("  {0,-18} n={1,5} (少)" -f $lbl,$(if($a){$a.n}else{0})); return }
  $ty=''; foreach($y in 2022..2026){ $b=$acc["$k|$y"]; if($b -and $b.n -ge 20){ $ty+=(" {0}:複{1:P0}" -f $y,($b.fuk/$b.inv)) } }
  Write-Host ("  {0,-18} n={1,5} 軸複勝{2} 勝率{3} 波乱{4} | 単回収{5} 複回収{6}" -f $lbl,$a.n,(Pc $a.t3 $a.n),(Pc $a.win $a.n),(Pc $a.up3 $a.n),(Pc $a.tan $a.inv),(Pc $a.fuk $a.inv)) }
Write-Host "`n===== 分散帯 × 軸脚質(全JRA2022-26) ====="
foreach($s in '堅','中','混戦'){ Write-Host "`n■ 分散$s (base:)"; Line "分散$s" "  分散${s}_全体"
  foreach($st in '逃','先','差','追'){ Line "分散$s×軸$st" "  軸$st" } }
Write-Host "`n===== 分散帯 × 展開グループ(軸単騎速/軸先行競合/軸差し追) ====="
foreach($s in '堅','中','混戦'){ Write-Host "`n■ 分散$s"
  foreach($g in '軸単騎速','軸先行(競合)','軸差し追'){ Line "分散$s×$g" "  $g" } }
Write-Host "`n--- 注目セル 年別複勝回収 ---"
foreach($k in '分散混戦×軸単騎速','分散混戦×軸逃','分散混戦×軸先行(競合)','分散混戦×軸差し追'){ $a=$acc[$k]; if($a){ $ln="  $k :"; foreach($y in 2022..2026){ $b=$acc["$k|$y"]; if($b -and $b.n -ge 15){ $ln+=(" {0}:複{1:P0}/単{2:P0}(n{3})" -f $y,($b.fuk/$b.inv),($b.tan/$b.inv),$b.n) } }; Write-Host $ln } }
Write-Host ("`n[{0:N0}s]" -f $sw.Elapsed.TotalSeconds)
