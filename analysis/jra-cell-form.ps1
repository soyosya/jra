<#
  コンピ不使用。純フォーム(前走セル/前走脚質/前走上り3F順位)で今走セルごとの傾向+複勝回収(実配当=+EV判定)を検証(全JRA2022-26)。
  上り3F順位=前走レース内の上り3F速さ順位/頭数(速=<=0.25/中<=0.6/遅>0.6)。脚質=前走四コーナー/頭数(逃/先/差/追)。
  前走セル遷移(今走比)=同cell/距離延長/距離短縮/種別替。単因子+三者組合せ。生存(妙味)=複回収>100が全年&n>=閾。leak無(全て前走=過去)。
#>
[Console]::OutputEncoding=[Text.Encoding]::UTF8
$connStr=(Get-Content (Join-Path $PSScriptRoot '..\共通\appsettings.json') -Raw -Encoding UTF8 | ConvertFrom-Json).ConnectionStrings.DefaultConnection
$cn=New-Object System.Data.SqlClient.SqlConnection $connStr;$cn.Open();$c=$cn.CreateCommand();$c.CommandTimeout=600
function Q($sql){ $c.CommandText=$sql; $r=$c.ExecuteReader(); $t=New-Object System.Data.DataTable; $t.Load($r); ,$t }
$sw=[Diagnostics.Stopwatch]::StartNew()
function Band($d){ if($d -le 1400){'短'}elseif($d -le 1799){'マ'}elseif($d -le 2200){'中'}else{'長'} }

# 競走結果+レース情報: 着順/四コーナー/上り3F/種別/距離
$rows=Q "SELECT k.馬名 nm,k.開催場所 v,CONVERT(varchar(10),k.開催日,23) d,k.レース番号 r,k.馬番 no,TRY_CONVERT(int,k.着順) ch,TRY_CONVERT(int,k.四コーナー) c4,TRY_CAST(k.上り3F AS float) ag,ri.コース種別 s,TRY_CAST(ri.距離 AS int) dist FROM dbo.競走結果 k JOIN dbo.レース情報 ri ON ri.開催場所=k.開催場所 AND ri.開催日=k.開催日 AND ri.レース番号=k.レース番号 AND ri.馬番=k.馬番 WHERE k.開催日>='2020-06-01' AND TRY_CONVERT(int,k.着順)>0"
# レース単位で頭数と上り3F順位を計算
$byRace=@{}
foreach($x in $rows.Rows){ $rk="$($x.v)|$($x.d)|$($x.r)"; if(-not $byRace.ContainsKey($rk)){ $byRace[$rk]=New-Object System.Collections.Generic.List[object] }; $byRace[$rk].Add($x) }
$agRank=@{}; $fldN=@{}
foreach($rk in $byRace.Keys){ $g=$byRace[$rk]; $fldN[$rk]=$g.Count
  $withAg=@($g|Where-Object{ $_.ag -isnot [DBNull] -and [double]$_.ag -gt 0 }|Sort-Object { [double]$_.ag })
  for($i=0;$i -lt $withAg.Count;$i++){ $agRank["$rk|$($withAg[$i].no)"]=$i+1 } }
# 馬別履歴
$byHorse=@{}
foreach($x in $rows.Rows){ $nm=[string]$x.nm; $rk="$($x.v)|$($x.d)|$($x.r)"; $n=$fldN[$rk]
  if(-not $byHorse.ContainsKey($nm)){ $byHorse[$nm]=New-Object System.Collections.Generic.List[object] }
  $sty= if($x.c4 -is [DBNull] -or $n -le 1){ '' } else { $c4=[int]$x.c4; $rat=$c4/[double]$n; if($c4 -le 1){'逃'}elseif($rat -le 0.34){'先'}elseif($rat -le 0.66){'差'}else{'追'} }
  $surf= if("$($x.s)" -match 'ダ'){'ダ'}else{'芝'}
  $ar= if($agRank.ContainsKey("$rk|$($x.no)")){$agRank["$rk|$($x.no)"]}else{$null}
  $agB= if($null -eq $ar -or $n -le 1){''}else{ $rt=$ar/[double]$n; if($rt -le 0.25){'速'}elseif($rt -le 0.6){'中'}else{'遅'} }
  $byHorse[$nm].Add([pscustomobject]@{ d=[string]$x.d;r=[int]$x.r;ch=[int]$x.ch;sty=$sty;surf=$surf;band=(Band ([int]$x.dist));agB=$agB }) }
foreach($nm in @($byHorse.Keys)){ $byHorse[$nm]=@($byHorse[$nm]|Sort-Object d,r) }
$fuku=@{}; foreach($x in (Q "SELECT 開催場所 v,CONVERT(varchar(10),開催日,23) d,レース番号 r,組番 kb,TRY_CAST(金額 AS int) kin FROM dbo.払戻金 WHERE 開催日>='2022-01-01' AND 馬券=N'複勝'").Rows){ $no=0; if([int]::TryParse(("$($x.kb)").Trim(),[ref]$no)){ $fuku["$($x.v)|$($x.d)|$($x.r)|$no"]=[int]$x.kin } }
Write-Host ("馬{0} レース{1}  [{2:N0}s]" -f $byHorse.Count,$byRace.Count,$sw.Elapsed.TotalSeconds)

$acc=@{}
function Add($k,$t3,$fp){ if(-not $acc.ContainsKey($k)){ $acc[$k]=@{n=0;t3=0;inv=0;fuk=0} }; $a=$acc[$k]; $a.n++; if($t3){$a.t3++}; $a.inv+=100; $a.fuk+=$fp }
function AddY($k,$yr,$t3,$fp){ Add $k $t3 $fp; Add "$k|$yr" $t3 $fp }
foreach($nm in $byHorse.Keys){ $h=$byHorse[$nm]
  for($i=1;$i -lt $h.Count;$i++){ $cur=$h[$i]; if($cur.d -lt '2022-01-01'){continue}
    $prev=$h[$i-1]; $cell="$($cur.surf)$($cur.band)"; $yr=$cur.d.Substring(0,4); $t3=($cur.ch -le 3)
    # 複勝払戻には馬番が要る→今走の馬番はhistに無い。fuku引きは別途今走行から。ここでは複勝率のみ+回収は今走行ループで。保留→下で別ループ
    $trans= if($prev.surf -ne $cur.surf){'種替'}elseif($prev.band -eq $cur.band){'同'}else{ $ord=@{'短'=1;'マ'=2;'中'=3;'長'=4}; if($ord[$cur.band] -gt $ord[$prev.band]){'延長'}else{'短縮'} }
    $ps= if($prev.sty -ne ''){$prev.sty}else{'?'}
    $pa= if($prev.agB -ne ''){$prev.agB}else{'?'}
    # 単因子(複勝率のみ・回収は別ループで馬番必要)
    AddY "$cell|base" $yr $t3 0
    if($pa -ne '?'){ AddY "$cell|上り$pa" $yr $t3 0 }
    if($ps -ne '?'){ AddY "$cell|脚$ps" $yr $t3 0 }
    AddY "$cell|遷$trans" $yr $t3 0
    if($ps -ne '?' -and $pa -ne '?'){ AddY "$cell|脚$ps×上り$pa" $yr $t3 0; AddY "$cell|遷$trans×上り$pa" $yr $t3 0 }
  } }
# 複勝回収: 今走行(馬番あり)で前走特徴を引いて回収集計
$acc2=@{}
function Add2($k,$t3,$fp){ if(-not $acc2.ContainsKey($k)){ $acc2[$k]=@{n=0;t3=0;inv=0;fuk=0} }; $a=$acc2[$k]; $a.n++; if($t3){$a.t3++}; $a.inv+=100; $a.fuk+=$fp }
function AddY2($k,$yr,$t3,$fp){ Add2 $k $t3 $fp; Add2 "$k|$yr" $t3 $fp }
foreach($x in $rows.Rows){ if($x.d -lt '2022-01-01'){continue}; $nm=[string]$x.nm; $h=$byHorse[$nm]
  # 今走インデックスを探す
  $idx=-1; for($j=0;$j -lt $h.Count;$j++){ if($h[$j].d -eq [string]$x.d -and $h[$j].r -eq [int]$x.r){ $idx=$j; break } }
  if($idx -lt 1){ continue }
  $cur=$h[$idx]; $prev=$h[$idx-1]; $cell="$($cur.surf)$($cur.band)"; $yr=([string]$x.d).Substring(0,4); $t3=([int]$x.ch -le 3)
  $fp= if($t3){ $kk="$($x.v)|$($x.d)|$($x.r)|$($x.no)"; if($fuku.ContainsKey($kk)){$fuku[$kk]}else{0} }else{0}
  $trans= if($prev.surf -ne $cur.surf){'種替'}elseif($prev.band -eq $cur.band){'同'}else{ $ord=@{'短'=1;'マ'=2;'中'=3;'長'=4}; if($ord[$cur.band] -gt $ord[$prev.band]){'延長'}else{'短縮'} }
  $ps= if($prev.sty -ne ''){$prev.sty}else{'?'}; $pa= if($prev.agB -ne ''){$prev.agB}else{'?'}
  AddY2 "$cell|base" $yr $t3 $fp
  if($pa -ne '?'){ AddY2 "$cell|上り$pa" $yr $t3 $fp }
  if($ps -ne '?'){ AddY2 "$cell|脚$ps" $yr $t3 $fp }
  AddY2 "$cell|遷$trans" $yr $t3 $fp
  if($ps -ne '?' -and $pa -ne '?'){ AddY2 "$cell|脚$ps×上り$pa" $yr $t3 $fp; AddY2 "$cell|遷$trans×上り$pa" $yr $t3 $fp }
}
$cn.Close()
function P($a,$b){ if($b){$a/$b}else{0} }
function L($cell,$k,$lbl){ $a=$acc2["$cell|$k"]; $b=$acc2["$cell|base"]; if(-not $a -or $a.n -lt 150){ return }
  $roi=P $a.fuk $a.inv; $t3=P $a.t3 $a.n; $bt3=P $b.t3 $b.n
  $pos=$true;$any=$false; foreach($y in 2022..2026){ $by=$acc2["$cell|$k|$y"]; if($by -and $by.n -ge 30){ $any=$true; if((P $by.fuk $by.inv) -le 1.0){$pos=$false} } }
  $flag= if($any -and $pos){'★複回収全年>100'}elseif($roi -gt 1.0){'△>100'}elseif(($t3-$bt3)*100 -ge 6){'▲複勝率+6pt'}elseif(($t3-$bt3)*100 -le -6){'▽複勝率-6pt'}else{''}
  Write-Host ("    {0,-14} n={1,5} 複勝{2,6:P1}(base{3,5:P1}) 複回収{4,6:P1} {5}" -f $lbl,$a.n,$t3,$bt3,$roi,$flag) }
Write-Host "`n===== コンピ不使用: 今走セル×前走フォーム(上り/脚質/遷移)傾向+複勝回収(全JRA2022-26) ====="
foreach($cell in 'ダ短','ダマ','ダ中','芝短','芝マ','芝中','芝長'){ $b=$acc2["$cell|base"]; if(-not $b){continue}
  Write-Host ("`n■ 今走[$cell] base複勝{0:P1} 複回収{1:P1} (n{2})" -f (P $b.t3 $b.n),(P $b.fuk $b.inv),$b.n)
  Write-Host "  -- 前走上り3F帯 --"; foreach($u in '速','中','遅'){ L $cell "上り$u" "上り$u" }
  Write-Host "  -- 前走脚質 --"; foreach($s in '逃','先','差','追'){ L $cell "脚$s" "脚$s" }
  Write-Host "  -- 前走セル遷移 --"; foreach($t in '同','延長','短縮','種替'){ L $cell "遷$t" "遷$t" }
  Write-Host "  -- 脚質×上り速(注目) --"; foreach($s in '逃','先','差','追'){ L $cell "脚$s×上り速" "脚$s×上速" } }
Write-Host "`n===== 全セル横断: 複勝回収>100の生存セル(n>=150) ====="
foreach($k in ($acc2.Keys | Where-Object { $_ -notlike '*|20*' -and $_ -notlike '*base*' } | Sort-Object)){ $a=$acc2[$k]; if($a.n -lt 150){continue}; $roi=P $a.fuk $a.inv; if($roi -le 1.0){continue}
  $pos=$true;$any=$false; foreach($y in 2022..2026){ $by=$acc2["$k|$y"]; if($by -and $by.n -ge 25){ $any=$true; if((P $by.fuk $by.inv) -le 1.0){$pos=$false} } }
  $rob= if($any -and $pos){'★全年>100'}else{'(非頑健)'}
  Write-Host ("  {0,-22} n={1,5} 複勝{2:P1} 複回収{3:P1} {4}" -f $k,$a.n,(P $a.t3 $a.n),$roi,$rob) }
Write-Host ("`n[{0:N0}s]" -f $sw.Elapsed.TotalSeconds)
