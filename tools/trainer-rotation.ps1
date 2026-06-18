<#
.SYNOPSIS
  調教師ごとの「必勝ローテ」と「勝負気配なし(叩き/延長)ローテ」を抽出します。

.DESCRIPTION
  指定場・期間の各走を、出走間隔・距離変化・乗替/継続・馬体重増減・前走着順 でバケット化し、
  調教師×要因×水準ごとに 勝率/複勝率/単勝回収率 を集計。調教師自身の平均勝率と比べて
   - 必勝ローテ = 勝率が平均の Lift倍以上 かつ 単勝回収率が高い(市場の見落とし)
   - 勝負気配なし = 勝率が平均の Low倍以下(叩き・距離延長など仕上げ途上で勝ちにきていない)
  を、最低標本数つきで抽出します。LAGは全履歴で計算(前走情報)。ばんえい除外。

.PARAMETER Venue / From / To / MinN / MinTrainer / Lift / Low
#>
[CmdletBinding()]
param(
    [string]$Venue = '高知',
    [string]$From = '2024-01-01',
    [string]$To = (Get-Date).ToString('yyyy-MM-dd'),
    [int]$MinN = 15,            # (調教師×単要因水準)の最低標本
    [int]$PairMinN = 10,        # (調教師×2要因水準)の最低標本
    [int]$MinTrainer = 80,      # 調教師の最低総走数
    [double]$Lift = 1.8,        # 必勝: 勝率 >= 平均×Lift
    [double]$Low = 0.4          # 気配なし: 勝率 <= 平均×Low
)
$ErrorActionPreference='Stop'
$appsettings = Join-Path $PSScriptRoot '..\共通\appsettings.json'
$connStr=(Get-Content $appsettings -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
$conn=New-Object System.Data.SqlClient.SqlConnection($connStr); $conn.Open()
$cmd=$conn.CreateCommand(); $cmd.CommandTimeout=600
$cmd.CommandText=@"
WITH runs AS (
  SELECT r.馬名, r.開催場所 v, r.開催日 d, r.レース番号 rno, r.馬番 uma,
    r.調教師 tr, r.騎手 jk, r.距離 dist, r.馬体重 bw, r.馬体重増減 bwd, k.着順 c,
    LAG(r.開催日) OVER(PARTITION BY r.馬名 ORDER BY r.開催日,r.レース番号) pd,
    LAG(r.距離)   OVER(PARTITION BY r.馬名 ORDER BY r.開催日,r.レース番号) pdist,
    LAG(r.騎手)   OVER(PARTITION BY r.馬名 ORDER BY r.開催日,r.レース番号) pjk,
    LAG(k.着順)   OVER(PARTITION BY r.馬名 ORDER BY r.開催日,r.レース番号) pc
  FROM レース情報 r JOIN 競走結果 k ON k.開催場所=r.開催場所 AND k.開催日=r.開催日 AND k.レース番号=r.レース番号 AND k.馬番=r.馬番
  WHERE k.着順>0
)
SELECT tr 調教師, c 着順,
  DATEDIFF(day,pd,d) 間隔, dist-pdist 距離差, bw, bwd,
  CASE WHEN jk<>pjk THEN N'乗替' ELSE N'継続' END 乗替,
  pc 前着,
  t.金額 単勝
FROM runs
LEFT JOIN 払戻金 t ON t.馬券=N'単勝' AND t.開催場所=runs.v AND t.開催日=runs.d AND t.レース番号=runs.rno AND LTRIM(RTRIM(t.組番))=CAST(runs.uma AS nvarchar(3)) AND runs.c=1
WHERE runs.v=@v AND runs.d BETWEEN @f AND @to AND pd IS NOT NULL
"@
[void]$cmd.Parameters.AddWithValue('@v',$Venue);[void]$cmd.Parameters.AddWithValue('@f',$From);[void]$cmd.Parameters.AddWithValue('@to',$To)
$rd=$cmd.ExecuteReader()
$rows=@()
while($rd.Read()){
  $rows += [PSCustomObject]@{
    tr=$rd['調教師']; c=[int]$rd['着順']
    間隔=if($rd['間隔'] -is [DBNull]){$null}else{[int]$rd['間隔']}
    距離差=if($rd['距離差'] -is [DBNull]){$null}else{[int]$rd['距離差']}
    bw=if($rd['bw'] -is [DBNull]){0}else{[int]$rd['bw']}
    bwd=if($rd['bwd'] -is [DBNull]){0}else{[int]$rd['bwd']}
    乗替=$rd['乗替']
    前着=if($rd['前着'] -is [DBNull]){$null}else{[int]$rd['前着']}
    tan=if($rd['単勝'] -is [DBNull]){0.0}else{[double]$rd['単勝']}
  }
}
$rd.Close(); $conn.Close()
Write-Host ("対象: {0} {1}〜{2}  {3:N0}走" -f $Venue,$From,$To,$rows.Count)

# 要因→水準 の関数
function Lv-間隔($v){ if($null -eq $v){return $null}; if($v -le 8){'連闘'}elseif($v -le 13){'中1週'}elseif($v -le 20){'中2週'}elseif($v -le 27){'中3週'}elseif($v -le 45){'中4-6週'}else{'休明け'} }
function Lv-距離($v){ if($null -eq $v){return $null}; if($v -gt 0){'延長'}elseif($v -lt 0){'短縮'}else{'同距離'} }
function Lv-体重($bw,$d){ if($bw -le 0){return $null}; if($d -le -6){'大幅減≤-6'}elseif($d -le -1){'減-5〜-1'}elseif($d -eq 0){'増減0'}elseif($d -le 5){'増+1〜+5'}else{'大幅増≥+6'} }
function Lv-前着($v){ if($null -eq $v){return $null}; if($v -eq 1){'前1着'}elseif($v -le 3){'前2-3着'}elseif($v -le 5){'前4-5着'}else{'前6着以下'} }

# 調教師ベースライン
$base=@{}
foreach($r in $rows){ if(-not $base.ContainsKey($r.tr)){$base[$r.tr]=@{n=0;w=0}}; $base[$r.tr].n++; if($r.c -eq 1){$base[$r.tr].w++} }

# (調教師|要因|水準) 集計。単要因と2要因ペアの両方。
$cell=@{}   # キー -> @{n;w;t3;ret}
function Add-Cell($tr,$fac,$lv,$r){ if($null -eq $lv){return}; $k="$tr|$fac|$lv"; if(-not $cell.ContainsKey($k)){$cell[$k]=@{n=0;w=0;t3=0;ret=0.0}}; $cell[$k].n++; if($r.c -eq 1){$cell[$k].w++; $cell[$k].ret+=$r.tan/100.0}; if($r.c -le 3){$cell[$k].t3++} }
foreach($r in $rows){
  if($base[$r.tr].n -lt $MinTrainer){continue}
  # 各要因の水準を求める
  $facs=[ordered]@{ '間隔'=(Lv-間隔 $r.間隔); '距離'=(Lv-距離 $r.距離差); '乗替'=$r.乗替; '体重'=(Lv-体重 $r.bw $r.bwd); '前走'=(Lv-前着 $r.前着) }
  $keys=@($facs.Keys)
  # 単要因
  foreach($f in $keys){ Add-Cell $r.tr $f $facs[$f] $r }
  # 2要因ペア
  for($i=0;$i -lt $keys.Count;$i++){ for($j=$i+1;$j -lt $keys.Count;$j++){
    $a=$keys[$i]; $b=$keys[$j]; if($null -eq $facs[$a] -or $null -eq $facs[$b]){continue}
    Add-Cell $r.tr "$a×$b" "$($facs[$a])/$($facs[$b])" $r } }
}

$out=@()
foreach($k in $cell.Keys){ $p=$k -split '\|'; $tr=$p[0]; $fac=$p[1]; $lv=$p[2]; $c=$cell[$k]
  $isPair = $fac.Contains('×')
  $minNeeded = if($isPair){$PairMinN}else{$MinN}
  if($c.n -lt $minNeeded){continue}
  $bw=$base[$tr]; $bwr= if($bw.n){[double]$bw.w/$bw.n}else{0}
  $wr= [double]$c.w/$c.n
  $out += [PSCustomObject]@{ 調教師=$tr; 要因=$fac; 水準=$lv; 走数=$c.n; 勝率=[Math]::Round($wr*100,1); 平均=[Math]::Round($bwr*100,1); Lift=if($bwr -gt 0){[Math]::Round($wr/$bwr,2)}else{0}; 複勝率=[Math]::Round(100.0*$c.t3/$c.n,1); 単回収=[Math]::Round(100.0*$c.ret/$c.n,1); pair=$isPair }
}

Write-Host ("`n===== 【単要因】必勝ローテ (勝率≥平均×{0}・単回収≥100%・{1}走以上) =====" -f $Lift,$MinN)
$out | Where-Object{ -not $_.pair -and $_.Lift -ge $Lift -and $_.単回収 -ge 100 } | Sort-Object 単回収 -Descending |
  Format-Table 調教師,要因,水準,走数,勝率,平均,Lift,複勝率,単回収 -AutoSize | Out-String -Width 200 | Write-Host

Write-Host ("===== 【2要因】必勝ローテ (勝率≥平均×{0}・単回収≥100%・{1}走以上) =====" -f $Lift,$PairMinN)
$out | Where-Object{ $_.pair -and $_.Lift -ge $Lift -and $_.単回収 -ge 100 } | Sort-Object 単回収 -Descending | Select-Object -First 25 |
  Format-Table 調教師,要因,水準,走数,勝率,平均,Lift,複勝率,単回収 -AutoSize | Out-String -Width 200 | Write-Host

Write-Host ("===== 【2要因】勝負気配なし (勝率≤平均×{0}・{1}走以上=叩き/延長等) =====" -f $Low,$PairMinN)
$out | Where-Object{ $_.pair -and $_.平均 -ge 8 -and $_.勝率 -le ($_.平均*$Low) } | Sort-Object 走数 -Descending | Select-Object -First 25 |
  Format-Table 調教師,要因,水準,走数,勝率,平均,Lift,複勝率,単回収 -AutoSize | Out-String -Width 200 | Write-Host
