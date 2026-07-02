<#
  昨日(既定06-27)の買目を 軸足切りあり(現状) vs なし(-NoAxisCap=旧) で再検証。
  各レースの軸/相手(EXPORT)を両モードで取得→着順と突合→軸top3率・ワイド的中率を比較。足切りで差替った軸の成否を明示。
#>
param([string]$Date='2026-06-27')
$ErrorActionPreference='Continue'
try{ [Console]::OutputEncoding=[Text.Encoding]::UTF8 }catch{}
$cs=(Get-Content 'C:\jra\共通\appsettings.json' -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
$cn=New-Object System.Data.SqlClient.SqlConnection $cs;$cn.Open();$c=$cn.CreateCommand()
function Q($sql,$p){ $c.CommandText=$sql;$c.Parameters.Clear();foreach($k in $p.Keys){[void]$c.Parameters.AddWithValue($k,$p[$k])};$dt=New-Object System.Data.DataTable;(New-Object System.Data.SqlClient.SqlDataAdapter $c).Fill($dt)|Out-Null;,$dt.Rows }
$vrows=Q "SELECT DISTINCT 開催場所 v FROM dbo.レース情報 WHERE 開催日=@d" @{'@d'=$Date}
$venues=@(); foreach($vr in $vrows){ $venues+=[string]$vr.v }
Write-Output ("対象会場: " + ($venues -join ' / '))
# 着順・コンピ順位 lookup
$chaku=@{}; foreach($x in (Q "SELECT 開催場所 v,レース番号 r,馬番 no,TRY_CONVERT(int,着順) ch FROM dbo.競走結果 WHERE 開催日=@d" @{'@d'=$Date})){ if($x.ch -isnot [DBNull]){ $chaku["$($x.v)|$($x.r)|$([int]$x.no)"]=[int]$x.ch } }
$crk=@{}; foreach($x in (Q "SELECT 開催場所 v,レース番号 r,馬番 no,指数順位 rk FROM (SELECT 開催場所,レース番号,馬番,指数順位,ROW_NUMBER() OVER(PARTITION BY 開催場所,レース番号,馬番 ORDER BY 取得日時 DESC) sn FROM dbo.コンピ指数 WHERE 開催日=@d) t WHERE sn=1" @{'@d'=$Date})){ $crk["$($x.v)|$($x.r)|$([int]$x.no)"]=[int]$x.rk }
$cn.Close()
function Ch($v,$r,$no){ $k="$v|$r|$no"; if($chaku.ContainsKey($k)){$chaku[$k]}else{99} }
function Rk($v,$r,$no){ $k="$v|$r|$no"; if($crk.ContainsKey($k)){$crk[$k]}else{0} }
function GetBets($v,$nocap){
  $h=@{Date=$Date; Venue=$v; ExportBets=$true; ExportN=5}; if($nocap){ $h.NoAxisCap=$true }
  $out=@(& 'C:\jra\tools\jra-card.ps1' @h 2>$null)
  $b=@{}
  foreach($l in $out){ if("$l" -match '^EXPORT\|'){ $f="$l" -split '\|'; if($f.Count -ge 6){ $r=[int]$f[1]; $ax=[int]([regex]::Match($f[3],'\d+').Value); $pt=@([regex]::Matches($f[5],'\d+')|ForEach-Object{[int]$_.Value}); $b[$r]=@{ax=$ax;pt=$pt;ev=$f[4]} } } }
  $b
}
$capTop=0;$nocapTop=0;$capWide=0;$nocapWide=0;$nR=0;$changed=@()
foreach($v in $venues){
  $cap=GetBets $v $false; $nc=GetBets $v $true
  foreach($r in ($cap.Keys | Sort-Object)){
    $nR++
    $axC=$cap[$r].ax; $axN= if($nc.ContainsKey($r)){$nc[$r].ax}else{$axC}
    $chC=Ch $v $r $axC; $chN=Ch $v $r $axN
    if($chC -le 3){$capTop++}; if($chN -le 3){$nocapTop++}
    # ワイド的中=軸top3 かつ 相手(先頭3)のどれかtop3
    $pt3C=@($cap[$r].pt | Select-Object -First 3); $wC=($chC -le 3 -and @($pt3C|Where-Object{(Ch $v $r $_) -le 3}).Count -ge 1)
    $pt3N= if($nc.ContainsKey($r)){@($nc[$r].pt|Select-Object -First 3)}else{$pt3C}; $wN=($chN -le 3 -and @($pt3N|Where-Object{(Ch $v $r $_) -le 3}).Count -ge 1)
    if($wC){$capWide++}; if($wN){$nocapWide++}
    if($axC -ne $axN){ $changed+=("  {0}{1,2}R 足切: 軸{2}(コ{3})着{4} {5}  ←旧 軸{6}(コ{7})着{8} {9}" -f $v,$r,$axC,(Rk $v $r $axC),$chC,$(if($chC -le 3){'○'}else{'×'}),$axN,(Rk $v $r $axN),$chN,$(if($chN -le 3){'○'}else{'×'})) }
  }
}
function Pc($a,$b){ if($b){'{0:P1}' -f ($a/$b)}else{'—'} }
Write-Output ("===== 昨日($Date)買目 再検証: 軸足切りあり(現) vs なし(旧) 全${nR}レース =====")
Write-Output ("軸top3率:  足切あり {0} ({1}/{2})  /  足切なし {3} ({4}/{5})" -f (Pc $capTop $nR),$capTop,$nR,(Pc $nocapTop $nR),$nocapTop,$nR)
Write-Output ("ワイド的中: 足切あり {0} ({1}/{2})  /  足切なし {3} ({4}/{5})" -f (Pc $capWide $nR),$capWide,$nR,(Pc $nocapWide $nR),$nocapWide,$nR)
Write-Output "--- 足切で軸が差替ったレース(○=top3的中/×=圏外) ---"
$changed | ForEach-Object { Write-Output $_ }
