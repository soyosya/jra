<#
  自律+EV総当たり Phase2(組合せ馬券・全JRA2022-26)。未検証の低ボリューム馬券種=枠連/ワイド/馬連をコンピ上位組合せで。
  規律: 生存=全年ROI>100 かつ 各年n>=5 かつ 総n>=閾。プール>100は年別表示。
  組合せ払戻を組番pairで辞書化。当たり判定は着順(枠連=1-2着の枠 / 馬連=1-2着の馬番 / ワイド=3着内2頭)。leak無(コンピ順位=事前)。
#>
[Console]::OutputEncoding=[Text.Encoding]::UTF8
$connStr=(Get-Content (Join-Path $PSScriptRoot '..\共通\appsettings.json') -Raw -Encoding UTF8 | ConvertFrom-Json).ConnectionStrings.DefaultConnection
$cn=New-Object System.Data.SqlClient.SqlConnection $connStr;$cn.Open();$c=$cn.CreateCommand();$c.CommandTimeout=600
function Q($sql){ $c.CommandText=$sql; $r=$c.ExecuteReader(); $t=New-Object System.Data.DataTable; $t.Load($r); ,$t }
$sw=[Diagnostics.Stopwatch]::StartNew()
function Band($d){ if($d -le 1400){'短'}elseif($d -le 1799){'マ'}elseif($d -le 2200){'中'}else{'長'} }
function PairKey($a,$b){ if([int]$a -le [int]$b){"$([int]$a)-$([int]$b)"}else{"$([int]$b)-$([int]$a)"} }

# 着順+枠+馬番(結果) + コンピ順位 + レース種別/距離
$rows=Q "SELECT k.開催場所 v,CONVERT(varchar(10),k.開催日,23) d,k.レース番号 r,k.馬名 nm,k.馬番 no,TRY_CONVERT(int,k.着順) ch,TRY_CONVERT(int,ri.枠番) wk,ri.コース種別 s,TRY_CAST(ri.距離 AS int) dist FROM dbo.競走結果 k JOIN dbo.レース情報 ri ON ri.開催場所=k.開催場所 AND ri.開催日=k.開催日 AND ri.レース番号=k.レース番号 AND ri.馬番=k.馬番 WHERE k.開催日>='2022-01-01' AND TRY_CONVERT(int,k.着順)>0"
$crk=@{}; foreach($x in (Q "SELECT 開催場所 v,CONVERT(varchar(10),開催日,23) d,レース番号 r,馬名 nm,指数順位 rk FROM (SELECT 開催場所,開催日,レース番号,馬名,指数順位,ROW_NUMBER() OVER(PARTITION BY 開催場所,開催日,レース番号,馬名 ORDER BY 取得日時 DESC) sn FROM dbo.コンピ指数 WHERE 開催日>='2022-01-01' AND 指数順位 IS NOT NULL) z WHERE sn=1").Rows){ $crk["$($x.v)|$($x.d)|$($x.r)|$($x.nm)"]=[int]$x.rk }
# 組合せ払戻(馬連/ワイド/枠連) 組番pair->金額(100円あたり)
$umaren=@{}; $wide=@{}; $wakuren=@{}
foreach($x in (Q "SELECT 開催場所 v,CONVERT(varchar(10),開催日,23) d,レース番号 r,馬券 bk,組番 kb,TRY_CAST(金額 AS int) kin FROM dbo.払戻金 WHERE 開催日>='2022-01-01' AND 馬券 IN (N'馬連',N'ワイド',N'枠連')").Rows){
  $nums=[regex]::Matches("$($x.kb)","\d+"); if($nums.Count -lt 2){ continue }
  $pk=PairKey $nums[0].Value $nums[1].Value; $rk="$($x.v)|$($x.d)|$($x.r)"; $key="$rk|$pk"; $kin=[int]$x.kin
  switch("$($x.bk)"){ '馬連'{$umaren[$key]=$kin} 'ワイド'{$wide[$key]=$kin} '枠連'{$wakuren[$key]=$kin} } }
Write-Host ("結果{0} コンピ{1} 馬連{2} ワイド{3} 枠連{4}  [{5:N0}s]" -f $rows.Rows.Count,$crk.Count,$umaren.Count,$wide.Count,$wakuren.Count,$sw.Elapsed.TotalSeconds)

# レース組立
$races=@{}
foreach($x in $rows.Rows){ $rk="$($x.v)|$($x.d)|$($x.r)"; $nm=[string]$x.nm; $ck="$rk|$nm"; if(-not $crk.ContainsKey($ck)){continue}
  if(-not $races.ContainsKey($rk)){ $races[$rk]=@{ v=[string]$x.v; d=[string]$x.d; s=[string]$x.s; dist=[int]$x.dist; hs=(New-Object System.Collections.Generic.List[object]) } }
  $races[$rk].hs.Add([pscustomobject]@{ nm=$nm; no=[int]$x.no; ch=[int]$x.ch; wk=$(if($x.wk -is [DBNull]){0}else{[int]$x.wk}); crk=$crk[$ck] }) }

$acc=@{}
function Add($k,$hit,$ret){ if(-not $acc.ContainsKey($k)){ $acc[$k]=@{n=0;hit=0;inv=0;ret=0} }; $a=$acc[$k]; $a.n++; if($hit){$a.hit++}; $a.inv+=100; $a.ret+=$ret }
function AddY($k,$yr,$hit,$ret){ Add $k $hit $ret; Add "$k|$yr" $hit $ret }

foreach($rk in $races.Keys){ $R=$races[$rk]; $field=$R.hs; if($field.Count -lt 6){ continue }
  $yr=$R.d.Substring(0,4); $surf= if($R.s -match 'ダ'){'ダ'}elseif($R.s -match '芝'){'芝'}else{'他'}; $cell="$surf$(Band $R.dist)"
  $c1=$field|Where-Object{$_.crk -eq 1}|Select-Object -First 1
  $c2=$field|Where-Object{$_.crk -eq 2}|Select-Object -First 1
  $c3=$field|Where-Object{$_.crk -eq 3}|Select-Object -First 1
  if(-not $c1 -or -not $c2){ continue }
  $top3=@($field|Where-Object{$_.ch -ge 1 -and $_.ch -le 3})
  $t1=$field|Where-Object{$_.ch -eq 1}|Select-Object -First 1
  $t2=$field|Where-Object{$_.ch -eq 2}|Select-Object -First 1
  if(-not $t1 -or -not $t2){ continue }
  $in3=@{}; foreach($h in $top3){ $in3[$h.no]=1 }
  # 馬連 コンピ1-2
  $pk=PairKey $c1.no $c2.no; $hit=($umaren.ContainsKey("$rk|$pk")); $ret= if($hit){$umaren["$rk|$pk"]}else{0}
  AddY '馬連_C1C2' $yr $hit $ret; AddY "馬連_C1C2|$cell" $yr $hit $ret
  # 枠連 コンピ1-2(枠pair)。同枠(ゾロ)はスキップ扱い(枠連組番に含まれる場合あり)
  if($c1.wk -ge 1 -and $c2.wk -ge 1){ $wpk=PairKey $c1.wk $c2.wk; $wh=($wakuren.ContainsKey("$rk|$wpk")); $wr= if($wh){$wakuren["$rk|$wpk"]}else{0}
    AddY '枠連_C1C2' $yr $wh $wr; AddY "枠連_C1C2|$cell" $yr $wh $wr }
  # ワイド コンピ1-2 / 1-3 / 軸流し(1-2,1-3の2点)
  $w12=($in3.ContainsKey($c1.no) -and $in3.ContainsKey($c2.no)); $r12= if($w12){$wide["$rk|$(PairKey $c1.no $c2.no)"]}else{0}; if($null -eq $r12){$r12=0}
  AddY 'ワイド_C1C2' $yr $w12 $r12; AddY "ワイド_C1C2|$cell" $yr $w12 $r12
  if($c3){ $w13=($in3.ContainsKey($c1.no) -and $in3.ContainsKey($c3.no)); $r13= if($w13){$wide["$rk|$(PairKey $c1.no $c3.no)"]}else{0}; if($null -eq $r13){$r13=0}
    AddY 'ワイド_C1C3' $yr $w13 $r13
    # 軸流し2点(投資200): 各点100
    if(-not $acc.ContainsKey('ワイド軸流し2点')){}
    $rf=$r12+$r13; if(-not $acc.ContainsKey('ワイド軸流し')){ $acc['ワイド軸流し']=@{n=0;hit=0;inv=0;ret=0} }
    $a=$acc['ワイド軸流し']; $a.n++; $a.inv+=200; $a.ret+=$rf; if($w12 -or $w13){$a.hit++}
    $ay="ワイド軸流し|$yr"; if(-not $acc.ContainsKey($ay)){ $acc[$ay]=@{n=0;hit=0;inv=0;ret=0} }; $b=$acc[$ay]; $b.n++; $b.inv+=200; $b.ret+=$rf; if($w12 -or $w13){$b.hit++}
    $ac="ワイド軸流し|$cell"; if(-not $acc.ContainsKey($ac)){ $acc[$ac]=@{n=0;hit=0;inv=0;ret=0} }; $e=$acc[$ac]; $e.n++; $e.inv+=200; $e.ret+=$rf; if($w12 -or $w13){$e.hit++}
  }
}
$cn.Close()
function Pc($a,$b){ if($b){'{0,6:P1}' -f ($a/$b)}else{'  —  '} }
function Line($k,$lbl,$minN){ $a=$acc[$k]; if(-not $a){ Write-Host ("  {0,-16} n=0" -f $lbl); return }
  $roi=$a.ret/$a.inv
  $ys=@(); $allpos=$true; $anyY=$false
  foreach($y in 2022..2026){ $b=$acc["$k|$y"]; if($b -and $b.n -ge 5){ $anyY=$true; $rr=$b.ret/$b.inv; if($rr -le 1.0){$allpos=$false}; $ys+=("{0}:{1:P0}(n{2})" -f $y,$rr,$b.n) } }
  $flag= if($a.n -ge $minN -and $allpos -and $anyY){'★生存'}elseif($roi -gt 1.0){'△プール>100'}else{''}
  Write-Host ("  {0,-16} n={1,5} 的中{2} 回収{3,7:P1} {4}" -f $lbl,$a.n,(Pc $a.hit $a.n),$roi,$flag)
  if($roi -gt 1.0){ Write-Host ("        年別 {0}" -f ($ys -join ' ')) } }
Write-Host "`n===== 自律+EV総当たり Phase2: 低ボリューム組合せ馬券(コンピ上位)・全JRA2022-26 ====="
Write-Host "--- 全体 ---"
Line '馬連_C1C2' '馬連 C1-C2' 500
Line '枠連_C1C2' '枠連 C1-C2' 500
Line 'ワイド_C1C2' 'ワイド C1-C2' 500
Line 'ワイド_C1C3' 'ワイド C1-C3' 500
Line 'ワイド軸流し' 'ワイド軸流し(2点)' 500
Write-Host "--- 枠連×セル(最低ボリューム=非効率の芽) ---"
foreach($cl in 'ダ短','ダマ','ダ中','ダ長','芝短','芝マ','芝中','芝長'){ Line "枠連_C1C2|$cl" "枠連 $cl" 100 }
Write-Host "--- ワイド軸流し×セル ---"
foreach($cl in 'ダ短','ダマ','ダ中','ダ長','芝短','芝マ','芝中','芝長'){ Line "ワイド軸流し|$cl" "ワイド軸 $cl" 100 }
Write-Host "--- 馬連×セル ---"
foreach($cl in 'ダ短','ダマ','ダ中','ダ長','芝短','芝マ','芝中','芝長'){ Line "馬連_C1C2|$cl" "馬連 $cl" 100 }
Write-Host ("`n[{0:N0}s]" -f $sw.Elapsed.TotalSeconds)
