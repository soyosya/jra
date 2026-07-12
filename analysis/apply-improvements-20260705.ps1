# 2026-07-05 買目・改善ロジック後処理（リバーシブル・jra-cardコア非改変）
# 2025+2026後追いの改善点を jra-cardキャッシュ出力に適用して買目を再作成する。
# 改善: (A)ネガ除外フロア (B)コンピ1-2位フロア (C)相手拡幅>=5 (D)警戒のみ格上げ軸→好シグナルのコンピ1位へ (E)重賞/混戦/軸複勝フラグ
param([string]$Date='2026-07-05')
$ymd = $Date -replace '-',''
$cs=(Get-Content 'C:\jra\共通\appsettings.json' -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
$cn=New-Object System.Data.SqlClient.SqlConnection $cs;$cn.Open()
function Q($sql){ $c=$cn.CreateCommand();$c.CommandText=$sql;$dt=New-Object System.Data.DataTable;[void](New-Object System.Data.SqlClient.SqlDataAdapter $c).Fill($dt);,$dt }
$posRe='★|完|連好|連脚|連上|適|↗|⚡'
$warnRe='▽不調|▽相悪|▽前敗|▽種替|▽長休|▽休|▽増|▽失速|▽延|▽後|弱|注危|危'
$negRe='△(不調|相悪|前敗|種替|長休|休|危|不適)'
$gradeRe='Ｇ[０-９]|ステークス|記念|カップ|ジュライ|大沼|北九州'

foreach($v in '函館','福島','小倉'){
  $f="C:\temp\jra_reason_${ymd}_${v}.json"
  if(-not(Test-Path $f)){ continue }
  $j=Get-Content $f -Raw -Encoding UTF8|ConvertFrom-Json
  # 補助DB
  $co=@{}; foreach($x in (Q "SELECT レース番号 R,馬番,指数順位 rk,指数 idx FROM dbo.コンピ指数 WHERE 開催日='$Date' AND 開催場所=N'$v'").Rows){ $co["$($x.R)_$($x.馬番)"]=@{rk=[int]$x.rk;idx=[int]$x.idx} }
  $nin=@{}; foreach($x in (Q "WITH l AS(SELECT レース番号,MAX(日時) mx FROM dbo.リアルタイムオッズ WHERE 開催日='$Date' AND 開催場所=N'$v' GROUP BY レース番号) SELECT o.レース番号 R,o.馬番,o.人気 FROM dbo.リアルタイムオッズ o JOIN l ON l.レース番号=o.レース番号 AND l.mx=o.日時 WHERE o.開催日='$Date' AND o.開催場所=N'$v'").Rows){ if("$($x.人気)" -ne '' -and [int]$x.人気 -gt 0){ $nin["$($x.R)_$($x.馬番)"]=[int]$x.人気 } }
  $ck=@{}; foreach($x in (Q "SELECT レース番号 R,馬番,矢印 FROM dbo.調教 WHERE 開催日='$Date' AND 開催場所=N'$v'").Rows){ $ck["$($x.R)_$($x.馬番)"]="$($x.矢印)" }
  $ri=@{}; foreach($x in (Q "SELECT レース番号 R,MAX(距離) kyo,MAX(コース種別) syu,COUNT(*) n,MAX(条件) joken,MAX(競走名) nm FROM dbo.レース情報 WHERE 開催日='$Date' AND 開催場所=N'$v' GROUP BY レース番号").Rows){ $ri["$($x.R)"]=@{kyo=$x.kyo;syu=$x.syu;n=[int]$x.n;joken=$x.joken;nm=$x.nm} }
  $done=@{}; foreach($x in (Q "SELECT DISTINCT レース番号 R FROM dbo.競走結果 WHERE 開催日='$Date' AND 開催場所=N'$v'").Rows){ $done["$($x.R)"]=$true }

  Write-Host "########## $v ##########"
  foreach($r in ($j.PSObject.Properties.Name | Sort-Object {[int]$_})){
    $rr=$j.$r; $inf=$ri["$r"]
    if($inf.joken -match '障'){ "  ${r}R [障害＝モデル対象外・見送り]"; continue }
    $H=$rr.horses; $ax="$($rr.axis)"; $axLab="$($rr.axisLab)"
    if($ax -eq ''){ "  ${r}R [jra-card欠測・スキップ]"; continue }
    # ヘルパ: uma-> compi/sougou/eval/ninki/arrow
    $umas=@($H.PSObject.Properties.Name)
    function C1of{ ($umas | Where-Object { $co["${r}_$_"].rk -eq 1 } | Select-Object -First 1) }
    $c1=C1of
    $axCompi=[int]$co["${r}_$ax"].rk; $axSou=[double]$H.$ax.sougou
    # (D) 軸差替: 警戒のみ格上げ軸(コ2+) → 好シグナルのコンピ1位(総合が軸以上)
    $newAx=$ax; $switch=''
    $axNoPos = ($axLab -notmatch $posRe)
    $axWarn  = ($axLab -match $warnRe)
    if($axNoPos -and $axWarn -and $axCompi -ge 2 -and $c1 -and $c1 -ne $ax){
      $c1eval="$($H.$c1.eval)"; $c1sou=[double]$H.$c1.sougou
      if(($c1eval -match $posRe) -and ($c1eval -notmatch $negRe) -and ($c1sou -ge $axSou)){
        $newAx=$c1; $switch="→軸差替(警戒のみ格上げ→好シグナルのコンピ1位 ${c1})"
      }
    }
    # (A)(B)(C) 相手構築
    $rel=New-Object System.Collections.Generic.List[string]
    foreach($p in ($rr.partners -split ',')){ if($p -ne '' -and $p -ne $newAx){ [void]$rel.Add($p) } }
    # フロア: 非軸で compi<=3 or 総合>=0.6 or 1番人気
    foreach($u in $umas){
      if($u -eq $newAx){ continue }
      $uc=[int]$co["${r}_$u"].rk; $us=[double]$H.$u.sougou; $un=$nin["${r}_$u"]
      if($uc -le 3 -or $us -ge 0.6 -or $un -eq 1){ if(-not $rel.Contains($u)){ [void]$rel.Add($u) } }
    }
    # (E)重賞: 調教↗の中位コンピ(4-9位)を1頭追加
    $isG = ($inf.nm -match $gradeRe) -or ($inf.joken -match 'オープン')
    if($isG){
      $add=$umas | Where-Object { $_ -ne $newAx -and $ck["${r}_$_"] -match '↗' -and $co["${r}_$_"].rk -ge 4 -and $co["${r}_$_"].rk -le 9 } | Sort-Object { $co["${r}_$_"].rk } | Select-Object -First 1
      if($add -and -not $rel.Contains($add)){ [void]$rel.Add($add) }
    }
    # (C)拡幅 >=5 (or 頭数-1): 総合desc→compi ascで補充
    $cap=[Math]::Min(6,$inf.n-1)
    $need=[Math]::Max(5,0)
    if($rel.Count -lt $need){
      $cand=$umas | Where-Object { $_ -ne $newAx -and -not $rel.Contains($_) } | Sort-Object { -[double]$H.$_.sougou },{ $co["${r}_$_"].rk }
      foreach($cc in $cand){ if($rel.Count -ge $need){break}; [void]$rel.Add($cc) }
    }
    # 相手をコンピ順に整列＋cap
    $relS=$rel | Sort-Object { $co["${r}_$_"].rk } | Select-Object -First $cap
    # 混戦(指数分散): 上位8頭SD
    $idxs=($umas | ForEach-Object { $co["${r}_$_"].idx } | Sort-Object -Descending | Select-Object -First 8)
    $m=($idxs|Measure-Object -Average).Average; $sd=[Math]::Sqrt((($idxs|ForEach-Object{($_-$m)*($_-$m)}|Measure-Object -Sum).Sum)/$idxs.Count)
    $flag=@()
    if($switch){ $flag+=$switch }
    if($isG){ $flag+='[重賞:市場人気/調教↗重視・↗中位1頭追加]' }
    if($sd -lt 8){ $flag+=("[混戦(指数SD{0:N1})＝軸複勝中心/三連系抑制]" -f $sd) }
    $st = if($done["$r"]){'※確定済'}else{'●発売中'}
    $newAxLab = if($newAx -eq $ax){$axLab}else{"（旧軸${ax}:${axLab}）"}
    "  {0,2}R {1} {2}{3} {4}頭｜◎{5} {6}｜相手:{7}｜軸複勝◎{5}常時" -f $r,$st,$inf.kyo,$inf.syu,$inf.n,$newAx,$newAxLab,($relS -join ',')
    if($flag){ "        "+($flag -join ' ') }
  }
}
$cn.Close()