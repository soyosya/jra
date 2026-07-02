<#
.SYNOPSIS
  極ウマAI三連複/三連単 推奨買い目の回収率検証(耐ハング: 1レース1行CSV追記・再開可・定期再ログイン)。
.DESCRIPTION
  応答が実結果を自己内包(trp_hb_number=的中3頭, payoff=実払戻)。買い目=sanren配列。
  買い目に的中3頭が含まれれば return=payoff、cost=点数×100。CSV(date,venue,race,year,rank,buy,pts,hit,cost,ret)へ追記。
  -Aggregate でCSVから集計表示のみ(取得なし)。ハングしても部分CSVを集計可。
.PARAMETER Bet puku|tan  .PARAMETER RunType 0=前日/9=直前  .PARAMETER Aggregate 集計のみ
#>
[CmdletBinding()]param([string]$From='2022-01-01',[string]$To='2026-12-31',[ValidateSet('puku','tan')][string]$Bet='puku',[int]$RunType=0,[switch]$Aggregate)
$ErrorActionPreference='Stop'
$csv="C:\temp\ai_sanren_${Bet}_rt${RunType}.csv"
$ordered=($Bet -eq 'tan')

function Aggregate(){
  if(-not (Test-Path $csv)){ "CSVなし: $csv"; return }
  $rows=Import-Csv $csv
  "===== 集計: AI三連{0} runType={1}({2}) / CSV {3}行 =====" -f $(if($Bet -eq 'puku'){'複'}else{'単'}),$RunType,$(if($RunType -eq 0){'前日'}else{'直前'}),$rows.Count
  function Grp($name,$sel){
    $g=$rows|Group-Object $sel
    foreach($x in ($g|Sort-Object Name)){
      $n=$x.Count; $hit=($x.Group|Measure-Object hit -Sum).Sum; $cost=($x.Group|Measure-Object cost -Sum).Sum; $ret=($x.Group|Measure-Object ret -Sum).Sum; $pts=($x.Group|Measure-Object pts -Sum).Sum
      "  {0,-14} N={1,5} 点数/R={2,4:N1} 的中率={3,5:N1}% 回収率={4,6:N1}%" -f "$name=$($x.Name)",$n,($pts/$n),(100*$hit/$n),(100*$ret/$cost)
    }
  }
  $n=$rows.Count;$hit=($rows|Measure-Object hit -Sum).Sum;$cost=($rows|Measure-Object cost -Sum).Sum;$ret=($rows|Measure-Object ret -Sum).Sum;$pts=($rows|Measure-Object pts -Sum).Sum
  "  {0,-14} N={1,5} 点数/R={2,4:N1} 的中率={3,5:N1}% 回収率={4,6:N1}%" -f 'ALL',$n,($pts/$n),(100*$hit/$n),(100*$ret/$cost)
  ""; "-- 年別 --"; Grp 'year' 'year'
  ""; "-- confidence_rank別 --"; Grp 'rank' 'rank'
  ""; "-- 買種別 --"; Grp 'buy' 'buy'
  return
}
if($Aggregate){ Aggregate; return }

$ua="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36"
$curl="C:\Windows\System32\curl.exe"; $api="https://horse.ai-nikkansports.com"
$ep= if($Bet -eq 'puku'){'sanrenpukuList'}else{'sanrentanList'}
function Login(){ (& $curl -s -A $ua --connect-timeout 15 --max-time 40 -X POST "$api/auth/login" --data-urlencode "userId=zY7J3ptH" --data-urlencode "password=u7LMJFpy"|ConvertFrom-Json).access_token }
$tok=Login; if(-not $tok){ throw "login失敗" }

# 対象 date×venue
$cs=(Get-Content (Join-Path $PSScriptRoot '..\共通\appsettings.json') -Raw -Encoding UTF8|ConvertFrom-Json).ConnectionStrings.DefaultConnection
$conn=New-Object System.Data.SqlClient.SqlConnection($cs);$conn.Open()
$cmd=$conn.CreateCommand();$cmd.CommandText="SELECT DISTINCT 開催日 d,開催場所 v FROM レース情報 WHERE 開催日 BETWEEN @f AND @t AND 着順>0 ORDER BY 開催日,開催場所"
[void]$cmd.Parameters.AddWithValue('@f',$From);[void]$cmd.Parameters.AddWithValue('@t',$To)
$r=$cmd.ExecuteReader();$dv=@();while($r.Read()){$dv+=[pscustomobject]@{d=([datetime]$r['d']).ToString('yyyyMMdd');v=[string]$r['v']}};$r.Close();$conn.Close()

# 再開: 既存CSVの date|venue をスキップ
$done=New-Object 'System.Collections.Generic.HashSet[string]'
if(Test-Path $csv){ Import-Csv $csv | ForEach-Object{ [void]$done.Add("$($_.date)|$($_.venue)") } }
else { 'date,venue,race,year,rank,buy,pts,hit,cost,ret' | Out-File $csv -Encoding utf8 }
function Key3($a,$b,$c){ if($ordered){ "$a-$b-$c" } else { (@([int]$a,[int]$b,[int]$c)|Sort-Object) -join '-' } }

$tmp="C:\temp\ai_sr_$Bet$RunType.json"; $i=0; $sb=New-Object System.Text.StringBuilder
foreach($g in $dv){
  $i++
  if($done.Contains("$($g.d)|$($g.v)")){ continue }
  if($i % 250 -eq 0){ $tok=Login }
  $cn=[uri]::EscapeDataString($g.v)
  & $curl -s -A $ua --connect-timeout 15 --max-time 60 -H "Authorization: Bearer $tok" -o $tmp "$api/predict/$ep`?dateFrom=$($g.d)&dateTo=$($g.d)&courseName=$cn&runType=$RunType"
  $txt= if(Test-Path $tmp){[IO.File]::ReadAllText($tmp,[Text.Encoding]::UTF8)}else{''}
  if($txt.Length -lt 5){ continue }
  $races=$null; try{ $races=@($txt|ConvertFrom-Json) }catch{ continue }
  [void]$sb.Clear()
  $yr=[int]$g.d.Substring(0,4)
  foreach($e in $races){
    if($null -eq $e.trp_hb_number1 -or [int]$e.trp_hb_number1 -le 0){ continue }
    $combos=@($e.sanren); if($combos.Count -eq 0){ continue }
    $winner=Key3 $e.trp_hb_number1 $e.trp_hb_number2 $e.trp_hb_number3
    $set=@{}; foreach($cb in $combos){ $set[(Key3 $cb.hb_number1 $cb.hb_number2 $cb.hb_number3)]=$true }
    $pts=$set.Keys.Count; if($pts -eq 0){ continue }
    $hit= if($set.ContainsKey($winner)){1}else{0}
    $pay= if($hit){[int]$e.payoff}else{0}
    $cr= if($e.confidence_rank){"$($e.confidence_rank)"}else{'?'}
    $bt= if($e.buy_type_name){"$($e.buy_type_name)"}else{'?'}
    [void]$sb.AppendLine(('{0},{1},{2},{3},{4},{5},{6},{7},{8},{9}' -f $g.d,$g.v,$e.race_number,$yr,$cr,$bt,$pts,$hit,($pts*100),$pay))
  }
  if($sb.Length -gt 0){ [IO.File]::AppendAllText($csv,$sb.ToString(),[Text.Encoding]::UTF8) }
  [void]$done.Add("$($g.d)|$($g.v)")
}
"取得完了: $csv"
Aggregate
