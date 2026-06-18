<#
.SYNOPSIS
  高知競馬の日次馬場差補正(トラックバリアント)。同開催日の全レースの時計水準から
  日次補正値 δ を作り、補正後タイムで馬を比較できるようにします。

.DESCRIPTION
  - クラス交絡を避けるため期待タイムは「距離×一着賞金(クラス)」の平均勝ち時計。
    セル標本が少ない場合は距離別中央値で代替。
  - 破損タイムは妥当速度域(dist/18〜dist/11 [m/s])で除外。さらに距離中央値±12%で再フィルタ。
  - 日次馬場差 δ = その日の各レース偏差(勝ち時計−期待)の中央値。正なら時計が掛かる重い日。
  - 補正後タイム = 生タイム − δ。
  - 検証: 同一(距離×クラス)セルの勝ち時計の標準偏差が、補正前→補正後で縮むかを確認。

.PARAMETER From  集計開始日。既定 2024-01-01。
.PARAMETER RecentDays  末尾に表示する直近の日次δ件数。既定 20。
.EXAMPLE
  .\kochi-track-variant.ps1 -From 2024-01-01
#>
[CmdletBinding()]
param(
    [string]$From = '2024-01-01',
    [int]$RecentDays = 20
)
$ErrorActionPreference = 'Stop'

$appsettings = Join-Path $PSScriptRoot '..\共通\appsettings.json'
if (Test-Path $appsettings) {
    $connStr = (Get-Content $appsettings -Raw -Encoding UTF8 | ConvertFrom-Json).ConnectionStrings.DefaultConnection
}
if ([string]::IsNullOrWhiteSpace($connStr)) {
    $connStr = "Server=192.168.168.81\SQLEXPRESS;Database=中央競馬;User Id=sa;Password=$($env:KEIBA_SA_PASSWORD);TrustServerCertificate=True;Connect Timeout=10"
}

# 各レースの勝ち時計(着順1)+距離+クラス(一着賞金)を取得
$sql = @"
DECLARE @venue nvarchar(10)=N'高知';
SELECT k.開催日, k.レース番号, rinfo.距離, rinfo.一着賞金 cls, k.走破時計 win_time
FROM 競走結果 k
JOIN レース情報 rinfo ON rinfo.開催場所=@venue AND rinfo.開催日=k.開催日 AND rinfo.レース番号=k.レース番号 AND rinfo.馬番=k.馬番
WHERE k.開催場所=@venue AND k.着順=1 AND k.走破時計>0 AND k.開催日>=@from
ORDER BY k.開催日, k.レース番号;
"@

function Median([double[]]$a) {
    if ($a.Count -eq 0) { return $null }
    $s = $a | Sort-Object
    $m = [int][math]::Floor($s.Count/2)
    if ($s.Count % 2) { return $s[$m] } else { return ($s[$m-1]+$s[$m])/2 }
}
function Stdev([double[]]$a) {
    if ($a.Count -lt 2) { return 0 }
    $mean = ($a | Measure-Object -Average).Average
    $v = 0.0; foreach($x in $a){ $v += ($x-$mean)*($x-$mean) }
    return [math]::Sqrt($v/($a.Count-1))
}

$conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
$conn.Open()
try {
    $cmd = $conn.CreateCommand(); $cmd.CommandTimeout=120; $cmd.CommandText=$sql
    [void]$cmd.Parameters.AddWithValue('@from',$From)
    $r = $cmd.ExecuteReader()
    $races = New-Object System.Collections.Generic.List[object]
    while ($r.Read()) {
        $races.Add([PSCustomObject]@{
            date=$r['開催日']; rno=[int]$r['レース番号']; dist=[int]$r['距離']
            cls=[double]$r['cls']; t=[double]$r['win_time']
        })
    }
    $r.Close()

    # 1) 妥当速度域フィルタ(dist/18 .. dist/11 [m/s])
    $valid = $races | Where-Object { $_.t -ge $_.dist/18.0 -and $_.t -le $_.dist/11.0 }
    # 2) 距離別中央値 ±12% で再フィルタ
    $distMed = @{}
    foreach($g in ($valid | Group-Object dist)){ $distMed[[int]$g.Name] = Median([double[]]($g.Group.t)) }
    $clean = $valid | Where-Object { $m=$distMed[$_.dist]; $_.t -ge $m*0.88 -and $_.t -le $m*1.12 }

    $dropped = $races.Count - $clean.Count
    Write-Host ("高知 馬場差補正  期間: {0}〜最新   勝ちレース {1} 件(妥当 {2} / 除外 {3})" -f $From,$races.Count,$clean.Count,$dropped)

    # 3) 期待タイム: (距離×クラス)平均, 標本<8 は距離中央値で代替
    $cell = @{}
    foreach($g in ($clean | Group-Object {"$($_.dist)|$($_.cls)"})){
        $cell[$g.Name] = [PSCustomObject]@{ n=$g.Count; mean=($g.Group.t | Measure-Object -Average).Average }
    }
    foreach($x in $clean){
        $key = "$($x.dist)|$($x.cls)"
        $exp = if ($cell[$key].n -ge 8) { $cell[$key].mean } else { $distMed[$x.dist] }
        $x | Add-Member -NotePropertyName exp -NotePropertyValue $exp -Force
        $x | Add-Member -NotePropertyName dev -NotePropertyValue ($x.t - $exp) -Force
    }

    # 4) 日次 δ = その日のレース偏差の中央値
    $delta = @{}
    foreach($g in ($clean | Group-Object {$_.date.ToString('yyyy-MM-dd')})){
        $delta[$g.Name] = Median([double[]]($g.Group.dev))
    }
    $deltaVals = [double[]]($delta.Values)
    $sortedD = $deltaVals | Sort-Object
    Write-Host ("`n■ 日次馬場差 δ の分布(開催日 {0} 日)" -f $delta.Count)
    Write-Host ("  最速(δ小) {0:F2}s   P25 {1:F2}   中央 {2:F2}   P75 {3:F2}   最重(δ大) {4:F2}   レンジ {5:F2}s" -f `
        $sortedD[0], $sortedD[[int]($sortedD.Count*0.25)], (Median $deltaVals), $sortedD[[int]($sortedD.Count*0.75)], $sortedD[-1], ($sortedD[-1]-$sortedD[0]))

    # 5) 検証: 同一(距離×クラス)セルの勝ち時計 標準偏差 補正前 vs 補正後
    $rawSds=@(); $adjSds=@(); $wts=@()
    foreach($g in ($clean | Group-Object {"$($_.dist)|$($_.cls)"})){
        if ($g.Count -lt 10) { continue }
        $raw = [double[]]($g.Group.t)
        $adj = [double[]]($g.Group | ForEach-Object { $_.t - $delta[$_.date.ToString('yyyy-MM-dd')] })
        $rawSds += (Stdev $raw); $adjSds += (Stdev $adj); $wts += $g.Count
    }
    $wsum=($wts|Measure-Object -Sum).Sum
    $rawW=0.0;$adjW=0.0; for($i=0;$i -lt $wts.Count;$i++){ $rawW+=$rawSds[$i]*$wts[$i]; $adjW+=$adjSds[$i]*$wts[$i] }
    $rawW/=$wsum; $adjW/=$wsum
    Write-Host ("`n■ 検証: 同一(距離×クラス)セル {0} 種・勝ち時計の加重平均SD" -f $wts.Count)
    Write-Host ("  補正前 {0:F3}s  →  補正後 {1:F3}s   (縮小 {2:P1})" -f $rawW,$adjW,(($rawW-$adjW)/$rawW))

    # 6) 直近の日次δ
    Write-Host ("`n■ 直近 {0} 開催日の δ(+は重い/時計掛かる, -は軽い/速い)" -f $RecentDays)
    $delta.GetEnumerator() | Sort-Object Name -Descending | Select-Object -First $RecentDays |
        ForEach-Object { "  {0}  δ={1,6:F2}s" -f $_.Name, $_.Value }
}
finally { $conn.Close() }
