<#
.SYNOPSIS
  高知競馬「今走逃げる」を前走からの変化で分析。乗り替わり・枠順変化・前走脚質が
  逃げ発生確率にどう効くか、特に「前走非逃げ→今走逃げ(伏兵の逃げ)」の予測と妙味を検証。

.DESCRIPTION
  対象は直近に高知前走がある出走馬(2024+)。今走逃げ = 今走 early_pos=1。
  特徴量(すべて前走との差分・事前入手可):
    - 前走脚質(逃げ/先行/差し/追込)
    - 乗り替わり(同騎手/乗替)と乗替先騎手の前々率帯
    - 枠順(相対位置: 内/中/外)と前走からの内外シフト
  出力: 各要因別の今走逃げ率、伏兵の逃げの単勝回収率、予測コンビの妙味。

.PARAMETER From  集計開始日。既定 2024-01-01。
#>
[CmdletBinding()]
param([string]$From='2024-01-01')
$ErrorActionPreference='Stop'

$appsettings = Join-Path $PSScriptRoot '..\共通\appsettings.json'
if (Test-Path $appsettings) { $connStr=(Get-Content $appsettings -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection }
if ([string]::IsNullOrWhiteSpace($connStr)) { $connStr="Server=192.168.168.81\SQLEXPRESS;Database=中央競馬;User Id=sa;Password=$($env:KEIBA_SA_PASSWORD);TrustServerCertificate=True;Connect Timeout=10" }

$sql=@"
DECLARE @venue nvarchar(10)=N'高知';
IF OBJECT_ID('tempdb..#r') IS NOT NULL DROP TABLE #r;
SELECT k.開催日, k.レース番号, k.馬番, rinfo.馬名, rinfo.距離, rinfo.騎手, rinfo.馬場,
  COALESCE(NULLIF(k.一コーナー,0),NULLIF(k.二コーナー,0),NULLIF(k.三コーナー,0),NULLIF(k.四コーナー,0)) early_pos, cnt.頭数
INTO #r FROM 競走結果 k
JOIN レース情報 rinfo ON rinfo.開催場所=@venue AND rinfo.開催日=k.開催日 AND rinfo.レース番号=k.レース番号 AND rinfo.馬番=k.馬番
CROSS APPLY (SELECT COUNT(*) 頭数 FROM 競走結果 k2 WHERE k2.開催場所=@venue AND k2.開催日=k.開催日 AND k2.レース番号=k.レース番号 AND k2.着順>0) cnt
WHERE k.開催場所=@venue AND k.着順>0;
CREATE INDEX ix1 ON #r(馬名,開催日,レース番号);

SELECT cur.開催日, cur.レース番号, cur.馬番 cur_uma, cur.頭数 cur_heads, cur.early_pos cur_ep,
  cur.騎手 cur_jk, cur.距離 cur_dist, cur.馬場,
  prv.馬番 prev_uma, prv.頭数 prev_heads, prv.early_pos prev_ep, prv.騎手 prev_jk, prv.距離 prev_dist,
  ptan.金額 win_pay, CASE WHEN pfuku.金額 IS NOT NULL THEN 1 ELSE 0 END placed, ISNULL(pfuku.金額,0) place_pay
FROM #r cur
CROSS APPLY (SELECT TOP 1 p.馬番, p.頭数, p.early_pos, p.騎手, p.距離 FROM #r p
   WHERE p.馬名=cur.馬名 AND (p.開催日<cur.開催日 OR (p.開催日=cur.開催日 AND p.レース番号<cur.レース番号))
   ORDER BY p.開催日 DESC, p.レース番号 DESC) prv
LEFT JOIN 払戻金 ptan ON ptan.開催場所=@venue AND ptan.開催日=cur.開催日 AND ptan.レース番号=cur.レース番号 AND ptan.馬券=N'単勝' AND ptan.組番=CAST(cur.馬番 AS nvarchar(8))
LEFT JOIN 払戻金 pfuku ON pfuku.開催場所=@venue AND pfuku.開催日=cur.開催日 AND pfuku.レース番号=cur.レース番号 AND pfuku.馬券=N'複勝' AND pfuku.組番=CAST(cur.馬番 AS nvarchar(8))
WHERE cur.開催日>=@from AND cur.early_pos IS NOT NULL AND prv.early_pos IS NOT NULL;
"@

$conn=New-Object System.Data.SqlClient.SqlConnection($connStr); $conn.Open()
try {
  $cmd=$conn.CreateCommand(); $cmd.CommandTimeout=300; $cmd.CommandText=$sql
  [void]$cmd.Parameters.AddWithValue('@from',$From)
  $r=$cmd.ExecuteReader(); $rows=New-Object System.Collections.Generic.List[object]
  while($r.Read()){
    $rows.Add([PSCustomObject]@{
      jk=[string]$r['cur_jk']; pjk=[string]$r['prev_jk']
      curEp=[int]$r['cur_ep']; curH=[int]$r['cur_heads']; curUma=[int]$r['cur_uma']
      prevEp=[int]$r['prev_ep']; prevH=[int]$r['prev_heads']; prevUma=[int]$r['prev_uma']
      curDist=[int]$r['cur_dist']; prevDist=[int]$r['prev_dist']; ba=[string]$r['馬場']
      winPay= if($r['win_pay'] -is [DBNull]){0}else{[double]$r['win_pay']}
      placed=[int]$r['placed']; placePay=[double]$r['place_pay']
    })
  }
  $r.Close()
} finally { $conn.Close() }

# 騎手前々率(2024+全体, n>=50)
$jk=@{}
foreach($x in $rows){ $f=($x.curEp -eq 1 -or $x.curEp -le $x.curH*0.33)
  if(-not $jk.ContainsKey($x.jk)){$jk[$x.jk]=[PSCustomObject]@{n=0;f=0}}
  $jk[$x.jk].n++; if($f){$jk[$x.jk].f++} }
$jkRate=@{}; foreach($k in $jk.Keys){ if($jk[$k].n -ge 50){$jkRate[$k]=100.0*$jk[$k].f/$jk[$k].n} }

# 派生フラグ
foreach($x in $rows){
  $x|Add-Member -NotePropertyName lead -NotePropertyValue ([int]($x.curEp -eq 1)) -Force
  $x|Add-Member -NotePropertyName prevLead -NotePropertyValue ([int]($x.prevEp -eq 1)) -Force
  $x|Add-Member -NotePropertyName prevStyle -NotePropertyValue $( if($x.prevEp -eq 1){'逃げ'}elseif($x.prevEp -le $x.prevH*0.33){'先行'}elseif($x.prevEp -le $x.prevH*0.66){'差し'}else{'追込'} ) -Force
  $x|Add-Member -NotePropertyName swap -NotePropertyValue ([int]($x.jk -ne $x.pjk)) -Force
  $x|Add-Member -NotePropertyName newJkRate -NotePropertyValue $( if($jkRate.ContainsKey($x.jk)){$jkRate[$x.jk]}else{$null} ) -Force
  $curRel=[double]($x.curUma-1)/[math]::Max(1,$x.curH-1)
  $prevRel=[double]($x.prevUma-1)/[math]::Max(1,$x.prevH-1)
  $x|Add-Member -NotePropertyName curRel -NotePropertyValue $curRel -Force
  $x|Add-Member -NotePropertyName prevRel -NotePropertyValue $prevRel -Force
  $x|Add-Member -NotePropertyName drawCat -NotePropertyValue $( if($curRel -le 0.33){'内'}elseif($curRel -le 0.66){'中'}else{'外'} ) -Force
}

function Agg($sub){
  $arr=@($sub); $n=$arr.Count
  $l=0;$lwp=0.0;$pl=0;$pp=0.0
  foreach($x in $arr){
    if([int]$x.lead -eq 1){ $l++; $lwp += [double]$x.winPay }
    if([int]$x.placed -eq 1){ $pl++ }
    $pp += [double]$x.placePay
  }
  $leadRate=0.0; if($n -gt 0){ $leadRate=$l/$n }
  $leadRoi=0.0;  if($l -gt 0){ $leadRoi=$lwp/($l*100) }
  $placeRate=0.0;$placeRoi=0.0; if($n -gt 0){ $placeRate=$pl/$n; $placeRoi=$pp/($n*100) }
  return [PSCustomObject]@{ n=$n; lead=$l; leadRate=$leadRate; leadRoi=$leadRoi; placeRate=$placeRate; placeRoi=$placeRoi }
}
function Rate($sub,$label){
  $a=Agg $sub; if($a.n -eq 0){ return }
  Write-Host ("  {0,-26} n={1,5}  今走逃げ率 {2,7:P1}  (逃げた時の単回収 {3,7:P1})" -f $label,$a.n,$a.leadRate,$a.leadRoi)
}

Write-Host ("高知 今走逃げの規定要因  期間 {0}〜  対象(前走高知あり) {1} 件" -f $From,$rows.Count)
$leadCount=0; foreach($x in $rows){ if([int]$x.lead -eq 1){$leadCount++} }
Write-Host ("  全体の今走逃げ率: {0:P1}" -f ($leadCount/$rows.Count))

$allRows=$rows.ToArray()

Write-Host "`n■ (1) 前走脚質別の今走逃げ率"
foreach($s in '逃げ','先行','差し','追込'){ Rate ($allRows.Where({$_.prevStyle -eq $s})) "前走$s" }

Write-Host "`n■ (2) 前走非逃げ馬: 乗り替わり×乗替先騎手前々率"
$nl=$allRows.Where({[int]$_.prevLead -eq 0})
Rate ($nl.Where({[int]$_.swap -eq 0})) '同騎手継続'
Rate ($nl.Where({[int]$_.swap -eq 1})) '乗り替わり(全体)'
Rate ($nl.Where({[int]$_.swap -eq 1 -and $null -ne $_.newJkRate -and $_.newJkRate -ge 40})) '乗替→前々率40%以上騎手'
Rate ($nl.Where({[int]$_.swap -eq 1 -and $null -ne $_.newJkRate -and $_.newJkRate -ge 33 -and $_.newJkRate -lt 40})) '乗替→33-40%騎手'
Rate ($nl.Where({[int]$_.swap -eq 1 -and $null -ne $_.newJkRate -and $_.newJkRate -lt 33})) '乗替→33%未満騎手'

Write-Host "`n■ (3) 枠順(相対)別の今走逃げ率"
foreach($d in '内','中','外'){ Rate ($allRows.Where({$_.drawCat -eq $d})) "今走 $d 枠" }
Write-Host "  -- 前走非逃げ馬に限定(内枠を引いた効果) --"
foreach($d in '内','中','外'){ Rate ($nl.Where({$_.drawCat -eq $d})) "前走非逃げ×$d 枠" }

Write-Host "`n■ (4) 内外シフト(前走非逃げ馬)"
Rate ($nl.Where({($_.prevRel-$_.curRel) -ge 0.25})) '前走より内へ(+0.25)'
Rate ($nl.Where({[math]::Abs($_.prevRel-$_.curRel) -lt 0.25})) 'ほぼ同じ枠位置'
Rate ($nl.Where({($_.curRel-$_.prevRel) -ge 0.25})) '前走より外へ(+0.25)'

Write-Host "`n■ (5) 伏兵の逃げ(前走非逃げ→今走逃げ)の規模と妙味"
$nlAgg=Agg $nl
$surprise=$nl.Where({[int]$_.lead -eq 1})
$sAgg=Agg $surprise
$shareNL=0.0; if($nlAgg.n -gt 0){ $shareNL=$sAgg.n/$nlAgg.n }
Write-Host ("  前走非逃げ {0} 件中 今走逃げ {1} 件 ({2:P1})  単回収 {3:P1}  複勝率 {4:P1} 複回収 {5:P1}" -f `
  $nlAgg.n,$sAgg.n,$shareNL,$sAgg.leadRoi,$sAgg.placeRate,$sAgg.placeRoi)

Write-Host "`n■ (6) 予測コンビ: 前走先行(非逃げ)×内枠×前々率40%以上騎手 で今走逃げを狙う"
$combo=$nl.Where({$_.prevStyle -eq '先行' -and $_.drawCat -eq '内' -and $null -ne $_.newJkRate -and $_.newJkRate -ge 40})
$cAgg=Agg $combo
if($cAgg.n -gt 0){
  Write-Host ("  上記コンビ n={0}  今走逃げ率 {1:P1}  (逃げた時の単回収 {2:P1})" -f $cAgg.n,$cAgg.leadRate,$cAgg.leadRoi)
  # コンビ全部を単勝買いした場合(逃げ有無問わず)
  $cwp=0.0; foreach($x in $combo){ $cwp += [double]$x.winPay }
  Write-Host ("    → コンビ全部を単勝買い: n={0} 単回収 {1:P1} 複回収 {2:P1}" -f $cAgg.n,($cwp/($cAgg.n*100)),$cAgg.placeRoi)
}
