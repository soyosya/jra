<#
  固い軸(コンピ1位)×中穴相手ゾーンで「相手からネガティブ要素馬を除外すると組合せ回収が上がるか」検証(全JRA2022-26)。
  相手のネガ=前敗(前走頭数下位30%)/不調(前3走3着内0)/長休(120日+)/種替(前走種別替)/相悪(同条件過去複勝率<34%)/不適(差分適性-)のいずれか。
  相手を[オッズ帯×ネガ有/無]で層別しワイド/馬連回収を年別頑健に。ネガ無が回収↑なら「相手にもネガ除外を効かせるべき」。leak無(全て過去走/事前)。
#>
[Console]::OutputEncoding=[Text.Encoding]::UTF8
$connStr=(Get-Content (Join-Path $PSScriptRoot '..\共通\appsettings.json') -Raw -Encoding UTF8 | ConvertFrom-Json).ConnectionStrings.DefaultConnection
$cn=New-Object System.Data.SqlClient.SqlConnection $connStr;$cn.Open();$c=$cn.CreateCommand();$c.CommandTimeout=600
function Q($sql){ $c.CommandText=$sql; $r=$c.ExecuteReader(); $t=New-Object System.Data.DataTable; $t.Load($r); ,$t }
$sw=[Diagnostics.Stopwatch]::StartNew()
function PairKey($a,$b){ if([int]$a -le [int]$b){"$([int]$a)-$([int]$b)"}else{"$([int]$b)-$([int]$a)"} }
function Band($d){ if($d -le 1400){'短'}elseif($d -le 1799){'マ'}elseif($d -le 2200){'中'}else{'長'} }

$rows=Q "SELECT k.馬名 nm,k.開催場所 v,CONVERT(varchar(10),k.開催日,23) d,k.レース番号 r,k.馬番 no,TRY_CONVERT(int,k.着順) ch,ri.コース種別 s,TRY_CAST(ri.距離 AS int) dist FROM dbo.競走結果 k JOIN dbo.レース情報 ri ON ri.開催場所=k.開催場所 AND ri.開催日=k.開催日 AND ri.レース番号=k.レース番号 AND ri.馬番=k.馬番 WHERE k.開催日>='2020-06-01' AND TRY_CONVERT(int,k.着順)>0"
$fld=@{}; foreach($x in $rows.Rows){ $k="$($x.v)|$($x.d)|$($x.r)"; if($fld.ContainsKey($k)){$fld[$k]++}else{$fld[$k]=1} }
$byHorse=@{}
foreach($x in $rows.Rows){ $nm=[string]$x.nm; if(-not $byHorse.ContainsKey($nm)){ $byHorse[$nm]=New-Object System.Collections.Generic.List[object] }
  $surf= if("$($x.s)" -match 'ダ'){'ダ'}else{'芝'}
  $byHorse[$nm].Add([pscustomobject]@{ d=[string]$x.d;r=[int]$x.r;ch=[int]$x.ch;field=$fld["$($x.v)|$($x.d)|$($x.r)"];surf=$surf;band=(Band ([int]$x.dist));t3=([int]$x.ch -le 3) }) }
foreach($nm in @($byHorse.Keys)){ $byHorse[$nm]=@($byHorse[$nm]|Sort-Object d,r) }
# 相手のネガ判定(今走d/種別surf/距離band)
function HasNeg($nm,$d,$surf,$band){ if(-not $byHorse.ContainsKey($nm)){return $false}
  $h=@($byHorse[$nm]|Where-Object{$_.d -lt $d}); if($h.Count -lt 1){return $false}
  $prev=$h[-1]
  if($prev.field -ge 6 -and ($prev.ch/[double]$prev.field) -ge 0.7){return $true}          # 前敗
  try{ if(([datetime]$d-[datetime]$prev.d).Days -ge 120 -and $surf -eq 'ダ'){return $true} }catch{}  # 長休(ダート)
  if($prev.surf -ne $surf){return $true}                                                   # 種別替
  $last3=@($h | Select-Object -Last 3); if($last3.Count -ge 3 -and (@($last3|Where-Object{$_.t3}).Count -eq 0)){return $true}  # 不調
  $cell=@($h|Where-Object{$_.surf -eq $surf -and $_.band -eq $band}); if($cell.Count -ge 3 -and (@($cell|Where-Object{$_.t3}).Count/$cell.Count) -lt 0.34){return $true}  # 相悪
  if($h.Count -ge 5){ $ob=(@($h|Where-Object{$_.t3}).Count)/$h.Count
    $sh=@($h|Where-Object{$_.surf -eq $surf}); if($sh.Count -ge 3 -and ((@($sh|Where-Object{$_.t3}).Count/$sh.Count)-$ob) -le -0.12){return $true}   # 不適(種別)
    if($band -eq '短' -or $band -eq '長'){ $bh=@($h|Where-Object{$_.band -eq $band}); if($bh.Count -ge 3 -and ((@($bh|Where-Object{$_.t3}).Count/$bh.Count)-$ob) -le -0.12){return $true} } }
  return $false }

$crk=@{}; foreach($x in (Q "SELECT 開催場所 v,CONVERT(varchar(10),開催日,23) d,レース番号 r,馬名 nm,指数順位 rk FROM (SELECT 開催場所,開催日,レース番号,馬名,指数順位,ROW_NUMBER() OVER(PARTITION BY 開催場所,開催日,レース番号,馬名 ORDER BY 取得日時 DESC) sn FROM dbo.コンピ指数 WHERE 開催日>='2022-01-01' AND 指数順位 IS NOT NULL) z WHERE sn=1").Rows){ $crk["$($x.v)|$($x.d)|$($x.r)|$($x.nm)"]=[int]$x.rk }
$od=@{}; foreach($x in (Q "SELECT 開催場所 v,CONVERT(varchar(10),開催日,23) d,レース番号 r,馬番 no,TRY_CAST(単勝オッズ AS float) o FROM (SELECT *,ROW_NUMBER() OVER(PARTITION BY 開催場所,開催日,レース番号,馬番 ORDER BY 日時 DESC) sn FROM dbo.リアルタイムオッズ WHERE 開催日>='2022-01-01') z WHERE sn=1").Rows){ if($x.o -isnot [DBNull]){ $od["$($x.v)|$($x.d)|$($x.r)|$($x.no)"]=[double]$x.o } }
$wide=@{}; $umaren=@{}
foreach($x in (Q "SELECT 開催場所 v,CONVERT(varchar(10),開催日,23) d,レース番号 r,馬券 bk,組番 kb,TRY_CAST(金額 AS int) kin FROM dbo.払戻金 WHERE 開催日>='2022-01-01' AND 馬券 IN (N'ワイド',N'馬連')").Rows){ $nums=[regex]::Matches("$($x.kb)","\d+"); if($nums.Count -lt 2){continue}; $key="$($x.v)|$($x.d)|$($x.r)|$(PairKey $nums[0].Value $nums[1].Value)"; if("$($x.bk)" -eq 'ワイド'){$wide[$key]=[int]$x.kin}else{$umaren[$key]=[int]$x.kin} }
Write-Host ("履歴{0} コンピ{1}  [{2:N0}s]" -f $byHorse.Count,$crk.Count,$sw.Elapsed.TotalSeconds)

$races=@{}
foreach($x in $rows.Rows){ if($x.d -lt '2022-01-01'){continue}; $rk="$($x.v)|$($x.d)|$($x.r)"; $ck="$rk|$($x.nm)"; if(-not $crk.ContainsKey($ck)){continue}
  if(-not $races.ContainsKey($rk)){ $races[$rk]=New-Object System.Collections.Generic.List[object] }
  $surf= if("$($x.s)" -match 'ダ'){'ダ'}else{'芝'}
  $races[$rk].Add([pscustomobject]@{ nm=[string]$x.nm; no=[int]$x.no; ch=[int]$x.ch; crk=$crk[$ck]; od=$(if($od.ContainsKey("$rk|$($x.no)")){$od["$rk|$($x.no)"]}else{0}); surf=$surf; band=(Band ([int]$x.dist)); d=[string]$x.d }) }

$acc=@{}
function Add($k,$wh,$wr,$uh,$ur){ if(-not $acc.ContainsKey($k)){ $acc[$k]=@{n=0;wh=0;winv=0;wret=0;uh=0;uret=0} }; $a=$acc[$k]; $a.n++; $a.winv+=100; if($wh){$a.wh++;$a.wret+=$wr}; if($uh){$a.uh++;$a.uret+=$ur} }
function AddY($k,$yr,$wh,$wr,$uh,$ur){ Add $k $wh $wr $uh $ur; Add "$k|$yr" $wh $wr $uh $ur }
function OB($o){ if($o -le 0){'?'}elseif($o -lt 5){'o<5'}elseif($o -lt 10){'o5-10'}elseif($o -lt 20){'o10-20'}elseif($o -lt 50){'o20-50'}else{'o50+'} }
foreach($rk in $races.Keys){ $R=$races[$rk]; if($R.Count -lt 8){ continue }; $p=$rk -split '\|'; $yr=$p[1].Substring(0,4)
  $ax=$R|Where-Object{$_.crk -eq 1}|Select-Object -First 1; if(-not $ax){ continue }; $axT3=($ax.ch -le 3)
  foreach($h in $R){ if($h.no -eq $ax.no -or $h.crk -le 1){continue}
    $ob=OB $h.od; if($ob -notin @('o5-10','o10-20','o20-50')){continue}
    $pk="$rk|$(PairKey $ax.no $h.no)"
    $wh=($axT3 -and $h.ch -le 3); $wr= if($wh -and $wide.ContainsKey($pk)){$wide[$pk]}else{0}
    $uh=(($ax.ch -le 2) -and ($h.ch -le 2) -and ($ax.ch+$h.ch -eq 3)); $ur= if($uh -and $umaren.ContainsKey($pk)){$umaren[$pk]}else{0}
    $neg=(HasNeg $h.nm $h.d $h.surf $h.band); $tag= if($neg){'ネガ有'}else{'ネガ無'}
    AddY "全_$ob" $yr $wh $wr $uh $ur
    AddY "${tag}_$ob" $yr $wh $wr $uh $ur
  } }
$cn.Close()
function Pc($a,$b){ if($b){'{0,6:P1}' -f ($a/$b)}else{'  —  '} }
function Line($k,$lbl){ $a=$acc[$k]; if(-not $a -or $a.n -lt 100){ return }
  $wroi=$a.wret/$a.winv; $uroi=$a.uret/$a.winv
  $wY='';$wPos=$true;$any=$false; foreach($y in 2022..2026){ $b=$acc["$k|$y"]; if($b -and $b.n -ge 30){ $any=$true; $rr=$b.wret/$b.winv; if($rr -le 1.0){$wPos=$false}; $wY+=(" {0}:{1:P0}" -f $y,$rr) } }
  foreach($y in 2022..2026){ $b=$acc["$k|$y"]; if($b -and $b.n -ge 30){ if(($b.uret/$b.winv) -le 1.0){$uPos=$false} } }
  $flag= if($any -and $wPos){'★ワイド全年>100'}elseif($wroi -gt 1 -or $uroi -gt 1){'△プール>100'}else{''}
  Write-Host ("  {0,-14} n={1,6} ワイド的中{2} 回収{3,7:P1} | 馬連回収{4,7:P1} {5}" -f $lbl,$a.n,(Pc $a.wh $a.n),$wroi,$uroi,$flag) }
Write-Host "`n===== 相手のネガ除外は組合せ回収を上げるか(固い軸コンピ1位・中穴相手・全JRA2022-26) ====="
foreach($ob in 'o5-10','o10-20','o20-50'){ Write-Host "`n--- 相手$ob ---"
  Line "全_$ob" "全相手"; Line "ネガ無_$ob" "ネガ無相手"; Line "ネガ有_$ob" "ネガ有相手" }
Write-Host ("`n[{0:N0}s]" -f $sw.Elapsed.TotalSeconds)
