<#
  軸=コンピ1位固定・相手=コンピ指定順位3頭 での買い方成績(全JRA2022-26)。
  券種: ワイド軸流し3点 / 馬連軸流し3点 / 三連複軸1頭流し3点(C(3,2))。的中率(レース)/回収率/収支/年別。
  相手セット比較: コ2-4(上位) / コ4-6(指定) / コ5-7 / コ7-9(中穴)。realized払戻ベース。leak無(コンピ/オッズ=事前)。
#>
[Console]::OutputEncoding=[Text.Encoding]::UTF8
$connStr=(Get-Content (Join-Path $PSScriptRoot '..\共通\appsettings.json') -Raw -Encoding UTF8 | ConvertFrom-Json).ConnectionStrings.DefaultConnection
$cn=New-Object System.Data.SqlClient.SqlConnection $connStr;$cn.Open();$c=$cn.CreateCommand();$c.CommandTimeout=600
function Q($sql){ $c.CommandText=$sql; $r=$c.ExecuteReader(); $t=New-Object System.Data.DataTable; $t.Load($r); ,$t }
$sw=[Diagnostics.Stopwatch]::StartNew()
function PK($a,$b){ if([int]$a -le [int]$b){"$([int]$a)-$([int]$b)"}else{"$([int]$b)-$([int]$a)"} }
function TK($a,$b,$cc){ (@([int]$a,[int]$b,[int]$cc)|Sort-Object) -join '-' }

$rows=Q "SELECT k.開催場所 v,CONVERT(varchar(10),k.開催日,23) d,k.レース番号 r,k.馬番 no,k.馬名 nm,TRY_CONVERT(int,k.着順) ch FROM dbo.競走結果 k WHERE k.開催日>='2022-01-01' AND TRY_CONVERT(int,k.着順)>0"
$crk=@{}; foreach($x in (Q "SELECT 開催場所 v,CONVERT(varchar(10),開催日,23) d,レース番号 r,馬名 nm,指数順位 rk FROM (SELECT 開催場所,開催日,レース番号,馬名,指数順位,ROW_NUMBER() OVER(PARTITION BY 開催場所,開催日,レース番号,馬名 ORDER BY 取得日時 DESC) sn FROM dbo.コンピ指数 WHERE 開催日>='2022-01-01' AND 指数順位 IS NOT NULL) z WHERE sn=1").Rows){ $crk["$($x.v)|$($x.d)|$($x.r)|$($x.nm)"]=[int]$x.rk }
$wide=@{};$umaren=@{};$trio=@{}
foreach($x in (Q "SELECT 開催場所 v,CONVERT(varchar(10),開催日,23) d,レース番号 r,馬券 bk,組番 kb,TRY_CAST(金額 AS int) kin FROM dbo.払戻金 WHERE 開催日>='2022-01-01' AND 馬券 IN (N'ワイド',N'馬連',N'三連複')").Rows){ $nums=@([regex]::Matches("$($x.kb)","\d+")|ForEach-Object{[int]$_.Value}); $rk="$($x.v)|$($x.d)|$($x.r)"; $bk="$($x.bk)"
  if($bk -eq '三連複' -and $nums.Count -ge 3){ $trio["$rk|$(TK $nums[0] $nums[1] $nums[2])"]=[int]$x.kin }
  elseif($nums.Count -ge 2){ $key="$rk|$(PK $nums[0] $nums[1])"; if($bk -eq 'ワイド'){$wide[$key]=[int]$x.kin}else{$umaren[$key]=[int]$x.kin} } }
Write-Host ("結果{0} コンピ{1} ワイド{2} 馬連{3} 三連複{4}  [{5:N0}s]" -f $rows.Rows.Count,$crk.Count,$wide.Count,$umaren.Count,$trio.Count,$sw.Elapsed.TotalSeconds)

$races=@{}
foreach($x in $rows.Rows){ $rk="$($x.v)|$($x.d)|$($x.r)"; $ck="$rk|$($x.nm)"; if(-not $crk.ContainsKey($ck)){continue}
  if(-not $races.ContainsKey($rk)){ $races[$rk]=New-Object System.Collections.Generic.List[object] }
  $races[$rk].Add([pscustomobject]@{ no=[int]$x.no; ch=[int]$x.ch; crk=$crk[$ck] }) }

$acc=@{}
function Add($k,$hit,$inv,$ret){ if(-not $acc.ContainsKey($k)){ $acc[$k]=@{n=0;hit=0;inv=0;ret=0} }; $a=$acc[$k]; $a.n++; if($hit){$a.hit++}; $a.inv+=$inv; $a.ret+=$ret }
function AddY($k,$yr,$hit,$inv,$ret){ Add $k $hit $inv $ret; Add "$k|$yr" $hit $inv $ret }
$setDefs=@{ 'コ2-4'=@(2,3,4); 'コ4-6'=@(4,5,6); 'コ5-7'=@(5,6,7); 'コ7-9'=@(7,8,9) }
foreach($rk in $races.Keys){ $R=$races[$rk]; if($R.Count -lt 8){ continue }; $yr=($rk -split '\|')[1].Substring(0,4)
  $ax=$R|Where-Object{$_.crk -eq 1}|Select-Object -First 1; if(-not $ax){ continue }
  $top3=@($R|Where-Object{$_.ch -le 3}|ForEach-Object{$_.no}); if($top3.Count -lt 3){continue}
  $axT3=($ax.ch -le 3); $t1=($R|Where-Object{$_.ch -eq 1}|Select-Object -First 1); $t2=($R|Where-Object{$_.ch -eq 2}|Select-Object -First 1)
  foreach($sn in $setDefs.Keys){ $ranks=$setDefs[$sn]
    $ps=@(); foreach($rr in $ranks){ $h=$R|Where-Object{$_.crk -eq $rr}|Select-Object -First 1; if($h){$ps+=$h} }
    if($ps.Count -lt 3){ continue }   # 3頭揃うレースのみ
    # ワイド軸流し3点
    $wInv=300; $wRet=0; $wHit=$false
    foreach($p in $ps){ if($axT3 -and $p.ch -le 3){ $k="$rk|$(PK $ax.no $p.no)"; if($wide.ContainsKey($k)){ $wRet+=$wide[$k]; $wHit=$true } } }
    AddY "ワイド_$sn" $yr $wHit $wInv $wRet
    # 馬連軸流し3点
    $uInv=300; $uRet=0; $uHit=$false
    foreach($p in $ps){ if($t1 -and $t2 -and ((($ax.no -eq $t1.no) -and ($p.no -eq $t2.no)) -or (($ax.no -eq $t2.no) -and ($p.no -eq $t1.no)))){ $k="$rk|$(PK $ax.no $p.no)"; if($umaren.ContainsKey($k)){ $uRet+=$umaren[$k]; $uHit=$true } } }
    AddY "馬連_$sn" $yr $uHit $uInv $uRet
    # 三連複軸1頭流し3点(C(3,2)=3)
    $tInv=300; $tRet=0; $tHit=$false
    $others=@($top3|Where-Object{$_ -ne $ax.no})
    if($axT3 -and $others.Count -eq 2){ $pset=@($ps|ForEach-Object{$_.no}); if(($pset -contains $others[0]) -and ($pset -contains $others[1])){ $k="$rk|$(TK $ax.no $others[0] $others[1])"; if($trio.ContainsKey($k)){ $tRet=$trio[$k]; $tHit=$true } } }
    AddY "三連複_$sn" $yr $tHit $tInv $tRet
  }
}
$cn.Close()
function Pc($a,$b){ if($b){'{0,6:P1}' -f ($a/$b)}else{'  —  '} }
function Line($k,$lbl){ $a=$acc[$k]; if(-not $a){ return }
  $roi=$a.ret/$a.inv; $yY=''; $pos=$true;$any=$false
  foreach($y in 2022..2026){ $b=$acc["$k|$y"]; if($b){ $any=$true; $rr=$b.ret/$b.inv; if($rr -le 1.0){$pos=$false}; $yY+=(" {0}:{1:P0}" -f $y,$rr) } }
  $flag= if($any -and $pos){'★全年>100'}elseif($roi -gt 1){'△プール>100'}else{''}
  Write-Host ("  {0,-12} {1}R 的中{2} 回収{3,7:P1} 収支¥{4,9:N0}(/R{5,6:N1}) {6}" -f $lbl,$a.n,(Pc $a.hit $a.n),$roi,($a.ret-$a.inv),(($a.ret-$a.inv)/[math]::Max(1,$a.n)),$flag)
  if($roi -gt 1){ Write-Host ("       年別{0}" -f $yY) } }
Write-Host "`n===== 軸=コンピ1位 × 相手3頭(コンピ順位別) 買い方成績(全JRA2022-26) ====="
foreach($bt in 'ワイド','馬連','三連複'){ Write-Host "`n■ $bt 軸流し3点(投資300/R)"
  foreach($sn in 'コ2-4','コ4-6','コ5-7','コ7-9'){ Line "${bt}_$sn" "相手$sn" } }
Write-Host ("`n[{0:N0}s]" -f $sw.Elapsed.TotalSeconds)
