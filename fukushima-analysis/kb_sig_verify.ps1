<#
  競馬ブック信号の検証: 矢印上向き(調教.矢印∈↗↑) / 厩舎の話◎(印=◎) が買目に効くか。
  コンピ順位band固定で複勝率上乗せ(独立か)+単勝/複勝回収(+EVか)。2024-2026。+自己ベスト調教(06-20のみ・参考)。
#>
[CmdletBinding()] param([string]$From='2024-01-01')
$ErrorActionPreference='Stop'
try{ [Console]::OutputEncoding=[Text.Encoding]::UTF8 }catch{}
$cs=(Get-Content 'C:\jra\共通\appsettings.json' -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
$conn=New-Object System.Data.SqlClient.SqlConnection($cs);$conn.Open()
function Q($sql){ $c=$conn.CreateCommand();$c.CommandText=$sql;$c.CommandTimeout=300;$dt=New-Object System.Data.DataTable;(New-Object System.Data.SqlClient.SqlDataAdapter $c).Fill($dt)|Out-Null;,$dt.Rows }
function K($v,$d,$r,$x){ '{0}|{1}|{2}|{3}' -f $v,([datetime]$d).ToString('yyyy-MM-dd'),[int]$r,$x }

# 信号集合(場|日|R|馬名)
$yaji=@{}; foreach($x in (Q "SELECT DISTINCT 開催場所 v,開催日 d,レース番号 r,馬名 nm FROM dbo.調教 WHERE 開催日>='$From' AND 矢印 IN (N'↗',N'↑')")){ $yaji[(K $x.v $x.d $x.r $x.nm)]=$true }
$maru=@{}; foreach($x in (Q "SELECT DISTINCT 開催場所 v,開催日 d,レース番号 r,馬名 nm FROM dbo.厩舎の話 WHERE 開催日>='$From' AND 印=N'◎'")){ $maru[(K $x.v $x.d $x.r $x.nm)]=$true }
Write-Host ("信号: 矢印↗↑ $($yaji.Count) / 厩舎◎ $($maru.Count)")
# コンピ順位(場|日|R|馬番)
$crk=@{}; foreach($x in (Q "SELECT 開催場所 v,開催日 d,レース番号 r,馬番 no,指数順位 rk FROM (SELECT 開催場所,開催日,レース番号,馬番,指数順位,ROW_NUMBER() OVER(PARTITION BY 開催場所,開催日,レース番号,馬番 ORDER BY 取得日時 DESC) sn FROM dbo.コンピ指数 WHERE 開催日>='$From' AND 指数順位 IS NOT NULL) t WHERE sn=1")){ $crk[(K $x.v $x.d $x.r $x.no)]=[int]$x.rk }
# 払戻 単複(場|日|R|馬番)
$tan=@{};$fuku=@{}; foreach($x in (Q "SELECT 開催場所 v,開催日 d,レース番号 r,馬券 bt,組番 kb,TRY_CAST(金額 AS int) kin FROM dbo.払戻金 WHERE 開催日>='$From' AND 馬券 IN (N'単勝',N'複勝')")){ $no=0; if([int]::TryParse(("$($x.kb)").Trim(),[ref]$no)){ $k=(K $x.v $x.d $x.r $no); if("$($x.bt)" -eq '単勝'){$tan[$k]=[int]$x.kin}else{$fuku[$k]=[int]$x.kin} } }

# 結果行ループ
function Band($rk){ if($null -eq $rk){return $null}; if($rk -le 1){'コ1'}elseif($rk -le 3){'コ2-3'}elseif($rk -le 6){'コ4-6'}else{'コ7+'} }
$G=@{}  # "signal|band" -> @{n,w,f,ti,tr,fi,fr}
function Acc($key,$ch,$kf){ if(-not $G.ContainsKey($key)){$G[$key]=@{n=0;w=0;f=0;ti=0;tr=0;fi=0;fr=0}}; $o=$G[$key]
  $o.n++; if($ch -eq 1){$o.w++}; if($ch -le 3){$o.f++}; $o.ti+=100; if($ch -eq 1 -and $tan.ContainsKey($kf)){$o.tr+=$tan[$kf]}; $o.fi+=100; if($ch -le 3 -and $fuku.ContainsKey($kf)){$o.fr+=$fuku[$kf]} }
foreach($x in (Q "SELECT 開催場所 v,開催日 d,レース番号 r,馬番 no,馬名 nm,TRY_CONVERT(int,着順) ch FROM dbo.競走結果 WHERE 開催日>='$From' AND TRY_CONVERT(int,着順)>0")){
  $kf=(K $x.v $x.d $x.r ([int]$x.no)); $rk= if($crk.ContainsKey($kf)){$crk[$kf]}else{$null}; $b=Band $rk; if(-not $b){continue}
  $ch=[int]$x.ch; $knm=(K $x.v $x.d $x.r ([string]$x.nm))
  Acc ("全体|"+$b) $ch $kf
  if($yaji.ContainsKey($knm)){ Acc ("矢印↗|"+$b) $ch $kf }
  if($maru.ContainsKey($knm)){ Acc ("厩舎◎|"+$b) $ch $kf }
}
function Pc($a,$b){ if($b){'{0,5:P1}' -f ($a/$b)}else{'  — '} }
Write-Host ""
Write-Host "===== 競馬ブック信号 検証 ($From〜) コンピband別 複勝率/単複回収 ====="
Write-Host "(各bandで 全体 vs 矢印↗↑ vs 厩舎◎ を比較=独立シグナルか/+EVか)"
foreach($b in 'コ1','コ2-3','コ4-6','コ7+'){
  Write-Host ("--- $b ---")
  foreach($sig in '全体','矢印↗','厩舎◎'){ $k="$sig|$b"; if($G.ContainsKey($k)){ $o=$G[$k]; Write-Host ("  {0,-6} n={1,6} 複勝{2} 勝{3} 単回{4} 複回{5}" -f $sig,$o.n,(Pc $o.f $o.n),(Pc $o.w $o.n),(Pc $o.tr $o.ti),(Pc $o.fr $o.fi)) } }
}
# 自己ベスト調教(06-20のみ・参考): 新が自己ベスト(=pickup掲載)馬の複勝率
Write-Host ""
Write-Host "--- 自己ベスト調教 pickup (06-20のみ・参考・小サンプル) ---"
$sb=@{}; foreach($x in (Q "SELECT DISTINCT 開催場所 v,開催日 d,レース番号 r,馬名 nm FROM dbo.自己ベスト調教 WHERE 開催日='2026-06-20'")){ $sb[(K $x.v $x.d $x.r $x.nm)]=$true }
$sn=0;$sf=0;[long]$sti=0;[long]$str=0;[long]$sfi=0;[long]$sfr=0
foreach($x in (Q "SELECT 開催場所 v,開催日 d,レース番号 r,馬番 no,馬名 nm,TRY_CONVERT(int,着順) ch FROM dbo.競走結果 WHERE 開催日='2026-06-20' AND TRY_CONVERT(int,着順)>0")){
  $knm=(K $x.v $x.d $x.r ([string]$x.nm)); if(-not $sb.ContainsKey($knm)){continue}
  $kf=(K $x.v $x.d $x.r ([int]$x.no)); $ch=[int]$x.ch; $sn++; if($ch -le 3){$sf++}; $sti+=100; if($ch -eq 1 -and $tan.ContainsKey($kf)){$str+=$tan[$kf]}; $sfi+=100; if($ch -le 3 -and $fuku.ContainsKey($kf)){$sfr+=$fuku[$kf]}
}
Write-Host ("  自己ベスト掲載馬 n=$sn 複勝$(Pc $sf $sn) 単回$(Pc $str $sti) 複回$(Pc $sfr $sfi)")
$conn.Close()
