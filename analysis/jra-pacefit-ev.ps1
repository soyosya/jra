<#
  単騎速×コンピ1位の+EV深掘り(全JRA 2022-26)。基底=単騎速×コ1位は単回収97.7%(全発見中で最も+EVに近い)。
  規律([[jra-ev-hunt]]): プール回収>100に飛びつかない・必ず年別頑健性(全年>100か)・n明記・多重比較の偽陽性を警戒。
  層: 場(前残り/差し)・種別(ダ/芝)・距離帯・自脚質(逃/先)・人気帯・馬場(良/道悪)・頭数・有望クロス。
  単騎速=フィールドで先行馬[逃/先]が1頭のみ。脚質=直近走の四コーナー/頭数。着順/コンピ/オッズは過去/最終スナップ(leak無・最終オッズで実現回収)。
#>
[Console]::OutputEncoding=[Text.Encoding]::UTF8
$connStr=(Get-Content (Join-Path $PSScriptRoot '..\共通\appsettings.json') -Raw -Encoding UTF8 | ConvertFrom-Json).ConnectionStrings.DefaultConnection
$cn=New-Object System.Data.SqlClient.SqlConnection $connStr;$cn.Open();$c=$cn.CreateCommand();$c.CommandTimeout=600
function Q($sql){ $c.CommandText=$sql; $r=$c.ExecuteReader(); $t=New-Object System.Data.DataTable; $t.Load($r); ,$t }
$sw=[Diagnostics.Stopwatch]::StartNew()
$zenzan=@{'小倉'=1;'福島'=1;'函館'=1;'中京'=1}
function Band($d){ if($d -le 1400){'短'}elseif($d -le 1799){'マ'}elseif($d -le 2200){'中'}else{'長'} }

# 競走結果(四コーナー→脚質)
$rows=Q "SELECT k.開催場所 v,CONVERT(varchar(10),k.開催日,23) d,k.レース番号 r,k.馬名 nm,k.馬番 no,TRY_CONVERT(int,k.着順) ch,TRY_CONVERT(int,k.四コーナー) c4 FROM dbo.競走結果 k WHERE k.開催日>='2021-06-01' AND TRY_CONVERT(int,k.着順)>0"
$fld=@{}; foreach($x in $rows.Rows){ $k="$($x.v)|$($x.d)|$($x.r)"; if($fld.ContainsKey($k)){$fld[$k]++}else{$fld[$k]=1} }
$byHorse=@{}
foreach($x in $rows.Rows){ $nm=[string]$x.nm; if(-not $byHorse.ContainsKey($nm)){ $byHorse[$nm]=New-Object System.Collections.Generic.List[object] }
  $n=$fld["$($x.v)|$($x.d)|$($x.r)"]
  $sty= if($x.c4 -is [DBNull] -or $n -le 1){ '' } else { $c4=[int]$x.c4; $rat=$c4/[double]$n; if($c4 -le 1){'逃'}elseif($rat -le 0.34){'先'}elseif($rat -le 0.66){'差'}else{'追'} }
  $byHorse[$nm].Add([pscustomobject]@{ d=[string]$x.d; r=[int]$x.r; sty=$sty }) }
foreach($nm in @($byHorse.Keys)){ $byHorse[$nm]=@($byHorse[$nm]|Sort-Object d,r) }
function PrevStyle($nm,$d){ if(-not $byHorse.ContainsKey($nm)){return ''}; $h=$byHorse[$nm]; for($i=$h.Count-1;$i -ge 0;$i--){ if($h[$i].d -lt $d -and $h[$i].sty -ne ''){ return $h[$i].sty } }; return '' }

# コンピ順位(最新スナップ)
$crk=@{}; foreach($x in (Q "SELECT 開催場所 v,CONVERT(varchar(10),開催日,23) d,レース番号 r,馬名 nm,指数順位 rk FROM (SELECT 開催場所,開催日,レース番号,馬名,指数順位,ROW_NUMBER() OVER(PARTITION BY 開催場所,開催日,レース番号,馬名 ORDER BY 取得日時 DESC) sn FROM dbo.コンピ指数 WHERE 開催日>='2022-01-01' AND 指数順位 IS NOT NULL) z WHERE sn=1").Rows){ $crk["$($x.v)|$($x.d)|$($x.r)|$($x.nm)"]=[int]$x.rk }
# 人気/単勝オッズ(最終スナップ)
$pop=@{}; $od=@{}; foreach($x in (Q "SELECT 開催場所 v,CONVERT(varchar(10),開催日,23) d,レース番号 r,馬番 no,人気 nin,TRY_CAST(単勝オッズ AS float) o FROM (SELECT *,ROW_NUMBER() OVER(PARTITION BY 開催場所,開催日,レース番号,馬番 ORDER BY 日時 DESC) sn FROM dbo.リアルタイムオッズ WHERE 開催日>='2022-01-01') z WHERE sn=1").Rows){ $kk="$($x.v)|$($x.d)|$($x.r)|$($x.no)"; if($x.nin -isnot [DBNull]){$pop[$kk]=[int]$x.nin}; if($x.o -isnot [DBNull]){$od[$kk]=[double]$x.o} }
# レース属性(種別/距離/馬場)
$meta=@{}; foreach($x in (Q "SELECT DISTINCT 開催場所 v,CONVERT(varchar(10),開催日,23) d,レース番号 r,コース種別 s,TRY_CAST(距離 AS int) dist,馬場 baba FROM dbo.レース情報 WHERE 開催日>='2022-01-01'").Rows){ $meta["$($x.v)|$($x.d)|$($x.r)"]=@{ s=[string]$x.s; dist=[int]$x.dist; baba=[string]$x.baba } }
# 払戻(単/複)
$tanPay=@{}; $fukuPay=@{}; foreach($x in (Q "SELECT 開催場所 v,CONVERT(varchar(10),開催日,23) d,レース番号 r,馬券 bk,組番 kb,TRY_CAST(金額 AS int) kin FROM dbo.払戻金 WHERE 開催日>='2022-01-01' AND 馬券 IN (N'単勝',N'複勝')").Rows){ $no=0; if([int]::TryParse(("$($x.kb)").Trim(),[ref]$no)){ $kk="$($x.v)|$($x.d)|$($x.r)|$no"; if("$($x.bk)" -eq '単勝'){$tanPay[$kk]=[int]$x.kin}else{$fukuPay[$kk]=[int]$x.kin} } }
Write-Host ("馬{0} コンピ{1} 人気{2} メタ{3}  [{4:N0}s]" -f $byHorse.Count,$crk.Count,$pop.Count,$meta.Count,$sw.Elapsed.TotalSeconds)

# 今走レース組立
$races=@{}
foreach($x in $rows.Rows){ if($x.d -lt '2022-01-01'){continue}; $rk="$($x.v)|$($x.d)|$($x.r)"; $nm=[string]$x.nm; $ck="$rk|$nm"; if(-not $crk.ContainsKey($ck)){continue}
  if(-not $races.ContainsKey($rk)){ $races[$rk]=New-Object System.Collections.Generic.List[object] }
  $races[$rk].Add([pscustomobject]@{ nm=$nm; no=[int]$x.no; ch=[int]$x.ch; crk=$crk[$ck]; pstyle=(PrevStyle $nm $x.d) }) }
Write-Host ("対象レース{0}  [{1:N0}s]" -f $races.Count,$sw.Elapsed.TotalSeconds)

$acc=@{}
function Add($k,$won,$t3,$tp,$fp){ if(-not $acc.ContainsKey($k)){ $acc[$k]=@{n=0;win=0;t3=0;inv=0;tan=0;fuk=0} }; $a=$acc[$k]; $a.n++; if($won){$a.win++}; if($t3){$a.t3++}; $a.inv+=100; $a.tan+=$tp; $a.fuk+=$fp }
foreach($rk in $races.Keys){ $parts=$rk -split '\|'; $v=$parts[0]; $yr=$parts[1].Substring(0,4)
  $field=$races[$rk]; if($field.Count -lt 6){ continue }
  $m=$meta[$rk]; if(-not $m){ continue }
  $speed=@($field|Where-Object{ $_.pstyle -eq '逃' -or $_.pstyle -eq '先' })
  if($speed.Count -ne 1){ continue }             # 単騎速レースのみ
  $ls=$speed[0]; if($ls.crk -ne 1){ continue }   # その単騎速馬がコンピ1位のみ
  $won=($ls.ch -eq 1); $t3=($ls.ch -le 3); $kk="$rk|$($ls.no)"
  $tp= if($won -and $tanPay.ContainsKey($kk)){$tanPay[$kk]}else{0}
  $fp= if($t3 -and $fukuPay.ContainsKey($kk)){$fukuPay[$kk]}else{0}
  $isZen=$zenzan.ContainsKey($v)
  $surf= if($m.s -match 'ダ'){'ダ'}elseif($m.s -match '芝'){'芝'}else{'他'}
  $bnd=Band $m.dist
  $selfSty=$ls.pstyle
  $nin= if($pop.ContainsKey($kk)){$pop[$kk]}else{0}
  $ninB= if($nin -eq 1){'人1'}elseif($nin -ge 2 -and $nin -le 3){'人2-3'}elseif($nin -ge 4){'人4+'}else{'人?'}
  $babaB= if($m.baba -match '良'){'良'}elseif($m.baba -ne ''){'道悪'}else{'?'}
  $fldB= if($field.Count -le 12){'≤12'}else{'13+'}
  # 各層に加算(全体+年別)
  $keys=@('ALL',
    ($(if($isZen){'前残り場'}else{'差し場'})),
    "種別_$surf","距離_$bnd","自_$selfSty",$ninB,"馬場_$babaB","頭_$fldB",
    ($(if($isZen){"前残り場×$surf"}else{$null})),
    ($(if($isZen){"前残り場×$ninB"}else{$null})),
    ($(if($isZen -and $surf -eq 'ダ'){'前残り場×ダ×'+$bnd}else{$null})) )
  foreach($k in $keys){ if($k){ Add $k $won $t3 $tp $fp; Add "$k|$yr" $won $t3 $tp $fp } }
}
$cn.Close()
function Pc($a,$b){ if($b){'{0,6:P1}' -f ($a/$b)}else{'   —  '} }
function L($k,$lbl){ if(-not $acc.ContainsKey($k)){ Write-Host ("  {0,-14} n=0" -f $lbl); return }; $a=$acc[$k]
  $yr=''; foreach($y in 2022..2026){ $b=$acc["$k|$y"]; if($b){ $yr+=(" {0}:単{1:P0}(n{2})" -f $y,($b.tan/$b.inv),$b.n) } }
  Write-Host ("  {0,-14} n={1,4} 勝率{2} 複勝{3} 単回収{4} 複回収{5}`n                   年別{6}" -f $lbl,$a.n,(Pc $a.win $a.n),(Pc $a.t3 $a.n),(Pc $a.tan $a.inv),(Pc $a.fuk $a.inv),$yr) }
Write-Host "`n===== 単騎速×コンピ1位 +EV深掘り(全JRA2022-26) ====="
L 'ALL' '★基底 全体'
Write-Host "--- 場 ---"; L '前残り場' '前残り場'; L '差し場' '差し場'
Write-Host "--- 種別 ---"; L '種別_ダ' 'ダート'; L '種別_芝' '芝'
Write-Host "--- 距離帯 ---"; foreach($b in '短','マ','中','長'){ L "距離_$b" "距離$b" }
Write-Host "--- 自分の前走脚質 ---"; L '自_逃' '前走=逃'; L '自_先' '前走=先'
Write-Host "--- 人気帯(未価格化の検定) ---"; L '人1' '人気1番'; L '人2-3' '人気2-3'; L '人4+' '人気4+'
Write-Host "--- 馬場 ---"; L '馬場_良' '良'; L '馬場_道悪' '道悪(稍重+)'
Write-Host "--- 頭数 ---"; L '頭_≤12' '≤12頭'; L '頭_13+' '13頭+'
Write-Host "--- 有望クロス ---"; L '前残り場×ダ' '前残×ダ'; L '前残り場×芝' '前残×芝'; L '前残り場×人1' '前残×人1'; L '前残り場×人2-3' '前残×人2-3'; L '前残り場×人4+' '前残×人4+'
foreach($b in '短','マ','中','長'){ L "前残り場×ダ×$b" "前残×ダ×$b" }
Write-Host ("`n[{0:N0}s]" -f $sw.Elapsed.TotalSeconds)
