<#
  展開的適性(h2h/コンピが測れない「レースの形」への適合)を検証(全JRA 2022-26)。
  各馬の脚質=直近走の四コーナー位置/頭数(逃:先頭 / 先:上位1/3 / 差:中 / 追:後)。速い馬=逃/先。
  フィールドの速い馬頭数から: 単騎速(=速い馬1頭のみ・そのマイペース馬) / 差し優位(速い馬多×自分は差し)。
  コンピ順位帯を統制し複勝率・単勝/複勝回収・年別頑健性。前残り場(小倉/福島/函館/中京)で層別。
#>
[Console]::OutputEncoding=[Text.Encoding]::UTF8
$cs='Server=192.168.168.81\SQLEXPRESS;Database=中央競馬;User Id=sa;Password=Hanasaki#2093;TrustServerCertificate=True;Connect Timeout=30'
$cn=New-Object System.Data.SqlClient.SqlConnection $cs;$cn.Open();$c=$cn.CreateCommand();$c.CommandTimeout=600
function Q($sql){ $c.CommandText=$sql; $r=$c.ExecuteReader(); $t=New-Object System.Data.DataTable; $t.Load($r); ,$t }
$sw=[Diagnostics.Stopwatch]::StartNew()
$zenzan=@{'小倉'=1;'福島'=1;'函館'=1;'中京'=1}

# 競走結果: 四コーナー+頭数で脚質。馬別に直近走の脚質を持つ。
$rows=Q "SELECT k.開催場所 v,CONVERT(varchar(10),k.開催日,23) d,k.レース番号 r,k.馬名 nm,k.馬番 no,TRY_CONVERT(int,k.着順) ch,TRY_CONVERT(int,k.四コーナー) c4 FROM dbo.競走結果 k WHERE k.開催日>='2021-06-01' AND TRY_CONVERT(int,k.着順)>0"
$fld=@{}; foreach($x in $rows.Rows){ $k="$($x.v)|$($x.d)|$($x.r)"; if($fld.ContainsKey($k)){$fld[$k]++}else{$fld[$k]=1} }
$byHorse=@{}
foreach($x in $rows.Rows){ $nm=[string]$x.nm; if(-not $byHorse.ContainsKey($nm)){ $byHorse[$nm]=New-Object System.Collections.Generic.List[object] }
  $k="$($x.v)|$($x.d)|$($x.r)"; $n=$fld[$k]
  $sty= if($x.c4 -is [DBNull] -or $n -le 1){ '' } else { $c4=[int]$x.c4; $rat=$c4/[double]$n; if($c4 -le 1){'逃'}elseif($rat -le 0.34){'先'}elseif($rat -le 0.66){'差'}else{'追'} }
  $byHorse[$nm].Add([pscustomobject]@{ d=[string]$x.d; r=[int]$x.r; sty=$sty }) }
foreach($nm in @($byHorse.Keys)){ $byHorse[$nm]=@($byHorse[$nm]|Sort-Object d,r) }
# 各馬の「直近走脚質」lookup: key v|d|r|nm(今走)-> 直近走の脚質
function PrevStyle($nm,$d){ if(-not $byHorse.ContainsKey($nm)){return ''}; $h=$byHorse[$nm]; for($i=$h.Count-1;$i -ge 0;$i--){ if($h[$i].d -lt $d -and $h[$i].sty -ne ''){ return $h[$i].sty } }; return '' }
$crk=@{}; foreach($x in (Q "SELECT 開催場所 v,CONVERT(varchar(10),開催日,23) d,レース番号 r,馬名 nm,指数順位 rk FROM (SELECT 開催場所,開催日,レース番号,馬名,指数順位,ROW_NUMBER() OVER(PARTITION BY 開催場所,開催日,レース番号,馬名 ORDER BY 取得日時 DESC) sn FROM dbo.コンピ指数 WHERE 開催日>='2022-01-01' AND 指数順位 IS NOT NULL) z WHERE sn=1").Rows){ $crk["$($x.v)|$($x.d)|$($x.r)|$($x.nm)"]=[int]$x.rk }
$tanPay=@{}; $fukuPay=@{}; foreach($x in (Q "SELECT 開催場所 v,CONVERT(varchar(10),開催日,23) d,レース番号 r,馬券 bk,組番 kb,TRY_CAST(金額 AS int) kin FROM dbo.払戻金 WHERE 開催日>='2022-01-01' AND 馬券 IN (N'単勝',N'複勝')").Rows){ $no=0; if([int]::TryParse(("$($x.kb)").Trim(),[ref]$no)){ $kk="$($x.v)|$($x.d)|$($x.r)|$no"; if("$($x.bk)" -eq '単勝'){$tanPay[$kk]=[int]$x.kin}else{$fukuPay[$kk]=[int]$x.kin} } }
Write-Host ("馬{0} コンピ{1}  [{2:N0}s]" -f $byHorse.Count,$crk.Count,$sw.Elapsed.TotalSeconds)

# 今走レースを組み立て: 出走馬(競走結果)ごとに 前走脚質・コンピ・着順・払戻
$races=@{}
foreach($x in $rows.Rows){ if($x.d -lt '2022-01-01'){continue}; $rk="$($x.v)|$($x.d)|$($x.r)"; $nm=[string]$x.nm; $ck="$rk|$nm"; if(-not $crk.ContainsKey($ck)){continue}
  if(-not $races.ContainsKey($rk)){ $races[$rk]=New-Object System.Collections.Generic.List[object] }
  $races[$rk].Add([pscustomobject]@{ nm=$nm; no=[int]$x.no; ch=[int]$x.ch; crk=$crk[$ck]; pstyle=(PrevStyle $nm $x.d) }) }
Write-Host ("対象レース{0}  [{1:N0}s]" -f $races.Count,$sw.Elapsed.TotalSeconds)

$acc=@{}; function Add($k,$won,$t3,$tp,$fp){ if(-not $acc.ContainsKey($k)){ $acc[$k]=@{n=0;win=0;t3=0;inv=0;tan=0;fuk=0} }; $a=$acc[$k]; $a.n++; if($won){$a.win++}; if($t3){$a.t3++}; $a.inv+=100; $a.tan+=$tp; $a.fuk+=$fp }
function CB($rk){ if($rk -eq 1){'コ1位'}elseif($rk -le 3){'コ2-3'}else{'コ4+'} }
foreach($rk in $races.Keys){ $parts=$rk -split '\|'; $v=$parts[0]; $yr=$parts[1].Substring(0,4)
  $field=$races[$rk]; if($field.Count -lt 6){ continue }
  $speed=@($field|Where-Object{ $_.pstyle -eq '逃' -or $_.pstyle -eq '先' })
  $nSpeed=$speed.Count
  $isZen= $zenzan.ContainsKey($v)
  foreach($h in $field){
    $cb=CB $h.crk; $won=($h.ch -eq 1); $t3=($h.ch -le 3); $kk="$rk|$($h.no)"
    $tp= if($won -and $tanPay.ContainsKey($kk)){$tanPay[$kk]}else{0}; $fp= if($t3 -and $fukuPay.ContainsKey($kk)){$fukuPay[$kk]}else{0}
    $isSpeed=($h.pstyle -eq '逃' -or $h.pstyle -eq '先'); $isSashi=($h.pstyle -eq '差' -or $h.pstyle -eq '追')
    Add "BASE_$cb" $won $t3 $tp $fp
    # 単騎速(フィールドの速い馬が1頭のみ)×自分がその速い馬
    if($nSpeed -eq 1 -and $isSpeed){ Add "単騎速×$cb" $won $t3 $tp $fp; Add "単騎速×$cb|$yr" $won $t3 $tp $fp; if($isZen){ Add "単騎速×前残り場×$cb" $won $t3 $tp $fp; Add "単騎速×前残り×$cb|$yr" $won $t3 $tp $fp } }
    # 速い馬2頭(競り合い薄)×自分が速い
    if($nSpeed -eq 2 -and $isSpeed){ Add "速2頭×自速×$cb" $won $t3 $tp $fp }
    # 差し優位(速い馬多≥4)×自分が差し
    if($nSpeed -ge 4 -and $isSashi){ Add "速4+×自差し×$cb" $won $t3 $tp $fp }
  } }
$cn.Close()
function Pc($a,$b){ if($b){'{0,6:P1}' -f ($a/$b)}else{'  — '} }
function L($k,$lbl){ if(-not $acc.ContainsKey($k)){ Write-Host ("  {0,-22} n=0" -f $lbl); return }; $a=$acc[$k]; Write-Host ("  {0,-22} n={1,5} 勝率{2} 複勝{3} 単回収{4} 複回収{5}" -f $lbl,$a.n,(Pc $a.win $a.n),(Pc $a.t3 $a.n),(Pc $a.tan $a.inv),(Pc $a.fuk $a.inv)) }
Write-Host "`n===== 展開的適性(脚質×フィールド構成) コンピ帯別 ====="
foreach($cb in 'コ1位','コ2-3','コ4+'){ $b=$acc["BASE_$cb"]; Write-Host ("[{0}] base 勝率{1} 複勝{2} 単回収{3}" -f $cb,(Pc $b.win $b.n),(Pc $b.t3 $b.n),(Pc $b.tan $b.inv))
  L "単騎速×$cb" '単騎速'; L "単騎速×前残り場×$cb" '単騎速×前残り場'; L "速2頭×自速×$cb" '速2頭×自速'; L "速4+×自差し×$cb" '速4+×自差し' }
Write-Host "`n===== 年別頑健性(単騎速×コンピ帯・全場) ====="
foreach($cb in 'コ1位','コ2-3'){ $line="  $cb :"; foreach($y in 2022..2026){ $a=$acc["単騎速×$cb|$y"]; if($a){ $line+=(" {0}複{1}単{2}(n{3})" -f $y,(Pc $a.t3 $a.n),(Pc $a.tan $a.inv),$a.n) } }; Write-Host $line }
Write-Host "--- 単騎速×前残り場 年別 ---"
foreach($cb in 'コ1位','コ2-3'){ $line="  $cb :"; foreach($y in 2022..2026){ $a=$acc["単騎速×前残り×$cb|$y"]; if($a){ $line+=(" {0}複{1}単{2}(n{3})" -f $y,(Pc $a.t3 $a.n),(Pc $a.tan $a.inv),$a.n) } }; Write-Host $line }
Write-Host ("`n[{0:N0}s]" -f $sw.Elapsed.TotalSeconds)
