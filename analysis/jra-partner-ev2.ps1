<#
  固い軸(コンピ1位)×中穴相手(オッズ5-50倍)ゾーンに、未価格化の確度シグナル(単騎速/条件適性+)を重ねて+EV相手を探す(全JRA2022-26)。
  仮説: 中穴相手は組合せで過小評価(FLB組合せ)=損益分岐の際。そこへ「オッズより来る」シグナル(単騎速=展開優位/適性+=条件巧者)を持つ相手に絞れば回収が控除率を超えるか。
  相手を[オッズ帯×シグナル(単騎速/適性+/無)]で層別しワイド/馬連回収を年別頑健に。生存=全年>100 かつ n>=閾。leak無。
#>
[Console]::OutputEncoding=[Text.Encoding]::UTF8
$connStr=(Get-Content (Join-Path $PSScriptRoot '..\共通\appsettings.json') -Raw -Encoding UTF8 | ConvertFrom-Json).ConnectionStrings.DefaultConnection
$cn=New-Object System.Data.SqlClient.SqlConnection $connStr;$cn.Open();$c=$cn.CreateCommand();$c.CommandTimeout=600
function Q($sql){ $c.CommandText=$sql; $r=$c.ExecuteReader(); $t=New-Object System.Data.DataTable; $t.Load($r); ,$t }
$sw=[Diagnostics.Stopwatch]::StartNew()
function PairKey($a,$b){ if([int]$a -le [int]$b){"$([int]$a)-$([int]$b)"}else{"$([int]$b)-$([int]$a)"} }
function Band($d){ if($d -le 1400){'短'}elseif($d -le 1799){'マ'}elseif($d -le 2200){'中'}else{'長'} }

# 競走結果(着順/四コーナー/距離/種別) 全期間(履歴用)
$rows=Q "SELECT k.馬名 nm,k.開催場所 v,CONVERT(varchar(10),k.開催日,23) d,k.レース番号 r,k.馬番 no,TRY_CONVERT(int,k.着順) ch,TRY_CONVERT(int,k.四コーナー) c4,ri.コース種別 s,TRY_CAST(ri.距離 AS int) dist FROM dbo.競走結果 k JOIN dbo.レース情報 ri ON ri.開催場所=k.開催場所 AND ri.開催日=k.開催日 AND ri.レース番号=k.レース番号 AND ri.馬番=k.馬番 WHERE k.開催日>='2020-06-01' AND TRY_CONVERT(int,k.着順)>0"
$fld=@{}; foreach($x in $rows.Rows){ $k="$($x.v)|$($x.d)|$($x.r)"; if($fld.ContainsKey($k)){$fld[$k]++}else{$fld[$k]=1} }
$byHorse=@{}
foreach($x in $rows.Rows){ $nm=[string]$x.nm; if(-not $byHorse.ContainsKey($nm)){ $byHorse[$nm]=New-Object System.Collections.Generic.List[object] }
  $n=$fld["$($x.v)|$($x.d)|$($x.r)"]
  $sty= if($x.c4 -is [DBNull] -or $n -le 1){ '' } else { $c4=[int]$x.c4; $rat=$c4/[double]$n; if($c4 -le 1){'逃'}elseif($rat -le 0.34){'先'}elseif($rat -le 0.66){'差'}else{'追'} }
  $surf= if("$($x.s)" -match 'ダ'){'ダ'}else{'芝'}
  $byHorse[$nm].Add([pscustomobject]@{ d=[string]$x.d;r=[int]$x.r;sty=$sty;surf=$surf;band=(Band ([int]$x.dist));t3=([int]$x.ch -le 3) }) }
foreach($nm in @($byHorse.Keys)){ $byHorse[$nm]=@($byHorse[$nm]|Sort-Object d,r) }
function PrevStyle($nm,$d){ if(-not $byHorse.ContainsKey($nm)){return ''}; $h=$byHorse[$nm]; for($i=$h.Count-1;$i -ge 0;$i--){ if($h[$i].d -lt $d -and $h[$i].sty -ne ''){ return $h[$i].sty } }; return '' }
# 差分適性(種別 or 距離両極が+): 過去その条件複勝率-全体複勝率>=0.12
function AptPlus($nm,$d,$surf,$band){ if(-not $byHorse.ContainsKey($nm)){return $false}; $h=@($byHorse[$nm]|Where-Object{$_.d -lt $d}); if($h.Count -lt 5){return $false}
  $oT3=@($h|Where-Object{$_.t3}).Count; $ob=$oT3/$h.Count
  $sh=@($h|Where-Object{$_.surf -eq $surf}); if($sh.Count -ge 3){ if((@($sh|Where-Object{$_.t3}).Count/$sh.Count)-$ob -ge 0.12){return $true} }
  if($band -eq '短' -or $band -eq '長'){ $bh=@($h|Where-Object{$_.band -eq $band}); if($bh.Count -ge 3){ if((@($bh|Where-Object{$_.t3}).Count/$bh.Count)-$ob -ge 0.12){return $true} } }
  return $false }

$crk=@{}; foreach($x in (Q "SELECT 開催場所 v,CONVERT(varchar(10),開催日,23) d,レース番号 r,馬名 nm,指数順位 rk FROM (SELECT 開催場所,開催日,レース番号,馬名,指数順位,ROW_NUMBER() OVER(PARTITION BY 開催場所,開催日,レース番号,馬名 ORDER BY 取得日時 DESC) sn FROM dbo.コンピ指数 WHERE 開催日>='2022-01-01' AND 指数順位 IS NOT NULL) z WHERE sn=1").Rows){ $crk["$($x.v)|$($x.d)|$($x.r)|$($x.nm)"]=[int]$x.rk }
$od=@{}; foreach($x in (Q "SELECT 開催場所 v,CONVERT(varchar(10),開催日,23) d,レース番号 r,馬番 no,TRY_CAST(単勝オッズ AS float) o FROM (SELECT *,ROW_NUMBER() OVER(PARTITION BY 開催場所,開催日,レース番号,馬番 ORDER BY 日時 DESC) sn FROM dbo.リアルタイムオッズ WHERE 開催日>='2022-01-01') z WHERE sn=1").Rows){ if($x.o -isnot [DBNull]){ $od["$($x.v)|$($x.d)|$($x.r)|$($x.no)"]=[double]$x.o } }
$wide=@{}; $umaren=@{}
foreach($x in (Q "SELECT 開催場所 v,CONVERT(varchar(10),開催日,23) d,レース番号 r,馬券 bk,組番 kb,TRY_CAST(金額 AS int) kin FROM dbo.払戻金 WHERE 開催日>='2022-01-01' AND 馬券 IN (N'ワイド',N'馬連')").Rows){ $nums=[regex]::Matches("$($x.kb)","\d+"); if($nums.Count -lt 2){continue}; $key="$($x.v)|$($x.d)|$($x.r)|$(PairKey $nums[0].Value $nums[1].Value)"; if("$($x.bk)" -eq 'ワイド'){$wide[$key]=[int]$x.kin}else{$umaren[$key]=[int]$x.kin} }
Write-Host ("履歴馬{0} コンピ{1}  [{2:N0}s]" -f $byHorse.Count,$crk.Count,$sw.Elapsed.TotalSeconds)

# レース組立(相手の脚質/種別/距離も要る)
$races=@{}
foreach($x in $rows.Rows){ if($x.d -lt '2022-01-01'){continue}; $rk="$($x.v)|$($x.d)|$($x.r)"; $ck="$rk|$($x.nm)"; if(-not $crk.ContainsKey($ck)){continue}
  if(-not $races.ContainsKey($rk)){ $races[$rk]=New-Object System.Collections.Generic.List[object] }
  $surf= if("$($x.s)" -match 'ダ'){'ダ'}else{'芝'}
  $races[$rk].Add([pscustomobject]@{ nm=[string]$x.nm; no=[int]$x.no; ch=[int]$x.ch; crk=$crk[$ck]; od=$(if($od.ContainsKey("$rk|$($x.no)")){$od["$rk|$($x.no)"]}else{0}); pstyle=(PrevStyle ([string]$x.nm) ([string]$x.d)); surf=$surf; band=(Band ([int]$x.dist)); d=[string]$x.d }) }

$acc=@{}
function Add($k,$wh,$wr,$uh,$ur){ if(-not $acc.ContainsKey($k)){ $acc[$k]=@{n=0;wh=0;winv=0;wret=0;uh=0;uret=0} }; $a=$acc[$k]; $a.n++; $a.winv+=100; if($wh){$a.wh++;$a.wret+=$wr}; if($uh){$a.uh++;$a.uret+=$ur} }
function AddY($k,$yr,$wh,$wr,$uh,$ur){ Add $k $wh $wr $uh $ur; Add "$k|$yr" $wh $wr $uh $ur }
function OB($o){ if($o -le 0){'?'}elseif($o -lt 5){'o<5'}elseif($o -lt 10){'o5-10'}elseif($o -lt 20){'o10-20'}elseif($o -lt 50){'o20-50'}else{'o50+'} }

foreach($rk in $races.Keys){ $R=$races[$rk]; if($R.Count -lt 8){ continue }; $p=$rk -split '\|'; $yr=$p[1].Substring(0,4)
  $ax=$R|Where-Object{$_.crk -eq 1}|Select-Object -First 1; if(-not $ax){ continue }
  $axFirm=($ax.od -gt 0 -and $ax.od -lt 2.5); $axT3=($ax.ch -le 3)
  $speed=@($R|Where-Object{ $_.pstyle -eq '逃' -or $_.pstyle -eq '先' }); $lone= if($speed.Count -eq 1){$speed[0].nm}else{''}
  foreach($h in $R){ if($h.no -eq $ax.no -or $h.crk -le 1){continue}
    $ob=OB $h.od; if($ob -notin @('o5-10','o10-20','o20-50')){continue}   # 中穴ゾーンのみ
    $pk="$rk|$(PairKey $ax.no $h.no)"
    $wh=($axT3 -and $h.ch -le 3); $wr= if($wh -and $wide.ContainsKey($pk)){$wide[$pk]}else{0}
    $uh=(($ax.ch -le 2) -and ($h.ch -le 2) -and ($ax.ch+$h.ch -eq 3)); $ur= if($uh -and $umaren.ContainsKey($pk)){$umaren[$pk]}else{0}
    $isLone=($lone -eq $h.nm); $isApt=(AptPlus $h.nm $h.d $h.surf $h.band)
    $sig= if($isLone){'単騎速'}elseif($isApt){'適性+'}else{'無'}
    AddY "全_$ob" $yr $wh $wr $uh $ur
    AddY "${sig}_$ob" $yr $wh $wr $uh $ur
    if($isLone -or $isApt){ AddY "シグナル有_$ob" $yr $wh $wr $uh $ur }
    if($axFirm -and ($isLone -or $isApt)){ AddY "固軸×シグナル有_$ob" $yr $wh $wr $uh $ur }
  } }
$cn.Close()
function Pc($a,$b){ if($b){'{0,6:P1}' -f ($a/$b)}else{'  —  '} }
function Line($k,$lbl,$minN){ $a=$acc[$k]; if(-not $a -or $a.n -lt $minN){ return }
  $wroi=$a.wret/$a.winv; $uroi=$a.uret/$a.winv
  $wY='';$wPos=$true;$any=$false; foreach($y in 2022..2026){ $b=$acc["$k|$y"]; if($b -and $b.n -ge 20){ $any=$true; $rr=$b.wret/$b.winv; if($rr -le 1.0){$wPos=$false}; $wY+=(" {0}:{1:P0}" -f $y,$rr) } }
  $uY='';$uPos=$true; foreach($y in 2022..2026){ $b=$acc["$k|$y"]; if($b -and $b.n -ge 20){ $rr=$b.uret/$b.winv; if($rr -le 1.0){$uPos=$false}; $uY+=(" {0}:{1:P0}" -f $y,$rr) } }
  $flag= if($any -and $wPos){'★ワイド+EV'}elseif($any -and $uPos){'★馬連+EV'}elseif($wroi -gt 1 -or $uroi -gt 1){'△プール>100'}else{''}
  Write-Host ("  {0,-20} n={1,5} ワイド的中{2} 回収{3,7:P1} | 馬連回収{4,7:P1} {5}" -f $lbl,$a.n,(Pc $a.wh $a.n),$wroi,$uroi,$flag)
  if($wroi -gt 1 -or $uroi -gt 1){ Write-Host ("        ワイド年別{0} | 馬連年別{1}" -f $wY,$uY) } }
Write-Host "`n===== 固い軸×中穴相手にシグナルを重ねた+EV相手探し(全JRA2022-26) ====="
foreach($ob in 'o5-10','o10-20','o20-50'){ Write-Host "`n--- 相手$ob ---"
  Line "全_$ob" "全相手" 300; Line "単騎速_$ob" "└単騎速相手" 30; Line "適性+_$ob" "└適性+相手" 80; Line "無_$ob" "└シグナル無" 300; Line "シグナル有_$ob" "└シグナル有(単騎速or適性+)" 80; Line "固軸×シグナル有_$ob" "└固軸×シグナル有" 60 }
Write-Host ("`n[{0:N0}s]" -f $sw.Elapsed.TotalSeconds)
