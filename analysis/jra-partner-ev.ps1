<#
  「固い軸(コンピ1位)を固定し、+EVになる相手の帯を探す」(全JRA2022-26)。
  軸は固く絡む前提→ワイド/馬連の当否≒相手が来るか。市場が過小評価する相手帯を選べば軸の固さが妙味に化けるか検定。
  仮説: FLB組合せ版=固い1位×中穴のワイドは一般客が買わず過小評価。相手を[コンピ帯×単勝オッズ帯]で層別しワイド/馬連回収を年別頑健に。
  生存(+EV相手帯)=全年ワイドor馬連回収>100 かつ n>=閾。leak無(コンピ/オッズ=事前)。
#>
[Console]::OutputEncoding=[Text.Encoding]::UTF8
$connStr=(Get-Content (Join-Path $PSScriptRoot '..\共通\appsettings.json') -Raw -Encoding UTF8 | ConvertFrom-Json).ConnectionStrings.DefaultConnection
$cn=New-Object System.Data.SqlClient.SqlConnection $connStr;$cn.Open();$c=$cn.CreateCommand();$c.CommandTimeout=600
function Q($sql){ $c.CommandText=$sql; $r=$c.ExecuteReader(); $t=New-Object System.Data.DataTable; $t.Load($r); ,$t }
$sw=[Diagnostics.Stopwatch]::StartNew()
function PairKey($a,$b){ if([int]$a -le [int]$b){"$([int]$a)-$([int]$b)"}else{"$([int]$b)-$([int]$a)"} }

# 結果(着順)・コンピ・オッズ・払戻(ワイド/馬連)
$rows=Q "SELECT k.開催場所 v,CONVERT(varchar(10),k.開催日,23) d,k.レース番号 r,k.馬番 no,k.馬名 nm,TRY_CONVERT(int,k.着順) ch FROM dbo.競走結果 k WHERE k.開催日>='2022-01-01' AND TRY_CONVERT(int,k.着順)>0"
$crk=@{}; foreach($x in (Q "SELECT 開催場所 v,CONVERT(varchar(10),開催日,23) d,レース番号 r,馬名 nm,指数順位 rk FROM (SELECT 開催場所,開催日,レース番号,馬名,指数順位,ROW_NUMBER() OVER(PARTITION BY 開催場所,開催日,レース番号,馬名 ORDER BY 取得日時 DESC) sn FROM dbo.コンピ指数 WHERE 開催日>='2022-01-01' AND 指数順位 IS NOT NULL) z WHERE sn=1").Rows){ $crk["$($x.v)|$($x.d)|$($x.r)|$($x.nm)"]=[int]$x.rk }
$od=@{}; foreach($x in (Q "SELECT 開催場所 v,CONVERT(varchar(10),開催日,23) d,レース番号 r,馬番 no,TRY_CAST(単勝オッズ AS float) o FROM (SELECT *,ROW_NUMBER() OVER(PARTITION BY 開催場所,開催日,レース番号,馬番 ORDER BY 日時 DESC) sn FROM dbo.リアルタイムオッズ WHERE 開催日>='2022-01-01') z WHERE sn=1").Rows){ if($x.o -isnot [DBNull]){ $od["$($x.v)|$($x.d)|$($x.r)|$($x.no)"]=[double]$x.o } }
$wide=@{}; $umaren=@{}
foreach($x in (Q "SELECT 開催場所 v,CONVERT(varchar(10),開催日,23) d,レース番号 r,馬券 bk,組番 kb,TRY_CAST(金額 AS int) kin FROM dbo.払戻金 WHERE 開催日>='2022-01-01' AND 馬券 IN (N'ワイド',N'馬連')").Rows){ $nums=[regex]::Matches("$($x.kb)","\d+"); if($nums.Count -lt 2){continue}; $key="$($x.v)|$($x.d)|$($x.r)|$(PairKey $nums[0].Value $nums[1].Value)"; if("$($x.bk)" -eq 'ワイド'){$wide[$key]=[int]$x.kin}else{$umaren[$key]=[int]$x.kin} }
Write-Host ("結果{0} コンピ{1} オッズ{2} ワイド{3} 馬連{4}  [{5:N0}s]" -f $rows.Rows.Count,$crk.Count,$od.Count,$wide.Count,$umaren.Count,$sw.Elapsed.TotalSeconds)

# レース組立
$races=@{}
foreach($x in $rows.Rows){ $rk="$($x.v)|$($x.d)|$($x.r)"; $ck="$rk|$($x.nm)"; if(-not $crk.ContainsKey($ck)){continue}
  if(-not $races.ContainsKey($rk)){ $races[$rk]=New-Object System.Collections.Generic.List[object] }
  $races[$rk].Add([pscustomobject]@{ no=[int]$x.no; ch=[int]$x.ch; crk=$crk[$ck]; od=$(if($od.ContainsKey("$rk|$($x.no)")){$od["$rk|$($x.no)"]}else{0}) }) }

$acc=@{}
function Add($k,$wh,$wr,$uh,$ur){ if(-not $acc.ContainsKey($k)){ $acc[$k]=@{n=0;wh=0;winv=0;wret=0;uh=0;uret=0} }; $a=$acc[$k]; $a.n++; $a.winv+=100; if($wh){$a.wh++;$a.wret+=$wr}; if($uh){$a.uh++;$a.uret+=$ur} }
function AddY($k,$yr,$wh,$wr,$uh,$ur){ Add $k $wh $wr $uh $ur; Add "$k|$yr" $wh $wr $uh $ur }
function OB($o){ if($o -le 0){'?'}elseif($o -lt 5){'o<5'}elseif($o -lt 10){'o5-10'}elseif($o -lt 20){'o10-20'}elseif($o -lt 50){'o20-50'}else{'o50+'} }
function CB($rk){ if($rk -le 3){'コ2-3'}elseif($rk -le 6){'コ4-6'}elseif($rk -le 9){'コ7-9'}else{'コ10+'} }

foreach($rk in $races.Keys){ $R=$races[$rk]; if($R.Count -lt 8){ continue }; $p=$rk -split '\|'; $yr=$p[1].Substring(0,4)
  $ax=$R|Where-Object{$_.crk -eq 1}|Select-Object -First 1; if(-not $ax){ continue }
  $axFirm= ($ax.od -gt 0 -and $ax.od -lt 2.5)   # 固い軸=1位かつ単勝<2.5
  $axT3=($ax.ch -le 3)
  foreach($h in $R){ if($h.no -eq $ax.no){continue}; if($h.crk -le 1){continue}
    $pk="$rk|$(PairKey $ax.no $h.no)"
    $wh=($axT3 -and $h.ch -le 3); $wr= if($wh -and $wide.ContainsKey($pk)){$wide[$pk]}else{0}
    $uh=(($ax.ch -le 2) -and ($h.ch -le 2) -and ($ax.ch+$h.ch -eq 3)); $ur= if($uh -and $umaren.ContainsKey($pk)){$umaren[$pk]}else{0}   # 馬連=1-2着
    $cb=CB $h.crk; $ob=OB $h.od; if($ob -eq '?'){continue}
    AddY "相手$cb" $yr $wh $wr $uh $ur
    AddY "相手$ob" $yr $wh $wr $uh $ur
    AddY "相手$cb×$ob" $yr $wh $wr $uh $ur
    if($axFirm){ AddY "固軸×相手$ob" $yr $wh $wr $uh $ur; AddY "固軸×相手$cb×$ob" $yr $wh $wr $uh $ur }
  } }
$cn.Close()
function Pc($a,$b){ if($b){'{0,6:P1}' -f ($a/$b)}else{'  —  '} }
function Line($k,$lbl,$minN){ $a=$acc[$k]; if(-not $a -or $a.n -lt $minN){ return }
  $wroi=$a.wret/$a.winv; $uroi=$a.uret/$a.winv
  $wY='';$wPos=$true;$anyY=$false; foreach($y in 2022..2026){ $b=$acc["$k|$y"]; if($b -and $b.n -ge 30){ $anyY=$true; $rr=$b.wret/$b.winv; if($rr -le 1.0){$wPos=$false}; $wY+=(" {0}:{1:P0}" -f $y,$rr) } }
  $uY='';$uPos=$true; foreach($y in 2022..2026){ $b=$acc["$k|$y"]; if($b -and $b.n -ge 30){ $rr=$b.uret/$b.winv; if($rr -le 1.0){$uPos=$false}; $uY+=(" {0}:{1:P0}" -f $y,$rr) } }
  $flag= if($anyY -and $wPos){'★ワイド+EV'}elseif($anyY -and $uPos){'★馬連+EV'}elseif($wroi -gt 1 -or $uroi -gt 1){'△プール>100'}else{''}
  Write-Host ("  {0,-18} n={1,6} ワイド的中{2} 回収{3,7:P1} | 馬連回収{4,7:P1} {5}" -f $lbl,$a.n,(Pc $a.wh $a.n),$wroi,$uroi,$flag)
  if($wroi -gt 1 -or $uroi -gt 1){ Write-Host ("        ワイド年別{0}  馬連年別{1}" -f $wY,$uY) } }
Write-Host "`n===== 固い軸(コンピ1位)の+EV相手探し: ワイド/馬連 軸-相手(全JRA2022-26) ====="
Write-Host "--- 相手コンピ帯別 ---"; foreach($cb in 'コ2-3','コ4-6','コ7-9','コ10+'){ Line "相手$cb" "相手$cb" 500 }
Write-Host "--- 相手単勝オッズ帯別 ---"; foreach($ob in 'o<5','o5-10','o10-20','o20-50','o50+'){ Line "相手$ob" "相手$ob" 500 }
Write-Host "--- 相手コンピ×オッズ ---"; foreach($cb in 'コ2-3','コ4-6','コ7-9','コ10+'){ foreach($ob in 'o<5','o5-10','o10-20','o20-50','o50+'){ Line "相手$cb×$ob" "$cb×$ob" 200 } }
Write-Host "`n--- 固い軸(1位×単<2.5)×相手オッズ帯 ---"; foreach($ob in 'o<5','o5-10','o10-20','o20-50','o50+'){ Line "固軸×相手$ob" "固軸×相手$ob" 300 }
Write-Host "--- 固い軸×相手コンピ×オッズ(妙味候補) ---"; foreach($cb in 'コ4-6','コ7-9','コ10+'){ foreach($ob in 'o10-20','o20-50','o50+'){ Line "固軸×相手$cb×$ob" "固軸×$cb×$ob" 150 } }
Write-Host ("`n[{0:N0}s]" -f $sw.Elapsed.TotalSeconds)
