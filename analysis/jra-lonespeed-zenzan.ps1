<#
  単騎速×前残り場×コンピ帯 の最終妙味探し(全JRA2022-26)。既知の芽(単騎速×コ1×前残り場108-115%)にコ2-3拡張を掛ける。
  前残り場=小倉/福島/函館/中京。単騎速馬をコンピ帯×場タイプ(前残り/差し)で単勝/複勝回収・年別。
  ※3フィルタ重ねでn極小・多重比較=プール>100も年別で崩れる前提で解釈。leak無(コンピ/脚質=事前)。
#>
[Console]::OutputEncoding=[Text.Encoding]::UTF8
$connStr=(Get-Content (Join-Path $PSScriptRoot '..\共通\appsettings.json') -Raw -Encoding UTF8 | ConvertFrom-Json).ConnectionStrings.DefaultConnection
$cn=New-Object System.Data.SqlClient.SqlConnection $connStr;$cn.Open();$c=$cn.CreateCommand();$c.CommandTimeout=600
function Q($sql){ $c.CommandText=$sql; $r=$c.ExecuteReader(); $t=New-Object System.Data.DataTable; $t.Load($r); ,$t }
$sw=[Diagnostics.Stopwatch]::StartNew()
$zenzan=@{'小倉'=1;'福島'=1;'函館'=1;'中京'=1}
$rows=Q "SELECT k.馬名 nm,k.開催場所 v,CONVERT(varchar(10),k.開催日,23) d,k.レース番号 r,k.馬番 no,TRY_CONVERT(int,k.着順) ch,TRY_CONVERT(int,k.四コーナー) c4 FROM dbo.競走結果 k WHERE k.開催日>='2020-06-01' AND TRY_CONVERT(int,k.着順)>0"
$fld=@{}; foreach($x in $rows.Rows){ $k="$($x.v)|$($x.d)|$($x.r)"; if($fld.ContainsKey($k)){$fld[$k]++}else{$fld[$k]=1} }
$byHorse=@{}
foreach($x in $rows.Rows){ $nm=[string]$x.nm; if(-not $byHorse.ContainsKey($nm)){ $byHorse[$nm]=New-Object System.Collections.Generic.List[object] }
  $n=$fld["$($x.v)|$($x.d)|$($x.r)"]
  $sty= if($x.c4 -is [DBNull] -or $n -le 1){ '' } else { $c4=[int]$x.c4; $rat=$c4/[double]$n; if($c4 -le 1){'逃'}elseif($rat -le 0.34){'先'}elseif($rat -le 0.66){'差'}else{'追'} }
  $byHorse[$nm].Add([pscustomobject]@{ d=[string]$x.d;r=[int]$x.r;sty=$sty }) }
foreach($nm in @($byHorse.Keys)){ $byHorse[$nm]=@($byHorse[$nm]|Sort-Object d,r) }
function PrevStyle($nm,$d){ if(-not $byHorse.ContainsKey($nm)){return ''}; $h=$byHorse[$nm]; for($i=$h.Count-1;$i -ge 0;$i--){ if($h[$i].d -lt $d -and $h[$i].sty -ne ''){ return $h[$i].sty } }; return '' }
$cprk=@{}; foreach($x in (Q "SELECT 開催場所 v,CONVERT(varchar(10),開催日,23) d,レース番号 r,馬名 nm,指数順位 rk FROM (SELECT 開催場所,開催日,レース番号,馬名,指数順位,ROW_NUMBER() OVER(PARTITION BY 開催場所,開催日,レース番号,馬名 ORDER BY 取得日時 DESC) sn FROM dbo.コンピ指数 WHERE 開催日>='2022-01-01' AND 指数順位 IS NOT NULL) z WHERE sn=1").Rows){ $cprk["$($x.v)|$($x.d)|$($x.r)|$($x.nm)"]=[int]$x.rk }
$tan=@{};$fuku=@{}; foreach($x in (Q "SELECT 開催場所 v,CONVERT(varchar(10),開催日,23) d,レース番号 r,馬券 bk,組番 kb,TRY_CAST(金額 AS int) kin FROM dbo.払戻金 WHERE 開催日>='2022-01-01' AND 馬券 IN (N'単勝',N'複勝')").Rows){ $no=0; if([int]::TryParse(("$($x.kb)").Trim(),[ref]$no)){ $kk="$($x.v)|$($x.d)|$($x.r)|$no"; if("$($x.bk)" -eq '単勝'){$tan[$kk]=[int]$x.kin}else{$fuku[$kk]=[int]$x.kin} } }
Write-Host ("履歴馬{0} コンピ{1}  [{2:N0}s]" -f $byHorse.Count,$cprk.Count,$sw.Elapsed.TotalSeconds)
$races=@{}
foreach($x in $rows.Rows){ if($x.d -lt '2022-01-01'){continue}; $rk="$($x.v)|$($x.d)|$($x.r)"; $ck="$rk|$($x.nm)"; if(-not $cprk.ContainsKey($ck)){continue}
  if(-not $races.ContainsKey($rk)){ $races[$rk]=@{v=[string]$x.v;hs=(New-Object System.Collections.Generic.List[object])} }
  $races[$rk].hs.Add([pscustomobject]@{ nm=[string]$x.nm; no=[int]$x.no; ch=[int]$x.ch; rk=$cprk[$ck]; pstyle=(PrevStyle ([string]$x.nm) ([string]$x.d)) }) }
$acc=@{}
function Add($k,$t3,$win,$tp,$fp){ if(-not $acc.ContainsKey($k)){ $acc[$k]=@{n=0;t3=0;win=0;inv=0;tan=0;fuk=0} }; $a=$acc[$k]; $a.n++; if($t3){$a.t3++}; if($win){$a.win++}; $a.inv+=100; $a.tan+=$tp; $a.fuk+=$fp }
function AddY($k,$yr,$t3,$win,$tp,$fp){ Add $k $t3 $win $tp $fp; Add "$k|$yr" $t3 $win $tp $fp }
foreach($rk in $races.Keys){ $R=$races[$rk].hs; if($R.Count -lt 8){ continue }; $p=$rk -split '\|'; $v=$p[0]; $yr=$p[1].Substring(0,4)
  $zt= if($zenzan.ContainsKey($v)){'前残'}else{'差場'}
  $speed=@($R|Where-Object{ $_.pstyle -eq '逃' -or $_.pstyle -eq '先' }); if($speed.Count -ne 1){ continue }; $lone=$speed[0]
  $cb= if($lone.rk -eq 1){'コ1'}elseif($lone.rk -le 3){'コ2-3'}elseif($lone.rk -le 6){'コ4-6'}else{'コ7+'}
  $t3=($lone.ch -le 3); $win=($lone.ch -eq 1); $kk="$rk|$($lone.no)"
  $tp= if($win -and $tan.ContainsKey($kk)){$tan[$kk]}else{0}; $fp= if($t3 -and $fuku.ContainsKey($kk)){$fuku[$kk]}else{0}
  AddY "$zt|$cb" $yr $t3 $win $tp $fp
  if($lone.rk -le 3){ AddY "$zt|コ1-3" $yr $t3 $win $tp $fp }   # コンテンダー(コ1-3)まとめ
}
$cn.Close()
function P($a,$b){ if($b){$a/$b}else{0} }
function Line($k,$lbl){ $a=$acc[$k]; if(-not $a){ Write-Host ("  {0,-14} n=0" -f $lbl); return }
  $ty=''; foreach($y in 2022..2026){ $b=$acc["$k|$y"]; if($b){ $ty+=(" {0}:単{1:P0}(n{2})" -f $y,(P $b.tan $b.inv),$b.n) } }
  Write-Host ("  {0,-14} n={1,4} 複勝{2:P1} 勝率{3:P1} 単回収{4:P1} 複回収{5:P1}" -f $lbl,$a.n,(P $a.t3 $a.n),(P $a.win $a.n),(P $a.tan $a.inv),(P $a.fuk $a.inv))
  if($a.n -ge 20){ Write-Host ("       $ty") } }
Write-Host "`n===== 単騎速×前残り場×コンピ帯(全JRA2022-26) ====="
Write-Host "■ 前残り場(小倉/福島/函館/中京)"
foreach($cb in 'コ1','コ2-3','コ1-3','コ4-6'){ Line "前残|$cb" "単騎速×$cb" }
Write-Host "`n■ 差し場(対照)"
foreach($cb in 'コ1','コ2-3','コ1-3','コ4-6'){ Line "差場|$cb" "単騎速×$cb" }
Write-Host ("`n[{0:N0}s]" -f $sw.Elapsed.TotalSeconds)
