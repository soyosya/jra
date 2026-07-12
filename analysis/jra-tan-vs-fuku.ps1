<#
  「軸が固い」前提で単勝/複勝どちらを買うべきかをコンピ指数順で検証(全JRA2022-26)。
  各コンピ順位で 勝率/複勝率/単勝回収/複勝回収 を年別頑健に比較→順位ごとに単複の推奨。
  さらにコンピ1位×単勝オッズ帯で「固さの度合い」別の単複比較。realized払戻ベース(控除込み実回収)。leak無(コンピ/オッズ=事前)。
#>
[Console]::OutputEncoding=[Text.Encoding]::UTF8
$connStr=(Get-Content (Join-Path $PSScriptRoot '..\共通\appsettings.json') -Raw -Encoding UTF8 | ConvertFrom-Json).ConnectionStrings.DefaultConnection
$cn=New-Object System.Data.SqlClient.SqlConnection $connStr;$cn.Open();$c=$cn.CreateCommand();$c.CommandTimeout=600
function Q($sql){ $c.CommandText=$sql; $r=$c.ExecuteReader(); $t=New-Object System.Data.DataTable; $t.Load($r); ,$t }
$sw=[Diagnostics.Stopwatch]::StartNew()

# 着順(結果) 場日R馬番
$ch=@{}; foreach($x in (Q "SELECT 開催場所 v,CONVERT(varchar(10),開催日,23) d,レース番号 r,馬番 no,TRY_CONVERT(int,着順) c FROM dbo.競走結果 WHERE 開催日>='2022-01-01' AND TRY_CONVERT(int,着順)>0").Rows){ $ch["$($x.v)|$($x.d)|$($x.r)|$($x.no)"]=[int]$x.c }
# コンピ順位(最新)  馬名→順位、馬番対応は競走結果と別なので、コンピは馬名で持ち競走結果の馬名で引く
$crk=@{}; foreach($x in (Q "SELECT 開催場所 v,CONVERT(varchar(10),開催日,23) d,レース番号 r,馬名 nm,指数順位 rk FROM (SELECT 開催場所,開催日,レース番号,馬名,指数順位,ROW_NUMBER() OVER(PARTITION BY 開催場所,開催日,レース番号,馬名 ORDER BY 取得日時 DESC) sn FROM dbo.コンピ指数 WHERE 開催日>='2022-01-01' AND 指数順位 IS NOT NULL) z WHERE sn=1").Rows){ $crk["$($x.v)|$($x.d)|$($x.r)|$($x.nm)"]=[int]$x.rk }
# 単勝オッズ(最終)
$od=@{}; foreach($x in (Q "SELECT 開催場所 v,CONVERT(varchar(10),開催日,23) d,レース番号 r,馬番 no,TRY_CAST(単勝オッズ AS float) o FROM (SELECT *,ROW_NUMBER() OVER(PARTITION BY 開催場所,開催日,レース番号,馬番 ORDER BY 日時 DESC) sn FROM dbo.リアルタイムオッズ WHERE 開催日>='2022-01-01') z WHERE sn=1").Rows){ if($x.o -isnot [DBNull]){ $od["$($x.v)|$($x.d)|$($x.r)|$($x.no)"]=[double]$x.o } }
# 払戻(単/複) 馬番
$tan=@{}; $fuku=@{}; foreach($x in (Q "SELECT 開催場所 v,CONVERT(varchar(10),開催日,23) d,レース番号 r,馬券 bk,組番 kb,TRY_CAST(金額 AS int) kin FROM dbo.払戻金 WHERE 開催日>='2022-01-01' AND 馬券 IN (N'単勝',N'複勝')").Rows){ $no=0; if([int]::TryParse(("$($x.kb)").Trim(),[ref]$no)){ $kk="$($x.v)|$($x.d)|$($x.r)|$no"; if("$($x.bk)" -eq '単勝'){$tan[$kk]=[int]$x.kin}else{$fuku[$kk]=[int]$x.kin} } }
# 競走結果の馬名→馬番(コンピ順位を馬番へ写す)
Write-Host ("着順{0} コンピ{1} オッズ{2}  [{3:N0}s]" -f $ch.Count,$crk.Count,$od.Count,$sw.Elapsed.TotalSeconds)
$nmrows=Q "SELECT 開催場所 v,CONVERT(varchar(10),開催日,23) d,レース番号 r,馬番 no,馬名 nm FROM dbo.競走結果 WHERE 開催日>='2022-01-01' AND TRY_CONVERT(int,着順)>0"

$acc=@{}
function Add($k,$won,$t3,$tp,$fp){ if(-not $acc.ContainsKey($k)){ $acc[$k]=@{n=0;win=0;t3=0;inv=0;tan=0;fuk=0} }; $a=$acc[$k]; $a.n++; if($won){$a.win++}; if($t3){$a.t3++}; $a.inv+=100; $a.tan+=$tp; $a.fuk+=$fp }
function AddY($k,$yr,$won,$t3,$tp,$fp){ Add $k $won $t3 $tp $fp; Add "$k|$yr" $won $t3 $tp $fp }
foreach($x in $nmrows.Rows){ $kk="$($x.v)|$($x.d)|$($x.r)|$($x.no)"; $ckn="$($x.v)|$($x.d)|$($x.r)|$($x.nm)"
  if(-not $crk.ContainsKey($ckn) -or -not $ch.ContainsKey($kk)){ continue }
  $rk=$crk[$ckn]; $c=$ch[$kk]; $yr=($x.d).Substring(0,4); $won=($c -eq 1); $t3=($c -le 3)
  $tp= if($won -and $tan.ContainsKey($kk)){$tan[$kk]}else{0}; $fp= if($t3 -and $fuku.ContainsKey($kk)){$fuku[$kk]}else{0}
  $rb= if($rk -le 6){"順$rk"}elseif($rk -le 9){'順7-9'}else{'順10+'}
  AddY $rb $yr $won $t3 $tp $fp
  # コンピ1位×単勝オッズ帯
  if($rk -eq 1){ $o= if($od.ContainsKey($kk)){$od[$kk]}else{0}
    $ob= if($o -le 0){'?'}elseif($o -lt 1.5){'1位_o<1.5'}elseif($o -lt 2.5){'1位_o1.5-2.5'}elseif($o -lt 4){'1位_o2.5-4'}else{'1位_o4+'}
    if($ob -ne '?'){ AddY $ob $yr $won $t3 $tp $fp } }
}
$cn.Close()
function Pc($a,$b){ if($b){'{0,6:P1}' -f ($a/$b)}else{'  —  '} }
function Line($k,$lbl){ $a=$acc[$k]; if(-not $a){ return }
  $tr=$a.tan/$a.inv; $fr=$a.fuk/$a.inv; $rec= if($tr -gt $fr){'→単勝'}else{'→複勝'}; $gap=[math]::Abs($tr-$fr)*100
  # 年別: 単複どちらが勝ったか一貫性
  $tanWin=0;$fukWin=0; foreach($y in 2022..2026){ $b=$acc["$k|$y"]; if($b -and $b.n -ge 20){ if(($b.tan/$b.inv) -gt ($b.fuk/$b.inv)){$tanWin++}else{$fukWin++} } }
  $robust= if($tr -gt $fr -and $tanWin -ge 4){'(単勝が全年優勢)'}elseif($fr -gt $tr -and $fukWin -ge 4){'(複勝が全年優勢)'}else{'(年で入替)'}
  Write-Host ("  {0,-12} n={1,6} 勝率{2} 複勝率{3} | 単回収{4} 複回収{5} | 差{6,4:N1}pt {7} {8}" -f $lbl,$a.n,(Pc $a.win $a.n),(Pc $a.t3 $a.n),(Pc $a.tan $a.inv),(Pc $a.fuk $a.inv),$gap,$rec,$robust) }
Write-Host "`n===== 軸が固い前提: コンピ順位別 単勝 vs 複勝 回収(全JRA2022-26) ====="
Write-Host "  (推奨=回収率が高い方 / robust=年別で一貫して優勢か)"
foreach($r in 1..6){ Line "順$r" ("コンピ{0}位" -f $r) }
Line '順7-9' 'コンピ7-9位'; Line '順10+' 'コンピ10位以下'
Write-Host "`n--- 参考: コンピ1位×単勝オッズ帯(固さの度合い別) ---"
foreach($ob in '1位_o<1.5','1位_o1.5-2.5','1位_o2.5-4','1位_o4+'){ Line $ob ($ob -replace '1位_','1位 ') }
Write-Host "`n--- 年別内訳(コンピ1位/2位/3位の単・複回収) ---"
foreach($r in 1..3){ $line=("  コンピ{0}位:" -f $r); foreach($y in 2022..2026){ $b=$acc["順$r|$y"]; if($b){ $line+=(" {0}[単{1:P0}/複{2:P0}]" -f $y,($b.tan/$b.inv),($b.fuk/$b.inv)) } }; Write-Host $line }
Write-Host ("`n[{0:N0}s]" -f $sw.Elapsed.TotalSeconds)
