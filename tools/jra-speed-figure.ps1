<#
.SYNOPSIS
  中央競馬のスピード指数(馬場差補正トラックバリアント)を計算し、テーブル スピード指数 に焼く。

.DESCRIPTION
  地方版 kochi-track-variant.ps1 を中央用に拡張:
    - δ(日次馬場差)を (開催日×開催場所×コース種別) 単位で算出(中央は同日複数場・芝/ダ混在のため)。
    - クラス交絡を避け、期待タイムは (コース種別×距離×一着賞金[クラス]) セルの勝ち時計平均。標本<8 は (コース種別×距離) 中央値で代替。
    - 破損タイム除外: 妥当速度域 dist/18..dist/11 [m/s] → さらに (コース種別×距離) 中央値±12%。
    - δ = その(日×場×コース種別)の勝ち時計偏差(=勝ち時計−セル期待)の中央値。+で重い/時計掛かる。
    - 補正後タイム corr = 生タイム − δ。全着順馬に適用。
    - スピード指数 SF = 50 - 10 * z  (z は (コース種別×距離) 内での補正後タイム標準化)。速い馬ほど高い。
  検証として同一(コース種別×距離×クラス)セルの勝ち時計SDが補正前→補正後で縮むかを表示。
  結果は SqlBulkCopy で テーブル スピード指数 に全置換(対象期間分を delete→insert)。

.PARAMETER From  集計開始日。既定 2022-01-01(全期間)。
.PARAMETER To    集計終了日。既定 2100-01-01。
.EXAMPLE
  .\jra-speed-figure.ps1
#>
[CmdletBinding()]
param(
    [string]$From = '2022-01-01',
    [string]$To   = '2100-01-01'
)
$ErrorActionPreference = 'Stop'

$appsettings = Join-Path $PSScriptRoot '..\共通\appsettings.json'
$connStr = $null
if (Test-Path $appsettings) {
    try { $connStr = (Get-Content $appsettings -Raw -Encoding UTF8 | ConvertFrom-Json).ConnectionStrings.DefaultConnection } catch {}
}
if ([string]::IsNullOrWhiteSpace($connStr)) {
    $connStr = (Get-Content 'C:\jra\共通\appsettings.json' -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
}

function Median([double[]]$a) {
    if ($a.Count -eq 0) { return $null }
    $s = $a | Sort-Object
    $m = [int][math]::Floor($s.Count/2)
    if ($s.Count % 2) { return [double]$s[$m] } else { return ([double]$s[$m-1]+[double]$s[$m])/2 }
}
function Stdev([double[]]$a) {
    if ($a.Count -lt 2) { return 0.0 }
    $mean = ($a | Measure-Object -Average).Average
    $v = 0.0; foreach($x in $a){ $v += ($x-$mean)*($x-$mean) }
    return [math]::Sqrt($v/($a.Count-1))
}

$conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
$conn.Open()
try {
    # --- テーブル作成(冪等) ---
    $ddl = @"
IF OBJECT_ID('dbo.スピード指数','U') IS NULL
CREATE TABLE dbo.スピード指数(
    開催場所 nvarchar(10) NOT NULL,
    開催日   date         NOT NULL,
    レース番号 int        NOT NULL,
    馬番     int          NOT NULL,
    馬名     nvarchar(50) NULL,
    着順     int          NULL,
    距離     int          NULL,
    コース種別 nvarchar(4) NULL,
    馬場     nvarchar(4)  NULL,
    生時計   decimal(9,2) NULL,
    馬場差   decimal(9,3) NULL,   -- δ
    補正時計 decimal(9,3) NULL,
    SF       decimal(7,2) NULL,
    CONSTRAINT PK_スピード指数 PRIMARY KEY(開催場所,開催日,レース番号,馬番)
);
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name='IX_スピード指数_馬名日')
    CREATE INDEX IX_スピード指数_馬名日 ON dbo.スピード指数(馬名,開催日);
"@
    $cmd=$conn.CreateCommand(); $cmd.CommandText=$ddl; [void]$cmd.ExecuteNonQuery()

    # --- データ取得(全着順馬・時計あり・芝ダのみ) ---
    $sql = @"
SELECT k.開催場所 v, k.開催日 d, k.レース番号 r, k.馬番 no, k.馬名 horse, k.着順 fin,
       k.走破時計 t, ri.距離 dist, ri.コース種別 surf, ri.馬場 cond, ri.一着賞金 cls
FROM 競走結果 k
JOIN レース情報 ri ON ri.開催場所=k.開催場所 AND ri.開催日=k.開催日 AND ri.レース番号=k.レース番号 AND ri.馬番=k.馬番
WHERE k.走破時計>0 AND ri.距離>0 AND ri.コース種別 IN (N'芝',N'ダ')
  AND k.開催日>=@from AND k.開催日<@to
ORDER BY k.開催日,k.開催場所,k.レース番号,k.馬番;
"@
    $cmd=$conn.CreateCommand(); $cmd.CommandTimeout=180; $cmd.CommandText=$sql
    [void]$cmd.Parameters.AddWithValue('@from',$From)
    [void]$cmd.Parameters.AddWithValue('@to',$To)
    $r=$cmd.ExecuteReader()
    $rows = New-Object System.Collections.Generic.List[object]
    while ($r.Read()) {
        $rows.Add([PSCustomObject]@{
            v=$r['v']; d=[datetime]$r['d']; r=[int]$r['r']; no=[int]$r['no']; horse=[string]$r['horse']; fin=[int]$r['fin']
            t=[double]$r['t']; dist=[int]$r['dist']; surf=[string]$r['surf']; cond=[string]$r['cond']; cls=[double]$r['cls']
            corr=$null; sf=$null
        })
    }
    $r.Close()
    Write-Host ("取得 {0} 行  期間 {1}〜{2}" -f $rows.Count,$From,$To)
    if ($rows.Count -eq 0) { return }

    # 1) 妥当速度域フィルタ
    $valid = $rows | Where-Object { $_.t -ge $_.dist/18.0 -and $_.t -le $_.dist/11.0 }
    # 2) (コース種別×距離) 中央値 ±12% 再フィルタ
    $distMed=@{}
    foreach($g in ($valid | Group-Object {"$($_.surf)|$($_.dist)"})){ $distMed[$g.Name]=Median([double[]]($g.Group.t)) }
    $clean = $valid | Where-Object { $m=$distMed["$($_.surf)|$($_.dist)"]; $_.t -ge $m*0.88 -and $_.t -le $m*1.12 }
    Write-Host ("妥当 {0} 行 / 除外 {1} 行" -f $clean.Count, ($rows.Count-$clean.Count))

    # 3) 期待タイム cell=(コース種別×距離×クラス)勝ち時計平均, n<8 は (コース種別×距離)中央値
    $winners = $clean | Where-Object { $_.fin -eq 1 }
    $cell=@{}
    foreach($g in ($winners | Group-Object {"$($_.surf)|$($_.dist)|$($_.cls)"})){
        $cell[$g.Name]=[PSCustomObject]@{ n=$g.Count; mean=($g.Group.t|Measure-Object -Average).Average }
    }
    function ExpTime($x){
        $k="$($x.surf)|$($x.dist)|$($x.cls)"
        if ($cell.ContainsKey($k) -and $cell[$k].n -ge 8) { return $cell[$k].mean }
        return $distMed["$($x.surf)|$($x.dist)"]
    }

    # 4) δ = (日×場×コース種別) の勝ち時計偏差の中央値
    $delta=@{}
    foreach($g in ($winners | Group-Object {"$($_.d.ToString('yyyyMMdd'))|$($_.v)|$($_.surf)"})){
        $devs = [double[]]($g.Group | ForEach-Object { $_.t - (ExpTime $_) })
        $delta[$g.Name]=Median($devs)
    }
    function DeltaOf($x){
        $k="$($x.d.ToString('yyyyMMdd'))|$($x.v)|$($x.surf)"
        if ($delta.ContainsKey($k)) { return $delta[$k] } else { return 0.0 }
    }

    # 5) 補正後タイム(全 clean 馬)
    foreach($x in $clean){ $x.corr = $x.t - (DeltaOf $x) }

    # 6) SF = 50 - 10z  ((コース種別×距離)内で補正後タイム標準化)
    foreach($g in ($clean | Group-Object {"$($_.surf)|$($_.dist)"})){
        $arr=[double[]]($g.Group.corr); $mean=($arr|Measure-Object -Average).Average; $sd=Stdev $arr
        if ($sd -le 0) { $sd = 1.0 }
        foreach($x in $g.Group){ $x.sf = [math]::Round(50 - 10*(($x.corr-$mean)/$sd),2) }
    }

    # --- 検証: 同一(コース種別×距離×クラス)勝ち時計SD 補正前→後 ---
    $rawSds=@();$adjSds=@();$wts=@()
    foreach($g in ($winners | Group-Object {"$($_.surf)|$($_.dist)|$($_.cls)"})){
        if ($g.Count -lt 10) { continue }
        $raw=[double[]]($g.Group.t)
        $adj=[double[]]($g.Group | ForEach-Object { $_.t - (DeltaOf $_) })
        $rawSds+=(Stdev $raw); $adjSds+=(Stdev $adj); $wts+=$g.Count
    }
    if ($wts.Count -gt 0) {
        $wsum=($wts|Measure-Object -Sum).Sum; $rawW=0.0;$adjW=0.0
        for($i=0;$i -lt $wts.Count;$i++){ $rawW+=$rawSds[$i]*$wts[$i]; $adjW+=$adjSds[$i]*$wts[$i] }
        $rawW/=$wsum; $adjW/=$wsum
        Write-Host ("`n■ 検証: 同一(コース種別×距離×クラス) {0}種・勝ち時計 加重平均SD" -f $wts.Count)
        Write-Host ("  補正前 {0:F3}s → 補正後 {1:F3}s  (縮小 {2:P1})" -f $rawW,$adjW,(($rawW-$adjW)/$rawW))
    }
    $dv=[double[]]($delta.Values); $sd2=$dv|Sort-Object
    Write-Host ("■ δ分布(日×場×コース種別 {0}群): 最速 {1:F2} / 中央 {2:F2} / 最重 {3:F2} / レンジ {4:F2}s" -f `
        $delta.Count,$sd2[0],(Median $dv),$sd2[-1],($sd2[-1]-$sd2[0]))

    # --- スピード指数テーブルへ書き出し(対象期間を全置換) ---
    $del=$conn.CreateCommand(); $del.CommandText="DELETE FROM dbo.スピード指数 WHERE 開催日>=@from AND 開催日<@to"
    [void]$del.Parameters.AddWithValue('@from',$From); [void]$del.Parameters.AddWithValue('@to',$To)
    [void]$del.ExecuteNonQuery()

    $dt=New-Object System.Data.DataTable
    '開催場所','開催日','レース番号','馬番','馬名','着順','距離','コース種別','馬場','生時計','馬場差','補正時計','SF' | ForEach-Object { [void]$dt.Columns.Add($_) }
    foreach($x in $clean){
        [void]$dt.Rows.Add($x.v,$x.d,$x.r,$x.no,$x.horse,$x.fin,$x.dist,$x.surf,$x.cond,$x.t,(DeltaOf $x),$x.corr,$x.sf)
    }
    $bulk=New-Object System.Data.SqlClient.SqlBulkCopy($conn)
    $bulk.DestinationTableName='dbo.スピード指数'; $bulk.BatchSize=5000; $bulk.BulkCopyTimeout=180
    foreach($c in $dt.Columns){ [void]$bulk.ColumnMappings.Add($c.ColumnName,$c.ColumnName) }
    $bulk.WriteToServer($dt)
    Write-Host ("`n✓ スピード指数 へ {0} 行書き込み完了" -f $dt.Rows.Count)
}
finally { $conn.Close() }
