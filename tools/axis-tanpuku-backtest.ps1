<#
.SYNOPSIS
  推奨外/推奨レースの「軸馬」と「相手筆頭(p1)」を単勝・複勝で1点(各100円)買ったときの成績を集計する。
  blend(-ExportAll)で各レースの軸・相手筆頭+推奨フラグを求め、払戻金(単勝/複勝)で的中/回収を算出。
  投票履歴テーブルは使わない(汚さない)自己完結バックテスト。
.PARAMETER From/To  期間(両端含む)。-Date で単日。
.PARAMETER Venue    場で絞る(未指定=全場)。
.PARAMETER FieldMax/EhMin  blendの推奨判定条件(既定は本命運用と同じ)。
.PARAMETER Target   集計対象: 推奨外(既定) / 推奨 / 両方。
#>
[CmdletBinding()]
param(
  [string]$From='', [string]$To='', [string]$Date='', [string]$Venue='',
  [int]$FieldMax=8, [double]$EhMin=0.55
)
$ErrorActionPreference='Stop'
$root = Split-Path $PSScriptRoot -Parent
$connStr=(Get-Content (Join-Path $root '共通\appsettings.json') -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
$blend = Join-Path $PSScriptRoot 'compi-today-blend.ps1'
$pwsh = (Get-Command powershell.exe).Source
$tmpDir = Join-Path $env:TEMP 'compi-autovote'; New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
function Log($m){ Write-Host ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'),$m) }
function Q($sql,[hashtable]$p){
  $cn=New-Object System.Data.SqlClient.SqlConnection $connStr; $cn.Open()
  try{ $c=$cn.CreateCommand(); $c.CommandText=$sql; if($p){foreach($k in $p.Keys){[void]$c.Parameters.AddWithValue($k,$p[$k])}}
       $dt=New-Object System.Data.DataTable; (New-Object System.Data.SqlClient.SqlDataAdapter $c).Fill($dt)|Out-Null; ,$dt }
  finally{ $cn.Close() }
}

$dates=@()
if($From -and $To){ $d=[datetime]$From; $end=[datetime]$To; while($d -le $end){ $dates+=$d.ToString('yyyy-MM-dd'); $d=$d.AddDays(1) } }
elseif($Date){ $dates=@($Date) } else { throw "期間を指定してください(-Date か -From/-To)" }

# 集計器: 推奨/推奨外 それぞれ 全体 + 場別
function NewAgg{ @{ n=0; atH=0; atRet=0.0; afH=0; afRet=0.0; ptH=0; ptRet=0.0; pfH=0; pfRet=0.0;
  nO=0; otH=0; otRet=0.0; ofH=0; ofRet=0.0; pickP1=0 } }
$rej=NewAgg; $rec=NewAgg; $byVenRej=@{}; $byVenRec=@{}

foreach($dt in $dates){
  # その日の単勝/複勝 払戻を一括ロード: key "場|R|馬券" -> @{ 馬番 -> 金額 }
  $pay=@{}
  $pr = Q "SELECT 開催場所 v,レース番号 r,馬券,組番,金額 FROM dbo.払戻金 WHERE 開催日=@d AND 馬券 IN (N'単勝',N'複勝')" @{'@d'=$dt}
  foreach($x in $pr){ $k='{0}|{1}|{2}' -f [string]$x.v,[int]$x.r,[string]$x.馬券; if(-not $pay.ContainsKey($k)){$pay[$k]=@{}}; $pay[$k][[string]$x.組番]=[double]$x.金額 }
  if($pay.Count -eq 0){ Log "${dt}: 払戻データなし(スキップ)"; continue }

  # 単勝オッズ(最新スナップショット): key "場|R" -> @{ 馬番 -> 単勝オッズ }。無い日はオッズ条件をスキップ。
  $odv=@{}
  $orow = Q "WITH o AS (SELECT 開催場所,レース番号,馬番,単勝オッズ,ROW_NUMBER() OVER(PARTITION BY 開催場所,レース番号,馬番 ORDER BY 日時 DESC) rn FROM リアルタイムオッズ WHERE 開催日=@d) SELECT 開催場所 v,レース番号 r,馬番 u,単勝オッズ od FROM o WHERE rn=1 AND 単勝オッズ IS NOT NULL" @{'@d'=$dt}
  foreach($x in $orow){ $k='{0}|{1}' -f [string]$x.v,[int]$x.r; if(-not $odv.ContainsKey($k)){$odv[$k]=@{}}; $odv[$k][[string][int]$x.u]=[double]$x.od }

  # blend で軸+推奨フラグを取得
  $csv = Join-Path $tmpDir ("tp_{0}.csv" -f ($dt -replace '-',''))
  if(Test-Path $csv){ Remove-Item $csv -Force }
  $a=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$blend,'-Date',$dt,'-FieldMax',$FieldMax,'-EhMin',$EhMin,'-ExportAll',$csv)
  if($Venue){ $a+=@('-Venue',$Venue) }
  try{ & $pwsh @a 2>$null | Out-Null }catch{ Log "  ${dt} 分析失敗" }
  if(-not (Test-Path $csv)){ Log "${dt}: 解析対象なし"; continue }

  $cnt=0
  foreach($r in (Import-Csv $csv -Encoding UTF8)){
    $isRec = ("$($r.推奨)" -eq '1')
    $v=[string]$r.venue; $rno=[int]$r.race
    $ax=[string][int]$r.axis_uma; $p1= if("$($r.p1)" -ne ''){[string][int]$r.p1}else{''}
    $tk="$v|$rno|単勝"; $fk="$v|$rno|複勝"
    if(-not ($pay.ContainsKey($tk) -or $pay.ContainsKey($fk))){ continue }  # 結果未確定/未取込
    $byVen = if($isRec){$byVenRec}else{$byVenRej}
    if(-not $byVen.ContainsKey($v)){ $byVen[$v]=NewAgg }
    $tot = if($isRec){$rec}else{$rej}
    $axT= if($pay.ContainsKey($tk) -and $pay[$tk].ContainsKey($ax)){ $pay[$tk][$ax] } else { 0.0 }
    $axF= if($pay.ContainsKey($fk) -and $pay[$fk].ContainsKey($ax)){ $pay[$fk][$ax] } else { 0.0 }
    $p1T= if($p1 -ne '' -and $pay.ContainsKey($tk) -and $pay[$tk].ContainsKey($p1)){ $pay[$tk][$p1] } else { 0.0 }
    $p1F= if($p1 -ne '' -and $pay.ContainsKey($fk) -and $pay[$fk].ContainsKey($p1)){ $pay[$fk][$p1] } else { 0.0 }
    foreach($g in @($tot,$byVen[$v])){ $g.n++;
      $g.atRet+=$axT; if($axT -gt 0){$g.atH++}; $g.afRet+=$axF; if($axF -gt 0){$g.afH++};
      $g.ptRet+=$p1T; if($p1T -gt 0){$g.ptH++}; $g.pfRet+=$p1F; if($p1F -gt 0){$g.pfH++} }
    # オッズ高い方を1点買い(軸と相手筆頭の単勝オッズを比較。両方のオッズがある場合のみ)
    $ok="$v|$rno"
    if($p1 -ne '' -and $odv.ContainsKey($ok) -and $odv[$ok].ContainsKey($ax) -and $odv[$ok].ContainsKey($p1)){
      $pickP1sel = ($odv[$ok][$p1] -gt $odv[$ok][$ax])
      $pk= if($pickP1sel){$p1}else{$ax}
      $oT= if($pay.ContainsKey($tk) -and $pay[$tk].ContainsKey($pk)){ $pay[$tk][$pk] } else { 0.0 }
      $oF= if($pay.ContainsKey($fk) -and $pay[$fk].ContainsKey($pk)){ $pay[$fk][$pk] } else { 0.0 }
      foreach($g in @($tot,$byVen[$v])){ $g.nO++; if($pickP1sel){$g.pickP1++}; $g.otRet+=$oT; if($oT -gt 0){$g.otH++}; $g.ofRet+=$oF; if($oF -gt 0){$g.ofH++} }
    }
    $cnt++
  }
  Log ("{0}: 対象 {1} レース" -f $dt,$cnt)
}

function Pct($n,$d){ if($d -gt 0){ '{0:N1}%' -f (100.0*$n/$d) } else { '-' } }
function Fmt($label,$th,$tr,$fh,$fr,$n){
  $st=$n*100
  "{0} 単勝 的中{1,4}({2,6}) 回収{3,8} | 複勝 的中{4,4}({5,6}) 回収{6,8}" -f $label,$th,(Pct $th $n),(Pct $tr $st),$fh,(Pct $fh $n),(Pct $fr $st)
}
function Block($name,$g){
  Write-Host ("{0} 対象{1}レース" -f $name,$g.n)
  Write-Host ("    "+(Fmt '軸      ' $g.atH $g.atRet $g.afH $g.afRet $g.n))
  Write-Host ("    "+(Fmt '相手筆頭' $g.ptH $g.ptRet $g.pfH $g.pfRet $g.n))
  if($g.nO -gt 0){ Write-Host ("    "+(Fmt 'オッズ高' $g.otH $g.otRet $g.ofH $g.ofRet $g.nO)+("  [オッズ有{0}/相手選択{1}]" -f $g.nO,$g.pickP1)) }
}
Write-Host ("`n===== 軸/相手筆頭 単複1点(各100円) {0}〜{1}{2} (頭数≤{3} & 期待的中≥{4}) =====" -f $dates[0],$dates[-1],$(if($Venue){" "+$Venue}else{" 全場"}),$FieldMax,$EhMin)
Write-Host "`n【推奨外】フィルタで除外したレース"
Block '全体' $rej
foreach($v in ($byVenRej.Keys|Sort-Object { -$byVenRej[$_].n })){ Block ('  '+$v) $byVenRej[$v] }
Write-Host "`n【推奨】(参考: 実際に推奨したレース)"
Block '全体' $rec
foreach($v in ($byVenRec.Keys|Sort-Object { -$byVenRec[$_].n })){ Block ('  '+$v) $byVenRec[$v] }
