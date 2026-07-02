<#
.SYNOPSIS
  IPAT投票履歴の精算: 結果='投票完了' かつ 確定済=0 の投票を、払戻金(当選組番×金額)と突合して 払戻金額・確定済 を更新する。
  /history の的中/払戻・status.ps1 の確定収支・jra-card 等に結果を反映させる土台。読み取り→該当行のみUPDATE。
.DESCRIPTION
  払戻金テーブル(馬券=式別・組番・金額[100円当たり])が当選の真実。各投票の買い目(軸/相手→組合せ)を式別ごとに列挙し、
  当選組番に一致した点の払戻(金額/100×一点金額)を合算→払戻金額。払戻金が存在するレースのみ精算(=結果確定済)。
  順不同(複勝/単勝/ワイド/馬連/枠連/三連複)=数字昇順で一致。順序(馬単/三連単)=組の順列いずれか一致(マルチ含む)。
.PARAMETER Date  対象日(yyyy-MM-dd)。既定=未指定なら未確定の全日。
.PARAMETER DryRun  更新せず精算結果(件数/的中/払戻)のみ表示。
.OUTPUTS  SETTLED|<確定件数>|HIT|<的中件数>|PAY|<払戻合計>
#>
[CmdletBinding()]
param([string]$Date='',[switch]$DryRun)
$ErrorActionPreference='Stop'
try{ [Console]::OutputEncoding=[Text.Encoding]::UTF8 }catch{}
$cs=(Get-Content 'C:\jra\共通\appsettings.json' -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
$cn=New-Object System.Data.SqlClient.SqlConnection $cs; $cn.Open()
function Q([string]$sql,[hashtable]$p){ $c=$cn.CreateCommand();$c.CommandText=$sql; if($p){foreach($k in $p.Keys){[void]$c.Parameters.AddWithValue($k,$p[$k])}}; $dt=New-Object System.Data.DataTable;(New-Object System.Data.SqlClient.SqlDataAdapter $c).Fill($dt)|Out-Null; ,$dt.Rows }
function Nums([string]$s){ @([regex]::Matches("$s",'\d+')|ForEach-Object{[int]$_.Value}) }
function Perms($a){ if($a.Count -le 1){return ,@($a)}; $res=@(); for($i=0;$i -lt $a.Count;$i++){ $rest=@($a[0..($a.Count-1)]|Where-Object{$true}); $rest=@(); for($j=0;$j -lt $a.Count;$j++){ if($j -ne $i){$rest+=$a[$j]} }; foreach($p in (Perms $rest)){ $res+=,(@($a[$i])+$p) } }; ,$res }

# 未確定(確定済=0) 全行を精算。実投票(結果=投票完了)はそのまま収支へ、計画(DryRun)/見送りはペーパー評価として確定済化(下流の収支は結果=投票完了で絞る)。
$dateF= if($Date){ " AND 開催日=@d" }else{ "" }
$pp= if($Date){ @{'@d'=$Date} }else{ @{} }
$votes=Q ("SELECT Id,開催日,開催場所,レース番号,式別,方式,軸馬番,相手馬番,組番,点数,一点金額,投票金額,結果 FROM dbo.IPAT投票履歴 WHERE 確定済=0" + $dateF) $pp
Write-Output ("未確定行: {0}件(実投票=結果『投票完了』/ それ以外=計画・見送り)" -f @($votes).Count)
if(@($votes).Count -eq 0){ $cn.Close(); Write-Output 'SETTLED|0|HIT|0|PAY|0'; return }

# 払戻金キャッシュ: (場|日|R) -> 式別 -> @{ normKey -> 金額per100 ; rawKeys=順序キー集合 }
$payCache=@{}
function LoadPay($v,$d,$r){
  $k="$v|$d|$r"; if($payCache.ContainsKey($k)){ return $payCache[$k] }
  $m=@{}
  foreach($x in (Q "SELECT 馬券 bt,組番 kb,TRY_CAST(金額 AS int) kin FROM dbo.払戻金 WHERE 開催場所=@v AND 開催日=@d AND レース番号=@r" @{'@v'=$v;'@d'=$d;'@r'=$r})){
    $bt=[string]$x.bt; if(-not $m.ContainsKey($bt)){ $m[$bt]=@{norm=@{};ord=@{}} }
    $ns=Nums $x.kb; if($ns.Count -eq 0){ continue }
    $m[$bt].norm[(($ns|Sort-Object) -join '-')]=[int]$x.kin   # 順不同
    $m[$bt].ord[($ns -join '-')]=[int]$x.kin                  # 順序(馬単/三連単)
  }
  $payCache[$k]=$m; return $m
}

$ordered=@('馬単','三連単')
$settled=0; $hitN=0; $payTotal=0
$realN=0; $realHit=0; $realPay=0   # 実投票(結果=投票完了)のみの集計
$ups=@()
foreach($vt in $votes){
  $v=[string]$vt.開催場所; $d=([datetime]$vt.開催日).ToString('yyyy-MM-dd'); $r=[int]$vt.レース番号
  $pay=LoadPay $v $d $r
  if($pay.Keys.Count -eq 0){ continue }   # 払戻金なし=結果未確定→精算しない
  $bt=[string]$vt.式別; $hoshiki=[string]$vt.方式; $unit=[int]$vt.一点金額; if($unit -le 0){ $unit=[int]$vt.投票金額 }
  $axis=(Nums $vt.軸馬番); $part=(Nums $vt.相手馬番); $kb=(Nums $vt.組番)
  $ax= if($axis.Count){$axis[0]}else{0}
  $multi = ($hoshiki -match 'マルチ')
  $isOrd = ($bt -in $ordered)
  # 式別→組合せ列挙(各組=馬番配列)。順序系(馬単/三連単)は軸1着固定で順序保持、マルチは全順列。
  $combos=@()
  switch -Regex ($bt){
    '単勝|複勝' { if($ax){$combos+=,@($ax)} }
    'ワイド|馬連|枠連' { foreach($p in $part){ if($ax -and $p -ne $ax){ $combos+=,@($ax,$p) } } ; if($combos.Count -eq 0 -and $kb.Count -ge 2){ $combos+=,$kb } }
    '三連複' { for($i=0;$i -lt $part.Count;$i++){ for($j=$i+1;$j -lt $part.Count;$j++){ if($ax){ $combos+=,@($ax,$part[$i],$part[$j]) } } } ; if($combos.Count -eq 0 -and $kb.Count -ge 3){ $combos+=,$kb } }
    '三連単' { for($i=0;$i -lt $part.Count;$i++){ for($j=$i+1;$j -lt $part.Count;$j++){ if($ax){ $t=@($ax,$part[$i],$part[$j]); if($multi){ foreach($pm in (Perms $t)){$combos+=,$pm} }else{ $combos+=,@($ax,$part[$i],$part[$j]); $combos+=,@($ax,$part[$j],$part[$i]) } } } } ; if($combos.Count -eq 0 -and $kb.Count -ge 3){ $combos+=,$kb } }
    '馬単' { foreach($p in $part){ if($ax -and $p -ne $ax){ if($multi){ $combos+=,@($ax,$p); $combos+=,@($p,$ax) }else{ $combos+=,@($ax,$p) } } } ; if($combos.Count -eq 0 -and $kb.Count -ge 2){ $combos+=,$kb } }
    default { if($kb.Count){$combos+=,$kb} }
  }
  $payThis=0
  $pm = if($pay.ContainsKey($bt)){$pay[$bt]}else{$null}
  if($pm){
    foreach($combo in $combos){
      if($isOrd){
        $key=($combo -join '-'); if($pm.ord.ContainsKey($key)){ $payThis += [int]($pm.ord[$key]*$unit/100) }
      }else{
        $key=(($combo|Sort-Object) -join '-'); if($pm.norm.ContainsKey($key)){ $payThis += [int]($pm.norm[$key]*$unit/100) }
      }
    }
  }
  $settled++; if($payThis -gt 0){ $hitN++; $payTotal+=$payThis }
  if([string]$vt.結果 -eq '投票完了'){ $realN++; if($payThis -gt 0){ $realHit++; $realPay+=$payThis } }
  $ups+=[pscustomobject]@{ Id=[long]$vt.Id; pay=$payThis }
}
Write-Output ("精算(払戻金あり): 全{0}件 的中{1} 払戻{2:N0}円 / 実投票{3}件 的中{4} 払戻{5:N0}円" -f $settled,$hitN,$payTotal,$realN,$realHit,$realPay)
if(-not $DryRun){
  foreach($u in $ups){ $c=$cn.CreateCommand(); $c.CommandText="UPDATE dbo.IPAT投票履歴 SET 確定済=1,払戻金額=@p WHERE Id=@id"; [void]$c.Parameters.AddWithValue('@p',$u.pay);[void]$c.Parameters.AddWithValue('@id',$u.Id); [void]$c.ExecuteNonQuery() }
  Write-Output ("  → {0}件を確定済=1で更新" -f $ups.Count)
}
$cn.Close()
Write-Output ("SETTLED|{0}|HIT|{1}|PAY|{2}|REALHIT|{3}|REALPAY|{4}" -f $settled,$hitN,$payTotal,$realHit,$realPay)
