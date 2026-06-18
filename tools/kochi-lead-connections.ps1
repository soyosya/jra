<#
.SYNOPSIS
  高知「今走逃げ」を 調教師×馬主×騎手(三者コネクション)で深掘りし、さらに前走結果
  (脚質・枠順・騎手継続・上り3F)を重ねて逃げシグナルを精密化する。

.DESCRIPTION
  三者コネクションの逃げ率はリーブワンアウト(当該レースを除外)で算出し自己参照を排除。
  「強コネ」= 三者の延べ走数 >= MinN かつ LOO逃げ率 >= Thresh の馬。
  強コネ馬の中で、前走脚質/騎手継続(乗替有無)/前走上り3F帯/前走枠 が逃げ率をどう動かすかを集計。
  逃げ率と「逃げた時の単勝回収(¥100あたり払戻ベース)」を併記。

.PARAMETER From    集計開始日。既定 2024-01-01。
.PARAMETER MinN    強コネ判定の三者最小走数。既定 30。
.PARAMETER Thresh  強コネ判定のLOO逃げ率閾値(0-1)。既定 0.20。
#>
[CmdletBinding()]
param([string]$From='2024-01-01',[int]$MinN=30,[double]$Thresh=0.20)
$ErrorActionPreference='Stop'

$appsettings = Join-Path $PSScriptRoot '..\共通\appsettings.json'
if (Test-Path $appsettings) { $connStr=(Get-Content $appsettings -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection }
if ([string]::IsNullOrWhiteSpace($connStr)) { $connStr="Server=192.168.168.81\SQLEXPRESS;Database=中央競馬;User Id=sa;Password=$($env:KEIBA_SA_PASSWORD);TrustServerCertificate=True;Connect Timeout=10" }

$sql=@"
DECLARE @venue nvarchar(10)=N'高知';
IF OBJECT_ID('tempdb..#r') IS NOT NULL DROP TABLE #r;
SELECT k.開催日, k.レース番号, k.馬番, k.馬名, rinfo.調教師 tr, rinfo.馬主 ow, rinfo.騎手 jk,
  COALESCE(NULLIF(k.一コーナー,0),NULLIF(k.二コーナー,0),NULLIF(k.三コーナー,0),NULLIF(k.四コーナー,0)) ep, cnt.頭数, k.上り3F up3f
INTO #r FROM 競走結果 k
JOIN レース情報 rinfo ON rinfo.開催場所=@venue AND rinfo.開催日=k.開催日 AND rinfo.レース番号=k.レース番号 AND rinfo.馬番=k.馬番
CROSS APPLY (SELECT COUNT(*) 頭数 FROM 競走結果 k2 WHERE k2.開催場所=@venue AND k2.開催日=k.開催日 AND k2.レース番号=k.レース番号 AND k2.着順>0) cnt
WHERE k.開催場所=@venue AND k.着順>0;
CREATE INDEX ix1 ON #r(馬名,開催日,レース番号);

WITH base AS (
  SELECT cur.tr, cur.ow, cur.jk, cur.馬番 cur_uma, cur.頭数 cur_h,
    CASE WHEN cur.ep=1 THEN 1 ELSE 0 END lead,
    prv.jk prev_jk,
    CASE WHEN prv.ep=1 THEN N'逃げ' WHEN prv.ep<=prv.h*0.33 THEN N'先行' WHEN prv.ep<=prv.h*0.66 THEN N'差し' ELSE N'追込' END prevStyle,
    CAST(prv.uma-1 AS float)/NULLIF(prv.h-1,0) prev_rel,
    prv.up3f prev_up3f,
    ISNULL(ptan.金額,0) wp
  FROM #r cur
  CROSS APPLY (SELECT TOP 1 p.馬番 uma, p.頭数 h, p.ep, p.jk, p.up3f FROM #r p
     WHERE p.馬名=cur.馬名 AND (p.開催日<cur.開催日 OR (p.開催日=cur.開催日 AND p.レース番号<cur.レース番号))
     ORDER BY p.開催日 DESC, p.レース番号 DESC) prv
  LEFT JOIN 払戻金 ptan ON ptan.開催場所=@venue AND ptan.開催日=cur.開催日 AND ptan.レース番号=cur.レース番号 AND ptan.馬券=N'単勝' AND ptan.組番=CAST(cur.馬番 AS nvarchar(8))
  WHERE cur.開催日>='$From' AND cur.ep IS NOT NULL AND prv.ep IS NOT NULL
)
SELECT tr, ow, jk, lead, prev_jk, prevStyle, prev_rel, prev_up3f, wp,
  COUNT(*) OVER(PARTITION BY tr,ow,jk) tN,
  SUM(lead) OVER(PARTITION BY tr,ow,jk) tS
FROM base;
"@

$conn=New-Object System.Data.SqlClient.SqlConnection($connStr); $conn.Open()
try {
  $cmd=$conn.CreateCommand(); $cmd.CommandTimeout=300; $cmd.CommandText=$sql
  $r=$cmd.ExecuteReader(); $rows=New-Object System.Collections.Generic.List[object]
  while($r.Read()){
    $tN=[int]$r['tN']; $tS=[int]$r['tS']; $ld=[int]$r['lead']
    $loo= if($tN -gt 1){ ($tS-$ld)/($tN-1.0) } else { -1.0 }
    $up= if($r['prev_up3f'] -is [DBNull]){0.0}else{[double]$r['prev_up3f']}
    $rel= if($r['prev_rel'] -is [DBNull]){0.5}else{[double]$r['prev_rel']}
    $rows.Add([PSCustomObject]@{
      tr=[string]$r['tr']; ow=[string]$r['ow']; jk=[string]$r['jk']; pjk=[string]$r['prev_jk']
      lead=$ld; wp= if($r['wp'] -is [DBNull]){0.0}else{[double]$r['wp']}
      prevStyle=[string]$r['prevStyle']; prevRel=$rel; prevUp=$up
      tN=$tN; looLead=$loo
      swap=[int]($r['jk'] -ne $r['prev_jk'])
      strong=[int]($tN -ge $MinN -and $loo -ge $Thresh)
      drawCat=$( if($rel -le 0.33){'内'}elseif($rel -le 0.66){'中'}else{'外'} )
    })
  }
  $r.Close()
} finally { $conn.Close() }

function Agg($sub){
  $arr=@($sub); $n=$arr.Count; $l=0;$lwp=0.0
  foreach($x in $arr){ if($x.lead -eq 1){ $l++; $lwp+=$x.winPayProxy } }
  $lr=0.0; if($n -gt 0){$lr=$l/$n}; $roi=0.0; if($l -gt 0){$roi=$lwp/($l*100)}
  return [PSCustomObject]@{ n=$n; leadRate=$lr; leadRoi=$roi }
}
# winPayProxy: agg は wp を参照(プロパティ名統一)
foreach($x in $rows){ $x|Add-Member -NotePropertyName winPayProxy -NotePropertyValue $x.wp -Force }

function Line($sub,$label){ $a=Agg $sub; if($a.n -eq 0){return}
  Write-Host ("  {0,-22} n={1,5}  逃げ率 {2,7:P1}  逃時単回収 {3,7:P1}" -f $label,$a.n,$a.leadRate,$a.leadRoi) }

$all=$rows.ToArray()
$strong=$all.Where({$_.strong -eq 1})
$weak=$all.Where({$_.strong -eq 0})

Write-Host ("高知 三者コネクション×前走 深掘り  期間 {0}〜  対象 {1} 走" -f $From,$all.Count)
Write-Host ("  強コネ定義: 三者延べ>={0}走 かつ LOO逃げ率>={1:P0}" -f $MinN,$Thresh)
Line $all   '全体'
Line $strong '強コネ'
Line $weak  '非強コネ'

Write-Host "`n■ 強コネ × 前走脚質"
foreach($s in '逃げ','先行','差し','追込'){ Line ($strong.Where({$_.prevStyle -eq $s})) "強コネ×前走$s" }

Write-Host "`n■ 強コネ × 騎手継続/乗替"
Line ($strong.Where({$_.swap -eq 0})) '強コネ×同騎手継続'
Line ($strong.Where({$_.swap -eq 1})) '強コネ×乗り替わり'

Write-Host "`n■ 強コネ × 前走上り3F帯(速い=瞬発力/上位33%, 遅い=下位33%)"
$ups=@($strong.Where({$_.prevUp -gt 0}) | ForEach-Object{$_.prevUp} | Sort-Object)
if($ups.Count -ge 6){
  $q1=$ups[[int]($ups.Count*0.33)]; $q2=$ups[[int]($ups.Count*0.66)]
  Write-Host ("  (強コネ内の前走上り3F 33%点={0:F1}s / 66%点={1:F1}s)" -f $q1,$q2)
  Line ($strong.Where({$_.prevUp -gt 0 -and $_.prevUp -le $q1})) "強コネ×上り速い(<=$([math]::Round($q1,1)))"
  Line ($strong.Where({$_.prevUp -gt $q1 -and $_.prevUp -le $q2})) '強コネ×上り中位'
  Line ($strong.Where({$_.prevUp -gt $q2})) "強コネ×上り遅い(>$([math]::Round($q2,1)))"
}

Write-Host "`n■ 強コネ × 前走枠(相対)"
foreach($d in '内','中','外'){ Line ($strong.Where({$_.drawCat -eq $d})) "強コネ×前走$d 枠" }

Write-Host "`n■ 合わせ技: 強コネ × 前走先行/逃げ × 同騎手継続"
Line ($strong.Where({($_.prevStyle -eq '逃げ' -or $_.prevStyle -eq '先行') -and $_.swap -eq 0})) '強コネ×前走前々×同騎手'
Line ($strong.Where({($_.prevStyle -eq '逃げ' -or $_.prevStyle -eq '先行')})) '強コネ×前走前々(参考)'
