<#
  自律+EV総当たり Phase1(単勝/複勝・全JRA2022-26)。per-horse強化データを構築し、多数の賭け条件をROI×年別で自動評価。
  規律([[jra-ev-hunt]]): 生存=全5年でROI>100% かつ 総n>=閾 かつ 各年n>=5。プール高回収は年別崩壊を必ず表示。
  leak無: コンピ順位/単オッズ=最終スナップ(事前) / 着順・払戻=結果 / 単騎速・連好=過去走のみ。
#>
[Console]::OutputEncoding=[Text.Encoding]::UTF8
$connStr=(Get-Content (Join-Path $PSScriptRoot '..\共通\appsettings.json') -Raw -Encoding UTF8 | ConvertFrom-Json).ConnectionStrings.DefaultConnection
$cn=New-Object System.Data.SqlClient.SqlConnection $connStr;$cn.Open();$c=$cn.CreateCommand();$c.CommandTimeout=600
function Q($sql){ $c.CommandText=$sql; $r=$c.ExecuteReader(); $t=New-Object System.Data.DataTable; $t.Load($r); ,$t }
$sw=[Diagnostics.Stopwatch]::StartNew()
$zenzan=@{'小倉'=1;'福島'=1;'函館'=1;'中京'=1}
function Band($d){ if($d -le 1400){'短'}elseif($d -le 1799){'マ'}elseif($d -le 2200){'中'}else{'長'} }

# 1) 競走結果(着順/四コーナー) 全期間(履歴用)
$rows=Q "SELECT k.開催場所 v,CONVERT(varchar(10),k.開催日,23) d,k.レース番号 r,k.馬名 nm,k.馬番 no,TRY_CONVERT(int,k.着順) ch,TRY_CONVERT(int,k.四コーナー) c4 FROM dbo.競走結果 k WHERE k.開催日>='2021-01-01' AND TRY_CONVERT(int,k.着順)>0"
$fld=@{}; foreach($x in $rows.Rows){ $k="$($x.v)|$($x.d)|$($x.r)"; if($fld.ContainsKey($k)){$fld[$k]++}else{$fld[$k]=1} }
$byHorse=@{}
foreach($x in $rows.Rows){ $nm=[string]$x.nm; if(-not $byHorse.ContainsKey($nm)){ $byHorse[$nm]=New-Object System.Collections.Generic.List[object] }
  $n=$fld["$($x.v)|$($x.d)|$($x.r)"]
  $sty= if($x.c4 -is [DBNull] -or $n -le 1){ '' } else { $c4=[int]$x.c4; $rat=$c4/[double]$n; if($c4 -le 1){'逃'}elseif($rat -le 0.34){'先'}elseif($rat -le 0.66){'差'}else{'追'} }
  $byHorse[$nm].Add([pscustomobject]@{ d=[string]$x.d; r=[int]$x.r; sty=$sty; ch=[int]$x.ch }) }
foreach($nm in @($byHorse.Keys)){ $byHorse[$nm]=@($byHorse[$nm]|Sort-Object d,r) }
function PrevStyle($nm,$d){ if(-not $byHorse.ContainsKey($nm)){return ''}; $h=$byHorse[$nm]; for($i=$h.Count-1;$i -ge 0;$i--){ if($h[$i].d -lt $d -and $h[$i].sty -ne ''){ return $h[$i].sty } }; return '' }
# 連好=前走かつ前々走とも3着内(過去走のみ)
function RenKo($nm,$d){ if(-not $byHorse.ContainsKey($nm)){return $false}; $h=@($byHorse[$nm]|Where-Object{ $_.d -lt $d }); if($h.Count -lt 2){return $false}; $l=$h[-1].ch; $p=$h[-2].ch; return ($l -ge 1 -and $l -le 3 -and $p -ge 1 -and $p -le 3) }

# 2) コンピ順位(最新)
$crk=@{}; foreach($x in (Q "SELECT 開催場所 v,CONVERT(varchar(10),開催日,23) d,レース番号 r,馬名 nm,指数順位 rk FROM (SELECT 開催場所,開催日,レース番号,馬名,指数順位,ROW_NUMBER() OVER(PARTITION BY 開催場所,開催日,レース番号,馬名 ORDER BY 取得日時 DESC) sn FROM dbo.コンピ指数 WHERE 開催日>='2022-01-01' AND 指数順位 IS NOT NULL) z WHERE sn=1").Rows){ $crk["$($x.v)|$($x.d)|$($x.r)|$($x.nm)"]=[int]$x.rk }
# 3) 人気/単オッズ(最終)
$pop=@{}; $od=@{}; foreach($x in (Q "SELECT 開催場所 v,CONVERT(varchar(10),開催日,23) d,レース番号 r,馬番 no,人気 nin,TRY_CAST(単勝オッズ AS float) o FROM (SELECT *,ROW_NUMBER() OVER(PARTITION BY 開催場所,開催日,レース番号,馬番 ORDER BY 日時 DESC) sn FROM dbo.リアルタイムオッズ WHERE 開催日>='2022-01-01') z WHERE sn=1").Rows){ $kk="$($x.v)|$($x.d)|$($x.r)|$($x.no)"; if($x.nin -isnot [DBNull]){$pop[$kk]=[int]$x.nin}; if($x.o -isnot [DBNull]){$od[$kk]=[double]$x.o} }
# 4) レース情報(種別/距離/馬場/枠/馬体重増減) per-horse
$ri=@{}; foreach($x in (Q "SELECT 開催場所 v,CONVERT(varchar(10),開催日,23) d,レース番号 r,馬番 no,コース種別 s,TRY_CAST(距離 AS int) dist,馬場 baba,TRY_CONVERT(int,枠番) waku,TRY_CONVERT(int,馬体重増減) dw FROM dbo.レース情報 WHERE 開催日>='2022-01-01'").Rows){ $ri["$($x.v)|$($x.d)|$($x.r)|$($x.no)"]=@{ s=[string]$x.s; dist=[int]$x.dist; baba=[string]$x.baba; waku=$(if($x.waku -is [DBNull]){0}else{[int]$x.waku}); dw=$(if($x.dw -is [DBNull]){-999}else{[int]$x.dw}) } }
# 5) 払戻(単/複)
$tanPay=@{}; $fukuPay=@{}; foreach($x in (Q "SELECT 開催場所 v,CONVERT(varchar(10),開催日,23) d,レース番号 r,馬券 bk,組番 kb,TRY_CAST(金額 AS int) kin FROM dbo.払戻金 WHERE 開催日>='2022-01-01' AND 馬券 IN (N'単勝',N'複勝')").Rows){ $no=0; if([int]::TryParse(("$($x.kb)").Trim(),[ref]$no)){ $kk="$($x.v)|$($x.d)|$($x.r)|$no"; if("$($x.bk)" -eq '単勝'){$tanPay[$kk]=[int]$x.kin}else{$fukuPay[$kk]=[int]$x.kin} } }
Write-Host ("履歴馬{0} コンピ{1} 人気{2} RI{3}  [{4:N0}s]" -f $byHorse.Count,$crk.Count,$pop.Count,$ri.Count,$sw.Elapsed.TotalSeconds)

# per-race field for 単騎速
$races=@{}
foreach($x in $rows.Rows){ if($x.d -lt '2022-01-01'){continue}; $rk="$($x.v)|$($x.d)|$($x.r)"; $nm=[string]$x.nm; $ck="$rk|$nm"; if(-not $crk.ContainsKey($ck)){continue}
  if(-not $races.ContainsKey($rk)){ $races[$rk]=New-Object System.Collections.Generic.List[object] }
  $races[$rk].Add([pscustomobject]@{ nm=$nm; no=[int]$x.no; ch=[int]$x.ch; crk=$crk[$ck]; pstyle=(PrevStyle $nm $x.d) }) }

# 集計エンジン: stratum×年
$acc=@{}
function Add($k,$won,$t3,$tp,$fp){ if(-not $acc.ContainsKey($k)){ $acc[$k]=@{n=0;win=0;t3=0;inv=0;tan=0;fuk=0} }; $a=$acc[$k]; $a.n++; if($won){$a.win++}; if($t3){$a.t3++}; $a.inv+=100; $a.tan+=$tp; $a.fuk+=$fp }
function AddY($k,$yr,$won,$t3,$tp,$fp){ Add $k $won $t3 $tp $fp; Add "$k|$yr" $won $t3 $tp $fp }

foreach($rk in $races.Keys){ $p=$rk -split '\|'; $v=$p[0]; $yr=$p[1].Substring(0,4)
  $field=$races[$rk]; if($field.Count -lt 5){ continue }
  $speed=@($field|Where-Object{ $_.pstyle -eq '逃' -or $_.pstyle -eq '先' })
  $lone= if($speed.Count -eq 1){$speed[0].nm}else{''}
  $isZen=$zenzan.ContainsKey($v)
  foreach($h in $field){
    if($h.crk -ne 1){ continue }        # ★コンピ1位のみを賭け対象(本命単複の+EVサブ条件を探索)
    $kk="$rk|$($h.no)"; $meta=$ri[$kk]; if(-not $meta){ continue }
    $won=($h.ch -eq 1); $t3=($h.ch -le 3)
    $tp= if($won -and $tanPay.ContainsKey($kk)){$tanPay[$kk]}else{0}
    $fp= if($t3 -and $fukuPay.ContainsKey($kk)){$fukuPay[$kk]}else{0}
    $surf= if($meta.s -match 'ダ'){'ダ'}elseif($meta.s -match '芝'){'芝'}else{'他'}
    $bnd=Band $meta.dist
    $o= if($od.ContainsKey($kk)){$od[$kk]}else{0}
    $ob= if($o -le 0){'?'}elseif($o -lt 1.5){'o<1.5'}elseif($o -lt 2.5){'o1.5-2.5'}elseif($o -lt 4){'o2.5-4'}elseif($o -lt 7){'o4-7'}else{'o7+'}
    $wk=$meta.waku
    $dw=$meta.dw
    $dwb= if($dw -eq -999){'体?'}elseif($dw -le -8){'体≤-8'}elseif($dw -lt 0){'体-1..-7'}elseif($dw -eq 0){'体0'}elseif($dw -le 7){'体+1..7'}else{'体+8'}
    $babaB= if($meta.baba -match '良'){'良'}elseif($meta.baba -ne ''){'道悪'}else{'?'}
    $fldB= if($field.Count -le 7){'頭5-7'}elseif($field.Count -le 12){'頭8-12'}else{'頭13+'}
    $isLone=($lone -eq $h.nm)
    $isRen=(RenKo $h.nm $p[1])
    # --- 戦略群(全てコンピ1位・単勝と複勝) ---
    AddY '単_ALL' $yr $won $t3 $tp 0
    AddY '複_ALL' $yr $won $t3 0 $fp
    AddY "単_$ob" $yr $won $t3 $tp 0
    AddY "複_$ob" $yr $won $t3 0 $fp
    AddY "単_$surf$bnd" $yr $won $t3 $tp 0
    AddY "複_$surf$bnd" $yr $won $t3 0 $fp
    if($wk -ge 1){ AddY "単_枠$wk" $yr $won $t3 $tp 0; AddY "複_枠$wk" $yr $won $t3 0 $fp }
    AddY "単_$dwb" $yr $won $t3 $tp 0
    AddY "複_$dwb" $yr $won $t3 0 $fp
    AddY "複_$fldB" $yr $won $t3 0 $fp
    AddY "単_$fldB" $yr $won $t3 $tp 0
    AddY "複_馬場$babaB" $yr $won $t3 0 $fp
    AddY "単_馬場$babaB" $yr $won $t3 $tp 0
    # 確度スタック
    if($isLone){ AddY '単_単騎速' $yr $won $t3 $tp 0; AddY '複_単騎速' $yr $won $t3 0 $fp }
    if($isRen){ AddY '単_連好' $yr $won $t3 $tp 0; AddY '複_連好' $yr $won $t3 0 $fp }
    if($isLone -and $isRen){ AddY '単_単騎速∩連好' $yr $won $t3 $tp 0; AddY '複_単騎速∩連好' $yr $won $t3 0 $fp }
    if($isLone -and $isZen){ AddY '単_単騎速∩前残場' $yr $won $t3 $tp 0 }
    if($ob -eq 'o1.5-2.5' -and $isLone){ AddY '単_o1.5-2.5∩単騎速' $yr $won $t3 $tp 0 }
  } }
$cn.Close()
function Pc($a,$b){ if($b){'{0,6:P1}' -f ($a/$b)}else{'  —  '} }
# 生存判定: 全年ROI>100(単はtan/inv,複はfuk/inv)・各年n>=5・総n>=$minN
function Survive($k,$mode,$minN){ $a=$acc[$k]; if(-not $a -or $a.n -lt $minN){return $null}
  $ys=@(); $allpos=$true; $anyY=$false
  foreach($y in 2022..2026){ $b=$acc["$k|$y"]; if($b -and $b.n -ge 5){ $anyY=$true; $roi= if($mode -eq '単'){$b.tan/$b.inv}else{$b.fuk/$b.inv}; if($roi -le 1.0){$allpos=$false}; $ys+=("{0}:{1:P0}(n{2})" -f $y,$roi,$b.n) } elseif($b){ $ys+=("{0}:n{1}" -f $y,$b.n) } }
  return @{ surv=($allpos -and $anyY); ys=($ys -join ' '); a=$a } }
function Report($title,$keys,$mode,$minN){ Write-Host "`n--- $title ---"
  foreach($k in $keys){ $a=$acc[$k]; if(-not $a){ continue }
    $roi= if($mode -eq '単'){$a.tan/$a.inv}else{$a.fuk/$a.inv}
    $s=Survive $k $mode $minN
    $flag= if($s -and $s.surv){'★生存'}elseif($roi -gt 1.0){'△プール>100'}else{''}
    Write-Host ("  {0,-20} n={1,5} 勝率{2} 複勝{3} {4}回収{5,7:P1} {6}" -f $k,$a.n,(Pc $a.win $a.n),(Pc $a.t3 $a.n),$mode,$roi,$flag)
    if($roi -gt 1.0 -and $s){ Write-Host ("       年別 {0}" -f $s.ys) } } }
Write-Host "`n===== 自律+EV総当たり Phase1: コンピ1位の単勝/複勝サブ条件(全JRA2022-26) ====="
Write-Host ("基底 単_ALL n={0}" -f $acc['単_ALL'].n)
Report '単勝×オッズ帯' @('単_ALL','単_o<1.5','単_o1.5-2.5','単_o2.5-4','単_o4-7','単_o7+') '単' 200
Report '複勝×オッズ帯' @('複_ALL','複_o<1.5','複_o1.5-2.5','複_o2.5-4','複_o4-7','複_o7+') '複' 200
Report '単勝×種別距離' @('単_ダ短','単_ダマ','単_ダ中','単_ダ長','単_芝短','単_芝マ','単_芝中','単_芝長') '単' 150
Report '複勝×種別距離' @('複_ダ短','複_ダマ','複_ダ中','複_ダ長','複_芝短','複_芝マ','複_芝中','複_芝長') '複' 150
Report '単勝×枠' @(1..8|ForEach-Object{"単_枠$_"}) '単' 150
Report '複勝×枠' @(1..8|ForEach-Object{"複_枠$_"}) '複' 150
Report '単勝×馬体重増減' @('単_体≤-8','単_体-1..-7','単_体0','単_体+1..7','単_体+8') '単' 150
Report '複勝×馬体重増減' @('複_体≤-8','複_体-1..-7','複_体0','複_体+1..7','複_体+8') '複' 150
Report '複勝×頭数(少頭数境界)' @('複_頭5-7','複_頭8-12','複_頭13+') '複' 100
Report '単勝×頭数' @('単_頭5-7','単_頭8-12','単_頭13+') '単' 100
Report '馬場' @('単_馬場良','単_馬場道悪','複_馬場良','複_馬場道悪') '単' 200
Report '確度スタック(単勝)' @('単_単騎速','単_連好','単_単騎速∩連好','単_単騎速∩前残場','単_o1.5-2.5∩単騎速') '単' 20
Report '確度スタック(複勝)' @('複_単騎速','複_連好','複_単騎速∩連好') '複' 20
Write-Host ("`n[{0:N0}s]" -f $sw.Elapsed.TotalSeconds)
