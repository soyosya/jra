<#
.SYNOPSIS
  +EV判定: 較正済みモデル勝率 vs 市場(単勝オッズ)を比較し、妙味(+EV)が実在するか検証。
.DESCRIPTION
  予測 テーブル(p_win)× 特徴量(単勝オッズ,人気,win)を H2検証(test split)で評価。
  - EV倍率 = p_win × 単勝オッズ。1.0超ならモデル基準で+EV(¥100単勝の期待値プラス)。
  - 市場含意勝率 q = (1/odds) を レース内で正規化(控除を除いた相対確率)。
  - 検証1: EV倍率バケット別の実回収率(モデルEVが実回収を予測するか=単調性)。
  - 検証2: 閾値戦略(EV倍率>=t)の単勝回収率・的中率・点数。
  - 検証3: モデル本命を機械的に単勝する軸戦略の回収率。
  すべて H2(2023後半=モデルが見ていない)で評価。
#>
[CmdletBinding()] param()
$ErrorActionPreference='Stop'
$connStr=(Get-Content 'C:\jra\共通\appsettings.json' -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
$conn=New-Object System.Data.SqlClient.SqlConnection($connStr); $conn.Open()
$sql=@"
SELECT f.開催場所,f.開催日,f.レース番号,f.馬番,p.p_win,f.tan_odds odds,f.ninki,f.win,f.頭数
FROM 予測 p
JOIN 特徴量 f ON f.開催場所=p.開催場所 AND f.開催日=p.開催日 AND f.レース番号=p.レース番号 AND f.馬番=p.馬番
WHERE p.split='test' AND f.tan_odds IS NOT NULL AND f.tan_odds>0
"@
$cmd=$conn.CreateCommand();$cmd.CommandTimeout=120;$cmd.CommandText=$sql
$r=$cmd.ExecuteReader()
$rows=New-Object System.Collections.Generic.List[object]
while($r.Read()){
  $rows.Add([PSCustomObject]@{
    v=$r['開催場所'];d=[datetime]$r['開催日'];rno=[int]$r['レース番号'];no=[int]$r['馬番']
    p=[double]$r['p_win'];odds=[double]$r['odds'];nin=$(if($r['ninki'] -is [DBNull]){0}else{[int]$r['ninki']});win=[int]$r['win']
    ev=0.0
  })
}
$r.Close();$conn.Close()
foreach($x in $rows){ $x.ev=$x.p*$x.odds }
Write-Host ("H2検証 {0} 頭  ({1} レース)" -f $rows.Count, (($rows|Group-Object {"$($_.v)|$($_.d.ToString('yyyyMMdd'))|$($_.rno)"}).Count))

function ROI($bets){
  if($bets.Count -eq 0){return [PSCustomObject]@{n=0;hit=0;roi=0;hitrate=0}}
  $ret=0.0;$hit=0
  foreach($b in $bets){ if($b.win -eq 1){ $ret+=$b.odds*100; $hit++ } }
  [PSCustomObject]@{n=$bets.Count;hit=$hit;roi=$ret/(100*$bets.Count);hitrate=[double]$hit/$bets.Count}
}

# 検証1: EV倍率バケット別の実単勝回収率
"`n■ 検証1: EV倍率バケット別 実単勝回収率(単調なら=モデルEVが妙味を捉える)"
"{0,-12} {1,7} {2,8} {3,9}" -f 'EV倍率','n','的中率','回収率'
$buckets=@(
 @{name='<0.5';lo=-99;hi=0.5},@{name='0.5-0.8';lo=0.5;hi=0.8},@{name='0.8-1.0';lo=0.8;hi=1.0},
 @{name='1.0-1.2';lo=1.0;hi=1.2},@{name='1.2-1.5';lo=1.2;hi=1.5},@{name='1.5-2.0';lo=1.5;hi=2.0},@{name='2.0+';lo=2.0;hi=999})
foreach($bk in $buckets){
  $g=$rows|Where-Object{$_.ev -ge $bk.lo -and $_.ev -lt $bk.hi}
  $s=ROI $g
  "{0,-12} {1,7} {2,8:P1} {3,9:P1}" -f $bk.name,$s.n,$s.hitrate,$s.roi
}

# 検証2: 閾値戦略(全馬からEV倍率>=t を単勝)
"`n■ 検証2: 閾値戦略(EV倍率>=t の全馬を単勝, H2)"
"{0,-8} {1,7} {2,8} {3,9}" -f '閾値t','点数','的中率','回収率'
foreach($t in 1.0,1.1,1.2,1.3,1.5){
  $s=ROI ($rows|Where-Object{$_.ev -ge $t})
  "{0,-8} {1,7} {2,8:P1} {3,9:P1}" -f $t,$s.n,$s.hitrate,$s.roi
}

# 検証3: モデル本命の単勝(軸戦略) vs 1番人気の単勝
"`n■ 検証3: 各レース最上位を機械的に単勝(H2)"
$byrace=$rows|Group-Object {"$($_.v)|$($_.d.ToString('yyyyMMdd'))|$($_.rno)"}
$modelTop=foreach($g in $byrace){ $g.Group|Sort-Object {-$_.p}|Select-Object -First 1 }
$ninTop  =foreach($g in $byrace){ $g.Group|Where-Object{$_.nin -gt 0}|Sort-Object nin|Select-Object -First 1 }
$mt=ROI $modelTop; $nt=ROI $ninTop
"  モデル本命単勝 : 的中 {0:P1}  回収 {1:P1}  ({2}点)" -f $mt.hitrate,$mt.roi,$mt.n
"  1番人気単勝    : 的中 {0:P1}  回収 {1:P1}  ({2}点)" -f $nt.hitrate,$nt.roi,$nt.n

# 検証3b: モデル本命のうち EV>=1 に絞った軸単勝(妙味のある本命だけ買う)
$modelTopEv=$modelTop|Where-Object{$_.ev -ge 1.0}
$me=ROI $modelTopEv
"  └ うちEV>=1のみ : 的中 {0:P1}  回収 {1:P1}  ({2}点 / 全{3}レース中)" -f $me.hitrate,$me.roi,$me.n,$mt.n
