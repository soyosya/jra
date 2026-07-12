<#
  各馬の今走条件への「差分適性」(全JRA2022-26)。前スクリプトで残差×条件替わりはフラット(価格化)、種別の素の実績は有効と判明。
  差分適性=(過去その条件での複勝率)-(過去全体の複勝率)。"自分の平均より、この条件で上げてくる/下げる馬か"=個体固有の条件適性(全体能力の交絡を除去)。
  条件=種別(芝/ダ)・距離帯(短/マ/中/長)・場・回り(右/左)。コンピ帯統制で適性+/0/-の複勝率を比較・年別頑健性。
  leak無: 適性は過去走のみ・コンピ/条件は事前。
#>
[Console]::OutputEncoding=[Text.Encoding]::UTF8
$connStr=(Get-Content (Join-Path $PSScriptRoot '..\共通\appsettings.json') -Raw -Encoding UTF8 | ConvertFrom-Json).ConnectionStrings.DefaultConnection
$cn=New-Object System.Data.SqlClient.SqlConnection $connStr;$cn.Open();$c=$cn.CreateCommand();$c.CommandTimeout=600
function Q($sql){ $c.CommandText=$sql; $r=$c.ExecuteReader(); $t=New-Object System.Data.DataTable; $t.Load($r); ,$t }
$sw=[Diagnostics.Stopwatch]::StartNew()
function Band($d){ if($d -le 1400){'短'}elseif($d -le 1799){'マ'}elseif($d -le 2200){'中'}else{'長'} }

$rows=Q "SELECT k.馬名 nm,k.開催場所 v,CONVERT(varchar(10),k.開催日,23) d,k.レース番号 r,k.馬番 no,TRY_CONVERT(int,k.着順) ch,ri.コース種別 s,TRY_CAST(ri.距離 AS int) dist,ri.周回方向 turn FROM dbo.競走結果 k JOIN dbo.レース情報 ri ON ri.開催場所=k.開催場所 AND ri.開催日=k.開催日 AND ri.レース番号=k.レース番号 AND ri.馬番=k.馬番 WHERE k.開催日>='2019-06-01' AND TRY_CONVERT(int,k.着順)>0"
$crk=@{}; foreach($x in (Q "SELECT 開催場所 v,CONVERT(varchar(10),開催日,23) d,レース番号 r,馬名 nm,指数順位 rk FROM (SELECT 開催場所,開催日,レース番号,馬名,指数順位,ROW_NUMBER() OVER(PARTITION BY 開催場所,開催日,レース番号,馬名 ORDER BY 取得日時 DESC) sn FROM dbo.コンピ指数 WHERE 開催日>='2022-01-01' AND 指数順位 IS NOT NULL) z WHERE sn=1").Rows){ $crk["$($x.v)|$($x.d)|$($x.r)|$($x.nm)"]=[int]$x.rk }
$fukuPay=@{}; foreach($x in (Q "SELECT 開催場所 v,CONVERT(varchar(10),開催日,23) d,レース番号 r,組番 kb,TRY_CAST(金額 AS int) kin FROM dbo.払戻金 WHERE 開催日>='2022-01-01' AND 馬券=N'複勝'").Rows){ $no=0; if([int]::TryParse(("$($x.kb)").Trim(),[ref]$no)){ $fukuPay["$($x.v)|$($x.d)|$($x.r)|$no"]=[int]$x.kin } }

$byHorse=@{}
foreach($x in $rows.Rows){ $nm=[string]$x.nm; if(-not $byHorse.ContainsKey($nm)){ $byHorse[$nm]=New-Object System.Collections.Generic.List[object] }
  $surf= if("$($x.s)" -match 'ダ'){'ダ'}else{'芝'}
  $byHorse[$nm].Add([pscustomobject]@{ v=[string]$x.v; d=[string]$x.d; r=[int]$x.r; no=[int]$x.no; ch=[int]$x.ch; surf=$surf; band=(Band ([int]$x.dist)); turn=[string]$x.turn; t3=([int]$x.ch -le 3) }) }
foreach($nm in @($byHorse.Keys)){ $byHorse[$nm]=@($byHorse[$nm]|Sort-Object d,r) }
Write-Host ("馬{0} コンピ{1}  [{2:N0}s]" -f $byHorse.Count,$crk.Count,$sw.Elapsed.TotalSeconds)

$acc=@{}
function Add($k,$t3,$fp){ if(-not $acc.ContainsKey($k)){ $acc[$k]=@{n=0;t3=0;inv=0;fuk=0} }; $a=$acc[$k]; $a.n++; if($t3){$a.t3++}; $a.inv+=100; $a.fuk+=$fp }
function AddY($k,$yr,$t3,$fp){ Add $k $t3 $fp; Add "$k|$yr" $t3 $fp }
function CBand($rk){ if($rk -eq 1){'C1'}elseif($rk -le 3){'C2-3'}elseif($rk -le 6){'C4-6'}else{'C7+'} }
# 差分適性符号: (条件複勝率-全体複勝率)。条件n>=3 & 全体n>=5 が要件。しきい±0.12
function DiffSign($cT3,$cN,$oT3,$oN){ if($cN -lt 3 -or $oN -lt 5){return '?'}; $diff=($cT3/$cN)-($oT3/$oN); if($diff -ge 0.12){'+'}elseif($diff -le -0.12){'-'}else{'0'} }

foreach($nm in $byHorse.Keys){ $h=$byHorse[$nm]
  for($i=0;$i -lt $h.Count;$i++){ $cur=$h[$i]; if($cur.d -lt '2022-01-01'){continue}
    $ck="$($cur.v)|$($cur.d)|$($cur.r)|$nm"; if(-not $crk.ContainsKey($ck)){continue}
    $yr=$cur.d.Substring(0,4); $cb=CBand $crk[$ck]; $t3=$cur.t3; $kk="$($cur.v)|$($cur.d)|$($cur.r)|$($cur.no)"; $fp= if($t3 -and $fukuPay.ContainsKey($kk)){$fukuPay[$kk]}else{0}
    # 過去走(0..i-1)から全体+条件別の複勝実績
    $oN=0;$oT3=0; $sN=0;$sT3=0; $bN=0;$bT3=0; $vN=0;$vT3=0; $tN=0;$tT3=0
    for($j=0;$j -lt $i;$j++){ $pj=$h[$j]; $oN++; if($pj.t3){$oT3++}
      if($pj.surf -eq $cur.surf){ $sN++; if($pj.t3){$sT3++} }
      if($pj.band -eq $cur.band){ $bN++; if($pj.t3){$bT3++} }
      if($pj.v -eq $cur.v){ $vN++; if($pj.t3){$vT3++} }
      if($pj.turn -eq $cur.turn -and $cur.turn -ne ''){ $tN++; if($pj.t3){$tT3++} } }
    AddY "種別_$($cur.surf)_${cb}_$(DiffSign $sT3 $sN $oT3 $oN)" $yr $t3 $fp
    AddY "距離_$($cur.band)_${cb}_$(DiffSign $bT3 $bN $oT3 $oN)" $yr $t3 $fp
    AddY "場_${cb}_$(DiffSign $vT3 $vN $oT3 $oN)" $yr $t3 $fp
    AddY "回り_${cb}_$(DiffSign $tT3 $tN $oT3 $oN)" $yr $t3 $fp
  } }
$cn.Close()
function Pc($a,$b){ if($b){'{0,6:P1}' -f ($a/$b)}else{'  —  '} }
function Show($key,$lbl){ $a=$acc[$key]; if(-not $a -or $a.n -lt 40){ Write-Host ("    {0,-6} n={1,5} (少)" -f $lbl,($(if($a){$a.n}else{0}))); return }
  $ys=''; foreach($y in 2022..2026){ $b=$acc["$key|$y"]; if($b -and $b.n -ge 15){ $ys+=(" {0}:{1:P0}" -f $y,($b.t3/$b.n)) } }
  Write-Host ("    {0,-6} n={1,5} 複勝{2} 複回収{3}  年別{4}" -f $lbl,$a.n,(Pc $a.t3 $a.n),(Pc $a.fuk $a.inv),$ys) }
function Block($title,$keyfmt,$cats,$cbs){ Write-Host "`n===== $title (差分適性+ = 自分の平均よりこの条件で上げる馬) ====="
  foreach($cat in $cats){ foreach($cb in $cbs){ Write-Host "  [$cat × $cb]"
    Show ($keyfmt -f $cat,$cb,'+') '適性+'; Show ($keyfmt -f $cat,$cb,'0') '適性0'; Show ($keyfmt -f $cat,$cb,'-') '適性-' } } }
Block '種別適性' '種別_{0}_{1}_{2}' @('芝','ダ') @('C1','C2-3','C4-6','C7+')
Block '距離帯適性' '距離_{0}_{1}_{2}' @('短','マ','中','長') @('C1','C2-3','C4-6')
Write-Host "`n===== 場適性 / 回り適性 ====="
foreach($cb in 'C1','C2-3','C4-6'){ Write-Host "  [場 × $cb]"; Show "場_${cb}_+" '適性+'; Show "場_${cb}_0" '適性0'; Show "場_${cb}_-" '適性-' }
foreach($cb in 'C1','C2-3','C4-6'){ Write-Host "  [回り × $cb]"; Show "回り_${cb}_+" '適性+'; Show "回り_${cb}_0" '適性0'; Show "回り_${cb}_-" '適性-' }
Write-Host ("`n[{0:N0}s]" -f $sw.Elapsed.TotalSeconds)
