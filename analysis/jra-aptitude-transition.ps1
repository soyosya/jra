<#
  各馬の「今走条件への適性」を個体の過去反応から測る(全JRA2022-26)。
  適性=残差(コンピ順位-着順=格付けより上に走ったか)を"条件替わりの種類別"に過去集計。
  今走の条件替わり(延長/短縮/同距離・同条件/替わり・種別)に対し、その馬の過去同種局面での平均残差=適性符号(+/0/-)。
  検定: コンピ帯を統制し、適性+の馬は同じコンピ順位でも複勝率が高いか(=コンピ未織込の個体適性か)。年別頑健性込み。
  leak無: コンピ/条件=事前、適性は過去走のみ、残差の着順も過去走のみ。
#>
[Console]::OutputEncoding=[Text.Encoding]::UTF8
$connStr=(Get-Content (Join-Path $PSScriptRoot '..\共通\appsettings.json') -Raw -Encoding UTF8 | ConvertFrom-Json).ConnectionStrings.DefaultConnection
$cn=New-Object System.Data.SqlClient.SqlConnection $connStr;$cn.Open();$c=$cn.CreateCommand();$c.CommandTimeout=600
function Q($sql){ $c.CommandText=$sql; $r=$c.ExecuteReader(); $t=New-Object System.Data.DataTable; $t.Load($r); ,$t }
$sw=[Diagnostics.Stopwatch]::StartNew()

# 競走結果(着順)+レース情報(距離/種別/回り) 馬別履歴
$rows=Q "SELECT k.馬名 nm,k.開催場所 v,CONVERT(varchar(10),k.開催日,23) d,k.レース番号 r,k.馬番 no,TRY_CONVERT(int,k.着順) ch,ri.コース種別 s,TRY_CAST(ri.距離 AS int) dist,ri.周回方向 turn FROM dbo.競走結果 k JOIN dbo.レース情報 ri ON ri.開催場所=k.開催場所 AND ri.開催日=k.開催日 AND ri.レース番号=k.レース番号 AND ri.馬番=k.馬番 WHERE k.開催日>='2020-06-01' AND TRY_CONVERT(int,k.着順)>0"
$crk=@{}; foreach($x in (Q "SELECT 開催場所 v,CONVERT(varchar(10),開催日,23) d,レース番号 r,馬名 nm,指数順位 rk FROM (SELECT 開催場所,開催日,レース番号,馬名,指数順位,ROW_NUMBER() OVER(PARTITION BY 開催場所,開催日,レース番号,馬名 ORDER BY 取得日時 DESC) sn FROM dbo.コンピ指数 WHERE 開催日>='2020-06-01' AND 指数順位 IS NOT NULL) z WHERE sn=1").Rows){ $crk["$($x.v)|$($x.d)|$($x.r)|$($x.nm)"]=[int]$x.rk }
$fukuPay=@{}; foreach($x in (Q "SELECT 開催場所 v,CONVERT(varchar(10),開催日,23) d,レース番号 r,組番 kb,TRY_CAST(金額 AS int) kin FROM dbo.払戻金 WHERE 開催日>='2022-01-01' AND 馬券=N'複勝'").Rows){ $no=0; if([int]::TryParse(("$($x.kb)").Trim(),[ref]$no)){ $fukuPay["$($x.v)|$($x.d)|$($x.r)|$no"]=[int]$x.kin } }

# 馬別履歴(日付順)。各走にコンピ順位/残差を付与
$byHorse=@{}
foreach($x in $rows.Rows){ $nm=[string]$x.nm; if(-not $byHorse.ContainsKey($nm)){ $byHorse[$nm]=New-Object System.Collections.Generic.List[object] }
  $ck="$($x.v)|$($x.d)|$($x.r)|$nm"; $rk= if($crk.ContainsKey($ck)){$crk[$ck]}else{$null}
  $byHorse[$nm].Add([pscustomobject]@{ v=[string]$x.v; d=[string]$x.d; r=[int]$x.r; no=[int]$x.no; ch=[int]$x.ch; s=[string]$x.s; dist=[int]$x.dist; turn=[string]$x.turn; crk=$rk }) }
foreach($nm in @($byHorse.Keys)){ $byHorse[$nm]=@($byHorse[$nm]|Sort-Object d,r) }
Write-Host ("馬{0} コンピ{1}  [{2:N0}s]" -f $byHorse.Count,$crk.Count,$sw.Elapsed.TotalSeconds)

function DistTrans($cur,$prev){ $dd=$cur-$prev; if($dd -ge 200){'延長'}elseif($dd -le -200){'短縮'}else{'同'} }

$acc=@{}
function Add($k,$t3,$fp){ if(-not $acc.ContainsKey($k)){ $acc[$k]=@{n=0;t3=0;inv=0;fuk=0} }; $a=$acc[$k]; $a.n++; if($t3){$a.t3++}; $a.inv+=100; $a.fuk+=$fp }
function AddY($k,$yr,$t3,$fp){ Add $k $t3 $fp; Add "$k|$yr" $t3 $fp }
function CBand($rk){ if($rk -eq 1){'C1'}elseif($rk -le 3){'C2-3'}elseif($rk -le 6){'C4-6'}else{'C7+'} }
function AptSign($vals){ if($vals.Count -lt 2){return '0'}; $m=($vals|Measure-Object -Average).Average; if($m -ge 1.0){'+'}elseif($m -le -1.0){'-'}else{'0'} }

foreach($nm in $byHorse.Keys){ $h=$byHorse[$nm]
  for($i=1;$i -lt $h.Count;$i++){ $cur=$h[$i]; if($cur.d -lt '2022-01-01'){continue}; if($null -eq $cur.crk){continue}
    $yr=$cur.d.Substring(0,4); $prev=$h[$i-1]
    $t3=($cur.ch -le 3); $kk="$($cur.v)|$($cur.d)|$($cur.r)|$($cur.no)"; $fp= if($t3 -and $fukuPay.ContainsKey($kk)){$fukuPay[$kk]}else{0}
    $cb=CBand $cur.crk
    # 今走の条件替わり
    $td=DistTrans $cur.dist $prev.dist
    $surfCh=($cur.s -ne $prev.s)
    $venCh=($cur.v -ne $prev.v)
    $situ= if($surfCh -or $td -ne '同' -or $venCh){'替わり'}else{'同条件'}
    # 過去走の残差を局面別に収集(j<i, 各jにも前走が要る=j>=1, かつコンピ&着順あり)
    $vDist=@(); $vSitu=@(); $vSurf=@{}
    for($j=1;$j -lt $i;$j++){ $pj=$h[$j]; if($null -eq $pj.crk){continue}; $res=$pj.crk-$pj.ch
      $pp=$h[$j-1]; $jtd=DistTrans $pj.dist $pp.dist; $jsurfCh=($pj.s -ne $pp.s); $jvenCh=($pj.v -ne $pp.v)
      $jsitu= if($jsurfCh -or $jtd -ne '同' -or $jvenCh){'替わり'}else{'同条件'}
      if($jtd -eq $td){ $vDist+=$res }
      if($jsitu -eq $situ){ $vSitu+=$res }
    }
    # 今走種別への適性=過去その種別での複勝率(残差でなく素の複勝率・コンピ統制で見る)
    $surfPast=@($h[0..($i-1)]|Where-Object{ $_.s -eq $cur.s -and $null -ne $_.crk })
    $surfT3= @($surfPast|Where-Object{ $_.ch -le 3 }).Count
    $surfApt= if($surfPast.Count -ge 3){ if($surfT3/$surfPast.Count -ge 0.5){'+'}elseif($surfT3/$surfPast.Count -le 0.2){'-'}else{'0'} }else{'0'}
    # 集計: 距離替わり適性
    $sd=AptSign $vDist
    AddY "距離_${td}_${cb}_apt$sd" $yr $t3 $fp
    # 同条件/替わり適性
    $ss=AptSign $vSitu
    AddY "局面_${situ}_${cb}_apt$ss" $yr $t3 $fp
    # 種別適性
    AddY "種別_$($cur.s)_${cb}_apt$surfApt" $yr $t3 $fp
  } }
$cn.Close()
function Pc($a,$b){ if($b){'{0,6:P1}' -f ($a/$b)}else{'  —  '} }
function Show($key,$lbl){ $a=$acc[$key]; if(-not $a -or $a.n -lt 30){ Write-Host ("    {0,-8} n={1,5} (少)" -f $lbl,($(if($a){$a.n}else{0}))); return }
  $ys=''; foreach($y in 2022..2026){ $b=$acc["$key|$y"]; if($b -and $b.n -ge 10){ $ys+=(" {0}:{1:P0}" -f $y,($b.t3/$b.n)) } }
  Write-Host ("    {0,-8} n={1,5} 複勝{2} 複回収{3}  年別{4}" -f $lbl,$a.n,(Pc $a.t3 $a.n),(Pc $a.fuk $a.inv),$ys) }
function Block($title,$prefix,$cats,$cbs){ Write-Host "`n===== $title ====="
  foreach($cat in $cats){ foreach($cb in $cbs){ Write-Host "  [$cat × $cb] 適性+ / 0 / - の複勝率(同コンピ帯での個体差)"
    Show "${prefix}_${cat}_${cb}_apt+" '適性+'; Show "${prefix}_${cat}_${cb}_apt0" '適性0'; Show "${prefix}_${cat}_${cb}_apt-" '適性-' } } }
Block '距離替わり適性(過去同種局面の残差)' '距離' @('延長','短縮','同') @('C1','C2-3','C4-6')
Block '同条件 vs 条件替わり適性' '局面' @('同条件','替わり') @('C1','C2-3','C4-6')
Block '種別適性(過去その種別の複勝率)' '種別' @('芝','ダート') @('C1','C2-3','C4-6')
Write-Host ("`n[{0:N0}s]" -f $sw.Elapsed.TotalSeconds)
