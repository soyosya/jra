<#
  昨年同開催(2025-06-28/29 小倉・福島・函館)の買目反省ログ。hansei-2025\*.txt(HORSE/EXPORT)を結果・払戻と突合。
  買目=三連複 軸1頭流し(相手5=10点/R)。反省=三連複回収+軸単複+軸確度別+消し精度(消しラベル別3着内率)+シグナル軸成否。
#>
[Console]::OutputEncoding=[Text.Encoding]::UTF8
$connStr=(Get-Content 'C:\jra\共通\appsettings.json' -Raw -Encoding UTF8 | ConvertFrom-Json).ConnectionStrings.DefaultConnection
$cn=New-Object System.Data.SqlClient.SqlConnection $connStr;$cn.Open();$c=$cn.CreateCommand()
function Q($sql,$p){ $c.CommandText=$sql; $c.Parameters.Clear(); foreach($k in $p.Keys){[void]$c.Parameters.AddWithValue($k,$p[$k])}; $r=$c.ExecuteReader();$t=New-Object System.Data.DataTable;$t.Load($r);,$t }
$dir='C:\jra\analysis\hansei-2025'
$cards=@(); foreach($d in '2025-06-28','2025-06-29'){ foreach($v in '小倉','福島','函館'){ $cards+=@{v=$v;d=$d;f=(Join-Path $dir ("{0}_{1}.txt" -f $v,($d -replace '-','')))} } }

# 集計器
$races=@()      # per-race records
$negLbl=@{}     # label -> @{n;t3}  消し精度
$negBase=@{n=0;t3=0}  # 全馬ベース(3着内率)
$axBuckets=@{} # 軸確度別
$sigAx=@{}     # シグナル軸(⚡単/適)
$keshiFail=@() # 消した馬が1着
function AddNeg($lbl,$t3){ if(-not $negLbl.ContainsKey($lbl)){$negLbl[$lbl]=@{n=0;t3=0}}; $negLbl[$lbl].n++; if($t3){$negLbl[$lbl].t3++} }

foreach($cd in $cards){ if(-not (Test-Path $cd.f)){ Write-Host "欠: $($cd.f)"; continue }
  $lines=Get-Content $cd.f -Encoding UTF8
  # 結果: 馬番->着順、top3
  $res=Q "SELECT 馬番 no,TRY_CONVERT(int,着順) ch,レース番号 r FROM dbo.競走結果 WHERE 開催場所=@v AND 開催日=@d AND TRY_CONVERT(int,着順)>0" @{'@v'=$cd.v;'@d'=$cd.d}
  $chOf=@{}; foreach($x in $res.Rows){ $chOf["$($x.r)|$($x.no)"]=[int]$x.ch }
  # 払戻
  $tan=@{};$fuku=@{};$trio=@{}
  foreach($x in (Q "SELECT レース番号 r,馬券 bk,組番 kb,TRY_CAST(金額 AS int) kin FROM dbo.払戻金 WHERE 開催場所=@v AND 開催日=@d AND 馬券 IN (N'単勝',N'複勝',N'三連複')" @{'@v'=$cd.v;'@d'=$cd.d}).Rows){
    $r=[int]$x.r; $bk="$($x.bk)"; $kin=[int]$x.kin
    if($bk -eq '三連複'){ $nums=@([regex]::Matches("$($x.kb)","\d+")|ForEach-Object{[int]$_.Value}); $trio["$r"]=@{set=($nums|Sort-Object);kin=$kin} }
    else{ $no=0; if([int]::TryParse(("$($x.kb)").Trim(),[ref]$no)){ if($bk -eq '単勝'){$tan["$r|$no"]=$kin}else{$fuku["$r|$no"]=$kin} } }
  }
  # HORSE 反省(消し精度)
  foreach($ln in ($lines|Where-Object{$_ -like 'HORSE|*'})){ $f=$ln -split '\|'; $rno=[int]$f[1]; $no=[int]$f[2]; $ev="$($f[3])"
    $ch=$chOf["$rno|$no"]; if($null -eq $ch){continue}; $t3=($ch -le 3)
    $negBase.n++; if($t3){$negBase.t3++}
    if($ev -like '◎*' -or $ev -like '○*' -or $ev -like '注*'){ continue }  # 買目(軸◎/注・相手○)は消された馬でないので消し精度から除外
    $anyNeg=$false
    foreach($tag in '前敗','長休','種替','不調','相悪','不適'){ if($ev -like "*$tag*"){ AddNeg $tag $t3; $anyNeg=$true } }
    if($ev -match '危'){ AddNeg '危' $t3; $anyNeg=$true }
    if($ev -eq '消'){ AddNeg '消' $t3; $anyNeg=$true }
    if($anyNeg -and $ch -eq 1){ $keshiFail+=("  {0} {1} {2,2}R 馬番{3}({4}) が1着" -f $cd.d.Substring(5),$cd.v,$rno,$no,$ev) }
  }
  # EXPORT 買目スコア
  foreach($ln in ($lines|Where-Object{$_ -like 'EXPORT|*'})){ $f=$ln -split '\|'; $rno=[int]$f[1]; $axno=[int]$f[3]; $axev="$($f[4])"; $ptn=@(($f[5] -split ',')|Where-Object{$_ -ne ''}|ForEach-Object{[int]$_})
    $t=$trio["$rno"]; $top3=@($res.Rows|Where-Object{[int]$_.r -eq $rno -and [int]$_.ch -le 3}|ForEach-Object{[int]$_.no})
    if($top3.Count -lt 3){ continue }
    $axCh=$chOf["$rno|$axno"]; $axT3=($null -ne $axCh -and $axCh -le 3); $axWin=($axCh -eq 1)
    # 三連複 軸1頭流し: 軸∈top3 & 他2頭のtop3が相手に含まれる
    $others=@($top3|Where-Object{$_ -ne $axno}); $hit=$false
    if($axT3 -and $others.Count -eq 2){ $hit=($ptn -contains $others[0]) -and ($ptn -contains $others[1]) }
    $pts=[math]::Max(0,[math]::Min($ptn.Count,5)); $cost=($pts*($pts-1)/2)*100  # C(相手,2)
    $ret= if($hit -and $t){ [int]$t.kin }else{ 0 }
    $tanRet= if($axWin){ [int]$tan["$rno|$axno"] }else{0}
    $fukRet= if($axT3){ [int]$fuku["$rno|$axno"] }else{0}
    $races+=[pscustomobject]@{ v=$cd.v;d=$cd.d;r=$rno;ax=$axno;axev=$axev;ptn=($ptn -join ',');top3=($top3 -join '-');axT3=$axT3;axWin=$axWin;hit=$hit;cost=$cost;ret=$ret;tanRet=$tanRet;fukRet=$fukRet }
    # 軸確度バケット
    $bk= if($axev -like '*堅軸*'){'堅軸'}elseif($axev -like '*軸★*'){'軸★'}elseif($axev -like '*軸弱*'){'軸弱'}elseif($axev -like '*注*'){'注危'}elseif($axev -like '*◎軸*'){'◎軸'}else{'他'}
    if(-not $axBuckets.ContainsKey($bk)){$axBuckets[$bk]=@{n=0;t3=0;hit=0;cost=0;ret=0}}; $b=$axBuckets[$bk]; $b.n++; if($axT3){$b.t3++}; if($hit){$b.hit++}; $b.cost+=$cost; $b.ret+=$ret
    foreach($sg in '⚡単','適'){ if($axev -like "*$sg*"){ if(-not $sigAx.ContainsKey($sg)){$sigAx[$sg]=@{n=0;t3=0}}; $sigAx[$sg].n++; if($axT3){$sigAx[$sg].t3++} } }
  }
}
$cn.Close()
function Pc($a,$b){ if($b){'{0:P1}' -f ($a/$b)}else{'—'} }

Write-Host "`n================= 昨年同開催(2025-06-28/29 小倉・福島・函館) 買目反省ログ ================="
Write-Host "買目=三連複 軸1頭流し(相手5=10点/R)`n"
# 全体
$n=$races.Count; $hit=@($races|Where-Object{$_.hit}).Count; $cost=($races|Measure-Object cost -Sum).Sum; $ret=($races|Measure-Object ret -Sum).Sum
$axT3=@($races|Where-Object{$_.axT3}).Count; $axWin=@($races|Where-Object{$_.axWin}).Count
$tanInv=$n*100; $tanRet=($races|Measure-Object tanRet -Sum).Sum; $fukRet=($races|Measure-Object fukRet -Sum).Sum
Write-Host "■ 全体(${n}レース)"
Write-Host ("  三連複軸流し: 的中{0}/{1}({2})  投資¥{3:N0} 回収¥{4:N0} 回収率{5:P1} 収支¥{6:N0}" -f $hit,$n,(Pc $hit $n),$cost,$ret,($ret/$cost),($ret-$cost))
Write-Host ("  軸: 複勝率{0} 勝率{1}  軸単勝回収{2} 軸複勝回収{3}" -f (Pc $axT3 $n),(Pc $axWin $n),(Pc $tanRet $tanInv),(Pc $fukRet $tanInv))
# 場別
Write-Host "`n■ 場別 三連複軸流し"
foreach($v in '小倉','福島','函館'){ $g=@($races|Where-Object{$_.v -eq $v}); if(-not $g.Count){continue}; $h=@($g|Where-Object{$_.hit}).Count; $co=($g|Measure-Object cost -Sum).Sum; $re=($g|Measure-Object ret -Sum).Sum
  Write-Host ("  {0}: 的中{1,2}/{2} 回収率{3,7:P1} 収支¥{4,8:N0} 軸複勝{5}" -f $v,$h,$g.Count,($re/$co),($re-$co),(Pc (@($g|Where-Object{$_.axT3}).Count) $g.Count)) }
# 軸確度別
Write-Host "`n■ 軸確度別(EXPORT軸評価)"
foreach($bk in '堅軸','軸★','◎軸','軸弱','注危','他'){ $b=$axBuckets[$bk]; if(-not $b -or $b.n -eq 0){continue}
  Write-Host ("  {0,-4} {1,2}R 三連複的中{2}({3}) 軸複勝{4} 回収率{5:P1}" -f $bk,$b.n,$b.hit,(Pc $b.hit $b.n),(Pc $b.t3 $b.n),($b.ret/[math]::Max(1,$b.cost))) }
# 消し精度
Write-Host "`n■ 消し精度(消しラベル別の3着内率=低いほど良い消し)  ベース全馬3着内率 $(Pc $negBase.t3 $negBase.n) (n$($negBase.n))"
foreach($tag in '前敗','長休','種替','危','不調','相悪','不適','消'){ $x=$negLbl[$tag]; if(-not $x -or $x.n -eq 0){continue}
  Write-Host ("  {0,-4} n={1,3} 3着内率{2,6} {3}" -f $tag,$x.n,(Pc $x.t3 $x.n),$(if(($x.t3/$x.n) -lt ($negBase.t3/$negBase.n)){'✓消し有効'}else{'✗消し逆効果'})) }
# シグナル軸
Write-Host "`n■ 正シグナル軸の成否(軸複勝率)"
foreach($sg in '⚡単','適'){ $x=$sigAx[$sg]; if($x){ Write-Host ("  {0} 軸{1}R 複勝率{2}" -f $sg,$x.n,(Pc $x.t3 $x.n)) } }
# 消し失敗(消した馬が1着)
Write-Host "`n■ 消し失敗チェック(消しラベルの馬が1着になったレース)"
if($keshiFail.Count){ $keshiFail | ForEach-Object { Write-Host $_ } }else{ Write-Host "  なし(消した馬から勝ち馬は出ず=消し良好)" }
# per-race table
Write-Host "`n■ レース別明細"
Write-Host "  日   場  R  軸(評価) / 相手 / 決着 / 三連複 / 軸着"
foreach($x in ($races|Sort-Object v,d,r)){ $mk= if($x.hit){'的中¥'+$x.ret}else{'—'}; $am= if($x.axT3){'複'}else{' '}; if($x.axWin){$am='勝'}
  Write-Host ("  {0} {1} {2,2} {3,-3}({4,-6}) 相手{5,-11} {6,-8} {7,-8} {8}" -f ($x.d.Substring(5)),$x.v,$x.r,$x.ax,$x.axev,$x.ptn,$x.top3,$mk,$am) }
