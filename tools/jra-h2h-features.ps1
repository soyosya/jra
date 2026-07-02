<#
.SYNOPSIS
  h2h(共通対戦相手・着差連鎖)スコアを全2023レースで一括計算し 特徴量.h2h / n_h2h を更新。
.DESCRIPTION
  race-h2h.ps1 のロジック(直接対決→同レース共通相手→近走共通相手、勝ち時計比%で正規化)を
  メモリ一括版に。全結果を1度ロードし、各2023レースの各馬について出走前(<当日・183日内・直近5走)の
  情報のみで h2h スコア(=出走全馬への推定着差平均, +が速い)を算出=リーク無し。
#>
[CmdletBinding()] param([int]$Year=2023,[int]$RecentN=5,[int]$RecentDays=183)
$ErrorActionPreference='Stop'
$connStr=(Get-Content 'C:\jra\共通\appsettings.json' -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
$conn=New-Object System.Data.SqlClient.SqlConnection($connStr);$conn.Open()

# 全結果ロード
$cmd=$conn.CreateCommand();$cmd.CommandTimeout=180
$cmd.CommandText="SELECT 開催場所,開催日,レース番号,馬番,馬名,走破時計,着順 FROM 競走結果 WHERE 走破時計>0 AND 着順>0"
$r=$cmd.ExecuteReader()
$raceRows=@{}; $raceWin=@{}; $horseRaces=@{}; $raceField=@{}
while($r.Read()){
  $v=[string]$r['開催場所']; $d=[datetime]$r['開催日']; $rno=[int]$r['レース番号']; $no=[int]$r['馬番']
  $h=[string]$r['馬名']; $t=[double]$r['走破時計']
  $k='{0}|{1}|{2}' -f $v,$d.ToString('yyyy-MM-dd'),$rno
  if(-not $raceRows.ContainsKey($k)){ $raceRows[$k]=@{}; $raceField[$k]=New-Object System.Collections.Generic.List[object] }
  $raceRows[$k][$h]=$t
  $raceField[$k].Add([PSCustomObject]@{no=$no;h=$h;d=$d;v=$v;rno=$rno})
  if(-not $horseRaces.ContainsKey($h)){ $horseRaces[$h]=New-Object System.Collections.Generic.List[object] }
  $horseRaces[$h].Add([PSCustomObject]@{d=$d;k=$k})
}
$r.Close()
foreach($k in $raceRows.Keys){ $raceWin[$k]=($raceRows[$k].Values|Measure-Object -Minimum).Minimum }
foreach($h in @($horseRaces.Keys)){ $horseRaces[$h]=@($horseRaces[$h]|Sort-Object d -Descending) }
Write-Host ("ロード: {0}レース / {1}頭" -f $raceRows.Count,$horseRaces.Count)

# 対象=指定年の全レースキー
$targetKeys=@($raceField.Keys | Where-Object { ([datetime]($_.Split('|')[1])).Year -eq $Year })
Write-Host ("対象 {0}年: {1}レース" -f $Year,$targetKeys.Count)

$out=New-Object System.Collections.Generic.List[object]
$done=0
foreach($tk in $targetKeys){
  $parts=$tk.Split('|'); $tv=$parts[0]; $td=[datetime]$parts[1]; $trno=[int]$parts[2]
  $dmin=$td.AddDays(-$RecentDays)
  $field=@($raceField[$tk] | ForEach-Object { $_.h } | Select-Object -Unique)
  $fieldSet=@{}; $field|ForEach-Object{ $fieldSet[$_]=$true }
  # 各馬の近走margin
  $margin=@{}
  foreach($a in $field){
    $margin[$a]=@{}
    if(-not $horseRaces.ContainsKey($a)){ continue }
    $recent=@($horseRaces[$a] | Where-Object { $_.d -lt $td -and $_.d -ge $dmin } | Select-Object -First $RecentN)
    $cnt=@{}
    foreach($rk in $recent){
      $rr=$raceRows[$rk.k]; if(-not $rr.ContainsKey($a)){ continue }
      $ta=$rr[$a]; $wt=$raceWin[$rk.k]; if(-not $wt){ continue }
      foreach($x in $rr.Keys){
        if($x -eq $a){ continue }
        $rel=($rr[$x]-$ta)/$wt*100.0
        if(-not $margin[$a].ContainsKey($x)){ $margin[$a][$x]=0.0; $cnt[$x]=0 }
        $margin[$a][$x]+=$rel; $cnt[$x]+=1
      }
    }
    foreach($x in @($margin[$a].Keys)){ $margin[$a][$x]=$margin[$a][$x]/$cnt[$x] }
  }
  # ペア推定
  function EstPair($a,$b){
    $vals=@()
    if($margin[$a].ContainsKey($b)){ $vals+=$margin[$a][$b] }
    if($margin[$b].ContainsKey($a)){ $vals+=(-1.0*$margin[$b][$a]) }
    if($vals.Count -gt 0){ return ($vals|Measure-Object -Average).Average }
    $common=@($margin[$a].Keys | Where-Object { $margin[$b].ContainsKey($_) -and $_ -ne $a -and $_ -ne $b })
    if($common.Count -eq 0){ return $null }
    $fc=@($common | Where-Object { $fieldSet.ContainsKey($_) })
    $useC=if($fc.Count -gt 0){$fc}else{$common}
    $est=foreach($c in $useC){ $margin[$a][$c]-$margin[$b][$c] }
    return ($est|Measure-Object -Average).Average
  }
  foreach($ent in $raceField[$tk]){
    $a=$ent.h; $ms=@(); $linked=0
    foreach($b in $field){ if($a -eq $b){continue}; $e=EstPair $a $b; if($null -ne $e){ $ms+=$e; $linked++ } }
    $score=if($ms.Count -gt 0){[math]::Round(($ms|Measure-Object -Average).Average,3)}else{$null}
    $out.Add([PSCustomObject]@{v=$tv;d=$td;rno=$trno;no=$ent.no;h2h=$score;n=$linked})
  }
  $done++; if($done % 300 -eq 0){ Write-Host ("  ...{0}/{1}" -f $done,$targetKeys.Count) }
}
Write-Host ("算出 {0} 頭。書込中..." -f $out.Count)

# ステージング→UPDATE JOIN
$c=$conn.CreateCommand()
$c.CommandText="IF OBJECT_ID('dbo.h2h_stg','U') IS NOT NULL DROP TABLE dbo.h2h_stg; CREATE TABLE dbo.h2h_stg(開催場所 nvarchar(10),開催日 date,レース番号 int,馬番 int,h2h float,n_h2h int);"
[void]$c.ExecuteNonQuery()
$dt=New-Object System.Data.DataTable; '開催場所','開催日','レース番号','馬番','h2h','n_h2h'|ForEach-Object{[void]$dt.Columns.Add($_)}
foreach($x in $out){ [void]$dt.Rows.Add($x.v,$x.d,$x.rno,$x.no,$(if($null -eq $x.h2h){[DBNull]::Value}else{$x.h2h}),$x.n) }
$bulk=New-Object System.Data.SqlClient.SqlBulkCopy($conn);$bulk.DestinationTableName='dbo.h2h_stg';$bulk.BatchSize=5000;$bulk.BulkCopyTimeout=180
foreach($cc in $dt.Columns){[void]$bulk.ColumnMappings.Add($cc.ColumnName,$cc.ColumnName)}
$bulk.WriteToServer($dt)
$c.CommandText="UPDATE f SET f.h2h=s.h2h, f.n_h2h=s.n_h2h FROM dbo.特徴量 f JOIN dbo.h2h_stg s ON s.開催場所=f.開催場所 AND s.開催日=f.開催日 AND s.レース番号=f.レース番号 AND s.馬番=f.馬番; DROP TABLE dbo.h2h_stg;"
$c.CommandTimeout=180; $n=$c.ExecuteNonQuery()
Write-Host ("✓ 特徴量.h2h 更新 {0} 頭" -f $out.Count)
$conn.Close()