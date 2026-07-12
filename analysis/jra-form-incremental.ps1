<#
  「前走先行×上り速」が既存の連好(前走&前々走とも3着内)と独立に複勝率を上げるか=純増分の確認(全JRA2022-26)。
  連好でない馬の中でも前走先行×上り速が効けば実装価値あり。overlapと条件別複勝率を出す。leak無(全て過去走)。
#>
[Console]::OutputEncoding=[Text.Encoding]::UTF8
$connStr=(Get-Content (Join-Path $PSScriptRoot '..\共通\appsettings.json') -Raw -Encoding UTF8 | ConvertFrom-Json).ConnectionStrings.DefaultConnection
$cn=New-Object System.Data.SqlClient.SqlConnection $connStr;$cn.Open();$c=$cn.CreateCommand();$c.CommandTimeout=600
function Q($sql){ $c.CommandText=$sql; $r=$c.ExecuteReader(); $t=New-Object System.Data.DataTable; $t.Load($r); ,$t }
$sw=[Diagnostics.Stopwatch]::StartNew()
$rows=Q "SELECT k.馬名 nm,k.開催場所 v,CONVERT(varchar(10),k.開催日,23) d,k.レース番号 r,k.馬番 no,TRY_CONVERT(int,k.着順) ch,TRY_CONVERT(int,k.四コーナー) c4,TRY_CAST(k.上り3F AS float) ag FROM dbo.競走結果 k WHERE k.開催日>='2020-06-01' AND TRY_CONVERT(int,k.着順)>0"
$byRace=@{}; foreach($x in $rows.Rows){ $rk="$($x.v)|$($x.d)|$($x.r)"; if(-not $byRace.ContainsKey($rk)){ $byRace[$rk]=New-Object System.Collections.Generic.List[object] }; $byRace[$rk].Add($x) }
$agRank=@{}; $fldN=@{}
foreach($rk in $byRace.Keys){ $g=$byRace[$rk]; $fldN[$rk]=$g.Count; $wa=@($g|Where-Object{ $_.ag -isnot [DBNull] -and [double]$_.ag -gt 0 }|Sort-Object { [double]$_.ag }); for($i=0;$i -lt $wa.Count;$i++){ $agRank["$rk|$($wa[$i].no)"]=$i+1 } }
$byHorse=@{}
foreach($x in $rows.Rows){ $nm=[string]$x.nm; $rk="$($x.v)|$($x.d)|$($x.r)"; $n=$fldN[$rk]
  if(-not $byHorse.ContainsKey($nm)){ $byHorse[$nm]=New-Object System.Collections.Generic.List[object] }
  $sty= if($x.c4 -is [DBNull] -or $n -le 1){ '' } else { $c4=[int]$x.c4; $rat=$c4/[double]$n; if($c4 -le 1){'逃'}elseif($rat -le 0.34){'先'}elseif($rat -le 0.66){'差'}else{'追'} }
  $ar= if($agRank.ContainsKey("$rk|$($x.no)")){$agRank["$rk|$($x.no)"]}else{$null}
  $agFast= ($null -ne $ar -and $n -gt 1 -and ($ar/[double]$n) -le 0.25)
  $byHorse[$nm].Add([pscustomobject]@{ d=[string]$x.d;r=[int]$x.r;ch=[int]$x.ch;fwd=($sty -eq '逃' -or $sty -eq '先');fast=$agFast;t3=([int]$x.ch -le 3) }) }
foreach($nm in @($byHorse.Keys)){ $byHorse[$nm]=@($byHorse[$nm]|Sort-Object d,r) }
Write-Host ("馬{0}  [{1:N0}s]" -f $byHorse.Count,$sw.Elapsed.TotalSeconds)
$acc=@{}
function Add($k,$t3){ if(-not $acc.ContainsKey($k)){ $acc[$k]=@{n=0;t3=0} }; $acc[$k].n++; if($t3){$acc[$k].t3++} }
foreach($nm in $byHorse.Keys){ $h=$byHorse[$nm]
  for($i=1;$i -lt $h.Count;$i++){ $cur=$h[$i]; if($cur.d -lt '2022-01-01'){continue}
    $prev=$h[$i-1]; $sig=($prev.fwd -and $prev.fast); $t3=$cur.t3
    $renko= ($i -ge 2 -and $h[$i-1].t3 -and $h[$i-2].t3)
    Add 'base' $t3
    if($sig){ Add 'sig' $t3 }; if($renko){ Add 'renko' $t3 }
    if($sig -and $renko){ Add 'sig&renko' $t3 }
    if($sig -and -not $renko){ Add 'sig_noRenko' $t3 }
    if(-not $sig -and $renko){ Add 'renko_noSig' $t3 }
    if(-not $sig -and -not $renko){ Add 'neither' $t3 } } }
$cn.Close()
function P($k){ $a=$acc[$k]; if($a -and $a.n){ "{0,6:P1} (n{1})" -f ($a.t3/$a.n),$a.n }else{ '—' } }
Write-Host "`n===== 前走先行×上り速(sig) vs 連好(renko) の複勝率・純増分 ====="
Write-Host ("  base(前走あり)         : {0}" -f (P 'base'))
Write-Host ("  sig(前走先行×上り速)    : {0}" -f (P 'sig'))
Write-Host ("  renko(連好)            : {0}" -f (P 'renko'))
Write-Host ("  sig ∩ renko           : {0}" -f (P 'sig&renko'))
Write-Host ("  ★sig ∩ 非連好(純増分)  : {0}" -f (P 'sig_noRenko'))
Write-Host ("  renko ∩ 非sig          : {0}" -f (P 'renko_noSig'))
Write-Host ("  どちらも無し            : {0}" -f (P 'neither'))
$so=$acc['sig']; $sr=$acc['sig&renko']; if($so.n){ Write-Host ("`n  overlap: sig馬のうち連好は {0:P1} (=独立性 {1:P1})" -f ($sr.n/$so.n),(1-$sr.n/$so.n)) }
Write-Host ("`n[{0:N0}s]" -f $sw.Elapsed.TotalSeconds)
