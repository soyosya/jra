<#
  自律+EV総当たり Phase3(穴狙い・全JRA2022-26)。本命でなくコンピ2-3位/4-6位に単騎速・連好・オッズ帯フィルタで単複。
  仮説: 非効率があるなら流動性低い中穴。特に単騎速×コンピ2-3(展開優位×長オッズ)=単勝+EVの芽。
  規律: 生存=全年ROI>100 かつ 各年n>=5 かつ 総n>=閾。leak無(コンピ/オッズ=事前,単騎速=過去走)。
#>
[Console]::OutputEncoding=[Text.Encoding]::UTF8
$connStr=(Get-Content (Join-Path $PSScriptRoot '..\共通\appsettings.json') -Raw -Encoding UTF8 | ConvertFrom-Json).ConnectionStrings.DefaultConnection
$cn=New-Object System.Data.SqlClient.SqlConnection $connStr;$cn.Open();$c=$cn.CreateCommand();$c.CommandTimeout=600
function Q($sql){ $c.CommandText=$sql; $r=$c.ExecuteReader(); $t=New-Object System.Data.DataTable; $t.Load($r); ,$t }
$sw=[Diagnostics.Stopwatch]::StartNew()
$zenzan=@{'小倉'=1;'福島'=1;'函館'=1;'中京'=1}
function Band($d){ if($d -le 1400){'短'}elseif($d -le 1799){'マ'}elseif($d -le 2200){'中'}else{'長'} }

$rows=Q "SELECT k.開催場所 v,CONVERT(varchar(10),k.開催日,23) d,k.レース番号 r,k.馬名 nm,k.馬番 no,TRY_CONVERT(int,k.着順) ch,TRY_CONVERT(int,k.四コーナー) c4 FROM dbo.競走結果 k WHERE k.開催日>='2021-01-01' AND TRY_CONVERT(int,k.着順)>0"
$fld=@{}; foreach($x in $rows.Rows){ $k="$($x.v)|$($x.d)|$($x.r)"; if($fld.ContainsKey($k)){$fld[$k]++}else{$fld[$k]=1} }
$byHorse=@{}
foreach($x in $rows.Rows){ $nm=[string]$x.nm; if(-not $byHorse.ContainsKey($nm)){ $byHorse[$nm]=New-Object System.Collections.Generic.List[object] }
  $n=$fld["$($x.v)|$($x.d)|$($x.r)"]
  $sty= if($x.c4 -is [DBNull] -or $n -le 1){ '' } else { $c4=[int]$x.c4; $rat=$c4/[double]$n; if($c4 -le 1){'逃'}elseif($rat -le 0.34){'先'}elseif($rat -le 0.66){'差'}else{'追'} }
  $byHorse[$nm].Add([pscustomobject]@{ d=[string]$x.d; r=[int]$x.r; sty=$sty; ch=[int]$x.ch }) }
foreach($nm in @($byHorse.Keys)){ $byHorse[$nm]=@($byHorse[$nm]|Sort-Object d,r) }
function PrevStyle($nm,$d){ if(-not $byHorse.ContainsKey($nm)){return ''}; $h=$byHorse[$nm]; for($i=$h.Count-1;$i -ge 0;$i--){ if($h[$i].d -lt $d -and $h[$i].sty -ne ''){ return $h[$i].sty } }; return '' }
function RenKo($nm,$d){ if(-not $byHorse.ContainsKey($nm)){return $false}; $h=@($byHorse[$nm]|Where-Object{ $_.d -lt $d }); if($h.Count -lt 2){return $false}; $l=$h[-1].ch; $p=$h[-2].ch; return ($l -ge 1 -and $l -le 3 -and $p -ge 1 -and $p -le 3) }
$crk=@{}; foreach($x in (Q "SELECT 開催場所 v,CONVERT(varchar(10),開催日,23) d,レース番号 r,馬名 nm,指数順位 rk FROM (SELECT 開催場所,開催日,レース番号,馬名,指数順位,ROW_NUMBER() OVER(PARTITION BY 開催場所,開催日,レース番号,馬名 ORDER BY 取得日時 DESC) sn FROM dbo.コンピ指数 WHERE 開催日>='2022-01-01' AND 指数順位 IS NOT NULL) z WHERE sn=1").Rows){ $crk["$($x.v)|$($x.d)|$($x.r)|$($x.nm)"]=[int]$x.rk }
$od=@{}; foreach($x in (Q "SELECT 開催場所 v,CONVERT(varchar(10),開催日,23) d,レース番号 r,馬番 no,TRY_CAST(単勝オッズ AS float) o FROM (SELECT *,ROW_NUMBER() OVER(PARTITION BY 開催場所,開催日,レース番号,馬番 ORDER BY 日時 DESC) sn FROM dbo.リアルタイムオッズ WHERE 開催日>='2022-01-01') z WHERE sn=1").Rows){ if($x.o -isnot [DBNull]){$od["$($x.v)|$($x.d)|$($x.r)|$($x.no)"]=[double]$x.o} }
$ri=@{}; foreach($x in (Q "SELECT 開催場所 v,CONVERT(varchar(10),開催日,23) d,レース番号 r,馬番 no,コース種別 s,TRY_CAST(距離 AS int) dist FROM dbo.レース情報 WHERE 開催日>='2022-01-01'").Rows){ $ri["$($x.v)|$($x.d)|$($x.r)|$($x.no)"]=@{ s=[string]$x.s; dist=[int]$x.dist } }
$tanPay=@{}; $fukuPay=@{}; foreach($x in (Q "SELECT 開催場所 v,CONVERT(varchar(10),開催日,23) d,レース番号 r,馬券 bk,組番 kb,TRY_CAST(金額 AS int) kin FROM dbo.払戻金 WHERE 開催日>='2022-01-01' AND 馬券 IN (N'単勝',N'複勝')").Rows){ $no=0; if([int]::TryParse(("$($x.kb)").Trim(),[ref]$no)){ $kk="$($x.v)|$($x.d)|$($x.r)|$no"; if("$($x.bk)" -eq '単勝'){$tanPay[$kk]=[int]$x.kin}else{$fukuPay[$kk]=[int]$x.kin} } }
Write-Host ("履歴{0} コンピ{1} オッズ{2}  [{3:N0}s]" -f $byHorse.Count,$crk.Count,$od.Count,$sw.Elapsed.TotalSeconds)

$races=@{}
foreach($x in $rows.Rows){ if($x.d -lt '2022-01-01'){continue}; $rk="$($x.v)|$($x.d)|$($x.r)"; $nm=[string]$x.nm; $ck="$rk|$nm"; if(-not $crk.ContainsKey($ck)){continue}
  if(-not $races.ContainsKey($rk)){ $races[$rk]=New-Object System.Collections.Generic.List[object] }
  $races[$rk].Add([pscustomobject]@{ nm=$nm; no=[int]$x.no; ch=[int]$x.ch; crk=$crk[$ck]; pstyle=(PrevStyle $nm $x.d) }) }

$acc=@{}
function Add($k,$won,$t3,$tp,$fp){ if(-not $acc.ContainsKey($k)){ $acc[$k]=@{n=0;win=0;t3=0;inv=0;tan=0;fuk=0} }; $a=$acc[$k]; $a.n++; if($won){$a.win++}; if($t3){$a.t3++}; $a.inv+=100; $a.tan+=$tp; $a.fuk+=$fp }
function AddY($k,$yr,$won,$t3,$tp,$fp){ Add $k $won $t3 $tp $fp; Add "$k|$yr" $won $t3 $tp $fp }
foreach($rk in $races.Keys){ $p=$rk -split '\|'; $v=$p[0]; $yr=$p[1].Substring(0,4)
  $field=$races[$rk]; if($field.Count -lt 6){ continue }
  $speed=@($field|Where-Object{ $_.pstyle -eq '逃' -or $_.pstyle -eq '先' })
  $lone= if($speed.Count -eq 1){$speed[0].nm}else{''}
  $isZen=$zenzan.ContainsKey($v)
  foreach($h in $field){
    $cb= if($h.crk -eq 1){'C1'}elseif($h.crk -le 3){'C2-3'}elseif($h.crk -le 6){'C4-6'}elseif($h.crk -le 9){'C7-9'}else{'C10+'}
    if($cb -eq 'C1'){ continue }   # 穴狙い=非本命のみ
    $kk="$rk|$($h.no)"; $meta=$ri[$kk]; if(-not $meta){ continue }
    $won=($h.ch -eq 1); $t3=($h.ch -le 3)
    $tp= if($won -and $tanPay.ContainsKey($kk)){$tanPay[$kk]}else{0}
    $fp= if($t3 -and $fukuPay.ContainsKey($kk)){$fukuPay[$kk]}else{0}
    $surf= if($meta.s -match 'ダ'){'ダ'}elseif($meta.s -match '芝'){'芝'}else{'他'}; $bnd=Band $meta.dist
    $o= if($od.ContainsKey($kk)){$od[$kk]}else{0}
    $ob= if($o -le 0){'?'}elseif($o -lt 5){'o<5'}elseif($o -lt 10){'o5-10'}elseif($o -lt 20){'o10-20'}elseif($o -lt 50){'o20-50'}else{'o50+'}
    $isLone=($lone -eq $h.nm); $isRen=(RenKo $h.nm $p[1])
    # 基底(コンピ帯別・単複)
    AddY "単_$cb" $yr $won $t3 $tp 0; AddY "複_$cb" $yr $won $t3 0 $fp
    # 単騎速×帯
    if($isLone){ AddY "単_$cb×単騎速" $yr $won $t3 $tp 0; AddY "複_$cb×単騎速" $yr $won $t3 0 $fp
      if($isZen){ AddY "単_$cb×単騎速×前残場" $yr $won $t3 $tp 0 } }
    # 連好×帯
    if($isRen){ AddY "単_$cb×連好" $yr $won $t3 $tp 0; AddY "複_$cb×連好" $yr $won $t3 0 $fp }
    # オッズ帯×帯(単勝)
    AddY "単_$cb×$ob" $yr $won $t3 $tp 0
    # 単騎速×オッズ帯(単勝) 全帯まとめ
    if($isLone){ AddY "単_単騎速×$ob" $yr $won $t3 $tp 0 }
  } }
$cn.Close()
function Pc($a,$b){ if($b){'{0,6:P1}' -f ($a/$b)}else{'  —  '} }
function Line($k,$lbl,$mode,$minN){ $a=$acc[$k]; if(-not $a){ return }
  $roi= if($mode -eq '単'){$a.tan/$a.inv}else{$a.fuk/$a.inv}
  $ys=@(); $allpos=$true; $anyY=$false
  foreach($y in 2022..2026){ $b=$acc["$k|$y"]; if($b -and $b.n -ge 5){ $anyY=$true; $rr= if($mode -eq '単'){$b.tan/$b.inv}else{$b.fuk/$b.inv}; if($rr -le 1.0){$allpos=$false}; $ys+=("{0}:{1:P0}(n{2})" -f $y,$rr,$b.n) } }
  $flag= if($a.n -ge $minN -and $allpos -and $anyY){'★生存'}elseif($roi -gt 1.0){'△プール>100'}else{''}
  Write-Host ("  {0,-18} n={1,5} 勝率{2} 複勝{3} {4}回収{5,7:P1} {6}" -f $lbl,$a.n,(Pc $a.win $a.n),(Pc $a.t3 $a.n),$mode,$roi,$flag)
  if($roi -gt 1.0){ Write-Host ("        年別 {0}" -f ($ys -join ' ')) } }
Write-Host "`n===== 自律+EV総当たり Phase3: 穴狙い(非本命)・全JRA2022-26 ====="
Write-Host "--- コンピ帯別 基底(単勝) ---"; foreach($cb in 'C2-3','C4-6','C7-9','C10+'){ Line "単_$cb" "単 $cb" '単' 300 }
Write-Host "--- コンピ帯別 基底(複勝) ---"; foreach($cb in 'C2-3','C4-6','C7-9','C10+'){ Line "複_$cb" "複 $cb" '複' 300 }
Write-Host "--- 単騎速×帯(単勝=展開優位×長オッズ) ---"; foreach($cb in 'C2-3','C4-6','C7-9','C10+'){ Line "単_$cb×単騎速" "単 $cb×単騎速" '単' 20 }
Write-Host "--- 単騎速×帯(複勝) ---"; foreach($cb in 'C2-3','C4-6','C7-9','C10+'){ Line "複_$cb×単騎速" "複 $cb×単騎速" '複' 20 }
Write-Host "--- 単騎速×帯×前残場(単勝) ---"; foreach($cb in 'C2-3','C4-6','C7-9','C10+'){ Line "単_$cb×単騎速×前残場" "単 $cb×単騎速×前残" '単' 10 }
Write-Host "--- 連好×帯(単勝) ---"; foreach($cb in 'C2-3','C4-6','C7-9','C10+'){ Line "単_$cb×連好" "単 $cb×連好" '単' 50 }
Write-Host "--- 単騎速×オッズ帯(単勝・全非本命) ---"; foreach($ob in 'o<5','o5-10','o10-20','o20-50','o50+'){ Line "単_単騎速×$ob" "単 単騎速×$ob" '単' 15 }
Write-Host "--- C2-3×オッズ帯(単勝) ---"; foreach($ob in 'o<5','o5-10','o10-20','o20-50','o50+'){ Line "単_C2-3×$ob" "単 C2-3×$ob" '単' 100 }
Write-Host "--- C4-6×オッズ帯(単勝) ---"; foreach($ob in 'o<5','o5-10','o10-20','o20-50','o50+'){ Line "単_C4-6×$ob" "単 C4-6×$ob" '単' 100 }
Write-Host ("`n[{0:N0}s]" -f $sw.Elapsed.TotalSeconds)
