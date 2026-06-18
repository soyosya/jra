<#
.SYNOPSIS
  コンピ指数(日刊スポーツ)と着順の相関を集計し、予想ファクトの素地を出します。

.DESCRIPTION
  コンピ指数テーブル(最新スナップショット)を 競走結果(着順)・払戻金(単勝)と結合し、
   - 指数順位別: 勝率/複勝率/単勝回収率
   - 指数値帯別(40-49…90): 勝率/複勝率/単回収
   - 変遷別: 最初→最新スナップの順位変化(上昇/不変/下降)と好走(3着内)率
  を集計します。中央競馬の指数順位は市場(オッズ)未保存のため、的中率/回収率は自前集計が本筋。
  ばんえい除外。馬同定は (開催場所,開催日,レース番号,馬番)。

.PARAMETER Venue / From / To / MinN
#>
[CmdletBinding()]
param(
  [string]$Venue = '',
  [string]$From = '2024-01-01',
  [string]$To = (Get-Date).ToString('yyyy-MM-dd'),
  [int]$MinN = 20
)
$ErrorActionPreference='Stop'
$appsettings = Join-Path $PSScriptRoot '..\共通\appsettings.json'
$connStr=(Get-Content $appsettings -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
$conn=New-Object System.Data.SqlClient.SqlConnection($connStr); $conn.Open()
$cmd=$conn.CreateCommand(); $cmd.CommandTimeout=300
$cmd.CommandText=@"
WITH snap AS (
  SELECT 開催日,開催場所,レース番号,馬番,馬名,指数,指数順位,頭数,取得日時,
    ROW_NUMBER() OVER(PARTITION BY 開催日,開催場所,レース番号,馬番 ORDER BY 取得日時 DESC) rnLast,
    ROW_NUMBER() OVER(PARTITION BY 開催日,開催場所,レース番号,馬番 ORDER BY 取得日時 ASC)  rnFirst
  FROM コンピ指数
  WHERE 開催日 BETWEEN @f AND @to AND (@v='' OR 開催場所=@v)
)
SELECT l.開催場所, l.開催日, l.レース番号, l.馬番, l.指数, l.指数順位, l.頭数,
  f.指数順位 first順位, f.指数 first指数,
  k.着順, t.金額 単勝
FROM snap l
JOIN snap f ON f.開催日=l.開催日 AND f.開催場所=l.開催場所 AND f.レース番号=l.レース番号 AND f.馬番=l.馬番 AND f.rnFirst=1
LEFT JOIN 競走結果 k ON k.開催場所=l.開催場所 AND k.開催日=l.開催日 AND k.レース番号=l.レース番号 AND k.馬番=l.馬番 AND k.着順>0
LEFT JOIN 払戻金 t ON t.馬券=N'単勝' AND t.開催場所=l.開催場所 AND t.開催日=l.開催日 AND t.レース番号=l.レース番号 AND LTRIM(RTRIM(t.組番))=CAST(l.馬番 AS nvarchar(3)) AND k.着順=1
WHERE l.rnLast=1
"@
[void]$cmd.Parameters.AddWithValue('@v',$Venue);[void]$cmd.Parameters.AddWithValue('@f',$From);[void]$cmd.Parameters.AddWithValue('@to',$To)
$rd=$cmd.ExecuteReader(); $rows=New-Object System.Collections.Generic.List[object]
while($rd.Read()){
  $rows.Add([PSCustomObject]@{
    着順=if($rd['着順'] -is [DBNull]){$null}else{[int]$rd['着順']}
    指数=if($rd['指数'] -is [DBNull]){$null}else{[int]$rd['指数']}
    順位=if($rd['指数順位'] -is [DBNull]){$null}else{[int]$rd['指数順位']}
    first順位=if($rd['first順位'] -is [DBNull]){$null}else{[int]$rd['first順位']}
    単勝=if($rd['単勝'] -is [DBNull]){0.0}else{[double]$rd['単勝']}
  })
}
$rd.Close(); $conn.Close()

$fin = @($rows | Where-Object{ $null -ne $_.着順 })   # 着順確定のみ
Write-Host ("対象: {0} {1}〜{2}  コンピ行 {3:N0} / 着順確定 {4:N0}" -f ($(if($Venue){$Venue}else{'全場'})),$From,$To,$rows.Count,$fin.Count)
if($fin.Count -eq 0){ Write-Host "→ コンピ指数データが未投入(または結合できる着順なし)。fetch-compi で取得後に再実行してください。"; return }

function Agg($items){
  $n=$items.Count; if($n -eq 0){return $null}
  $w=@($items|Where-Object{$_.着順 -eq 1}).Count
  $t3=@($items|Where-Object{$_.着順 -le 3}).Count
  $ret=(@($items|Where-Object{$_.着順 -eq 1}) | Measure-Object 単勝 -Sum).Sum
  [PSCustomObject]@{ n=$n; 勝率=[Math]::Round(100.0*$w/$n,1); 複勝率=[Math]::Round(100.0*$t3/$n,1); 単回収=[Math]::Round(100.0*($ret/100.0)/$n,1) }
}

Write-Host "`n=== 指数順位別 ==="
$rows2=@()
foreach($g in ($fin | Group-Object 順位 | Sort-Object {[int]$_.Name})){
  if([string]::IsNullOrEmpty($g.Name)){continue}; if($g.Count -lt $MinN){continue}
  $a=Agg $g.Group; $rows2+=[PSCustomObject]@{ 指数順位=$g.Name; 走数=$a.n; 勝率=$a.勝率; 複勝率=$a.複勝率; 単回収=$a.単回収 }
}
$rows2 | Format-Table -AutoSize | Out-String -Width 160 | Write-Host

Write-Host "=== 指数値帯別 ==="
$band={ param($x) if($null -eq $x){'?'}elseif($x -ge 90){'90'}elseif($x -ge 80){'80-89'}elseif($x -ge 70){'70-79'}elseif($x -ge 60){'60-69'}elseif($x -ge 50){'50-59'}else{'40-49'} }
$rows3=@()
foreach($g in ($fin | Group-Object {& $band $_.指数})){
  if($g.Count -lt $MinN){continue}
  $a=Agg $g.Group; $rows3+=[PSCustomObject]@{ 指数帯=$g.Name; 走数=$a.n; 勝率=$a.勝率; 複勝率=$a.複勝率; 単回収=$a.単回収 }
}
$rows3 | Sort-Object 指数帯 | Format-Table -AutoSize | Out-String -Width 160 | Write-Host

Write-Host "=== 変遷別(最初→最新スナップの順位変化) ==="
$trend={ param($r) if($null -eq $r.first順位 -or $null -eq $r.順位){'不明'}elseif($r.first順位 -gt $r.順位){'上昇(順位↑)'}elseif($r.first順位 -lt $r.順位){'下降(順位↓)'}else{'不変'} }
$hasTrend = @($fin | Where-Object{ $_.first順位 -ne $_.順位 }).Count
if($hasTrend -eq 0){ Write-Host "  スナップショットが1時点のみ=変遷なし(複数回取得後に有効)。" }
else {
  $rows4=@()
  foreach($g in ($fin | Group-Object {& $trend $_})){
    $a=Agg $g.Group; $rows4+=[PSCustomObject]@{ 変遷=$g.Name; 走数=$a.n; 勝率=$a.勝率; 複勝率=$a.複勝率; 単回収=$a.単回収 }
  }
  $rows4 | Format-Table -AutoSize | Out-String -Width 160 | Write-Host
}
