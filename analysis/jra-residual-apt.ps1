<#
  コンピと直交する軸=「コンピ順位に対する着順の超過/不足(残差)」で好不調/適性を測る(全JRA 2022-26)。
  aptRes=同セル(コース種別×距離帯)の過去(コンピ順位-着順)平均[+=格付け以上に走る=適性] / formRes=直近3走の同残差。
  能力(コンピ)を差し引くので、コンピ織込を超える条件依存の癖を抽出。今日のコンピ順位帯を統制し複勝率・複回収・年別頑健性。
  ※着順・コンピは過去走のみ(leak無)。距離帯: 短≤1400/マ1401-1799/中1800-2200/長2201+。
#>
[Console]::OutputEncoding=[Text.Encoding]::UTF8
$cs='Server=192.168.168.81\SQLEXPRESS;Database=中央競馬;User Id=sa;Password=Hanasaki#2093;TrustServerCertificate=True;Connect Timeout=30'
$cn=New-Object System.Data.SqlClient.SqlConnection $cs;$cn.Open();$c=$cn.CreateCommand();$c.CommandTimeout=600
function Q($sql){ $c.CommandText=$sql; $r=$c.ExecuteReader(); $t=New-Object System.Data.DataTable; $t.Load($r); ,$t }
$sw=[Diagnostics.Stopwatch]::StartNew()
function Band($d){ if($d -le 1400){'短'}elseif($d -le 1799){'マ'}elseif($d -le 2200){'中'}else{'長'} }
function Med($a){ $s=@($a|Sort-Object); $n=$s.Count; if(-not $n){return $null}; if($n%2){return [double]$s[[int](($n-1)/2)]}; return ([double]$s[$n/2-1]+[double]$s[$n/2])/2 }

# 競走結果(着順)+レース情報(種別/距離) 馬別
$rows=Q "SELECT k.馬名 nm,k.開催場所 v,CONVERT(varchar(10),k.開催日,23) d,k.レース番号 r,k.馬番 no,TRY_CONVERT(int,k.着順) ch,ri.コース種別 s,TRY_CAST(ri.距離 AS int) dist FROM dbo.競走結果 k JOIN dbo.レース情報 ri ON ri.開催場所=k.開催場所 AND ri.開催日=k.開催日 AND ri.レース番号=k.レース番号 AND ri.馬番=k.馬番 WHERE k.開催日>='2021-06-01' AND TRY_CONVERT(int,k.着順)>0"
# コンピ順位 v|d|r|nm
$crk=@{}; foreach($x in (Q "SELECT 開催場所 v,CONVERT(varchar(10),開催日,23) d,レース番号 r,馬名 nm,指数順位 rk FROM (SELECT 開催場所,開催日,レース番号,馬名,指数順位,ROW_NUMBER() OVER(PARTITION BY 開催場所,開催日,レース番号,馬名 ORDER BY 取得日時 DESC) sn FROM dbo.コンピ指数 WHERE 開催日>='2021-06-01' AND 指数順位 IS NOT NULL) z WHERE sn=1").Rows){ $crk["$($x.v)|$($x.d)|$($x.r)|$($x.nm)"]=[int]$x.rk }
# 馬別履歴(コンピ順位あり・残差計算可能な走のみ)
$byHorse=@{}
foreach($x in $rows.Rows){ $nm=[string]$x.nm; $k="$($x.v)|$($x.d)|$($x.r)|$nm"; if(-not $crk.ContainsKey($k)){ continue }
  if(-not $byHorse.ContainsKey($nm)){ $byHorse[$nm]=New-Object System.Collections.Generic.List[object] }
  $byHorse[$nm].Add([pscustomobject]@{ d=[string]$x.d; r=[int]$x.r; s=[string]$x.s; dist=[int]$x.dist; ch=[int]$x.ch; crk=$crk[$k]; cell="$($x.s)$(Band $x.dist)"; res=($crk[$k]-[int]$x.ch); no=[int]$x.no }) }
foreach($nm in @($byHorse.Keys)){ $byHorse[$nm]=@($byHorse[$nm]|Sort-Object d,r) }
$fukuPay=@{}; foreach($x in (Q "SELECT 開催場所 v,CONVERT(varchar(10),開催日,23) d,レース番号 r,組番 kb,TRY_CAST(金額 AS int) kin FROM dbo.払戻金 WHERE 開催日>='2022-01-01' AND 馬券=N'複勝'").Rows){ $no=0; if([int]::TryParse(("$($x.kb)").Trim(),[ref]$no)){ $fukuPay["$($x.v)|$($x.d)|$($x.r)|$no"]=[int]$x.kin } }
Write-Host ("馬{0} コンピ{1} 複勝払{2}  [{3:N0}s]" -f $byHorse.Count,$crk.Count,$fukuPay.Count,$sw.Elapsed.TotalSeconds)

$acc=@{}; function Add($k,$t3,$fp){ if(-not $acc.ContainsKey($k)){ $acc[$k]=@{n=0;t3=0;inv=0;fuk=0} }; $a=$acc[$k]; $a.n++; if($t3){$a.t3++}; $a.inv+=100; $a.fuk+=$fp }
function BandC($rk){ if($rk -eq 1){'コ1位'}elseif($rk -le 3){'コ2-3'}elseif($rk -le 6){'コ4-6'}else{'コ7+'} }
foreach($nm in $byHorse.Keys){ $h=$byHorse[$nm]
  for($i=0;$i -lt $h.Count;$i++){ $cur=$h[$i]; if($cur.d -lt '2022-01-01'){ continue }
    $cb=BandC $cur.crk; $t3=($cur.ch -le 3); $fp= if($t3){ $kk="$($cur.v)|$($cur.d)|$($cur.r)|$($cur.no)"; if($fukuPay.ContainsKey($kk)){$fukuPay[$kk]}else{0} }else{0}
    # 適性残差(同セル過去)
    $cellRes=@(); for($j=0;$j -lt $i;$j++){ if($h[$j].cell -eq $cur.cell){ $cellRes+=$h[$j].res } }
    # 好不調残差(直近3走・セル不問)
    $recRes=@(); for($j=[math]::Max(0,$i-3);$j -lt $i;$j++){ $recRes+=$h[$j].res }
    Add "BASE_$cb" $t3 $fp
    if($cellRes.Count -ge 3){ $ar=Med $cellRes
      $bk= if($ar -ge 1.5){'適+(格上走)'}elseif($ar -le -1.5){'適-(格下走)'}else{'適0'}
      Add "$cb|$bk" $t3 $fp; Add "$cb|$bk|$($cur.d.Substring(0,4))" $t3 $fp }
    if($recRes.Count -ge 3){ $fr=Med $recRes
      $bk= if($fr -ge 1.5){'好調+'}elseif($fr -le -1.5){'不調-'}else{'普0'}
      Add "$cb|F_$bk" $t3 $fp }
  } }
$cn.Close()
function Pc($a,$b){ if($b){'{0,6:P1}' -f ($a/$b)}else{'  — '} }
function L($k,$lbl){ if(-not $acc.ContainsKey($k)){ return }; $a=$acc[$k]; Write-Host ("  {0,-16} n={1,5} 複勝{2} 複回収{3}" -f $lbl,$a.n,(Pc $a.t3 $a.n),(Pc $a.fuk $a.inv)) }
Write-Host "`n===== 適性残差(同セル コンピ順位-着順) コンピ帯別 ====="
foreach($cb in 'コ1位','コ2-3','コ4-6','コ7+'){ $b=$acc["BASE_$cb"]; if($b){ Write-Host ("[{0}] base複勝{1}(n{2})" -f $cb,(Pc $b.t3 $b.n),$b.n) }
  L "$cb|適+(格上走)" '適性+(≥+1.5)'; L "$cb|適0" '適性中'; L "$cb|適-(格下走)" '適性-(≤-1.5)' }
Write-Host "`n===== 好不調残差(直近3走 コンピ順位-着順) コンピ帯別 ====="
foreach($cb in 'コ1位','コ2-3','コ4-6','コ7+'){ $b=$acc["BASE_$cb"]; if($b){ Write-Host ("[{0}]" -f $cb) }
  L "$cb|F_好調+" '好調+(≥+1.5)'; L "$cb|F_普0" '普通'; L "$cb|F_不調-" '不調-(≤-1.5)' }
Write-Host "`n===== 年別頑健性(コ1位 適性+/-) ====="
foreach($bk in '適+(格上走)','適-(格下走)'){ $line="  $bk :"; foreach($y in 2022..2026){ $a=$acc["コ1位|$bk|$y"]; if($a){ $line+=(" {0}複{1}(n{2})" -f $y,(Pc $a.t3 $a.n),$a.n) } }; Write-Host $line }
Write-Host ("`n[{0:N0}s]" -f $sw.Elapsed.TotalSeconds)
