param(
    [datetime]$StartDate = [datetime]'2006-06-13',
    [datetime]$EndDate = [datetime]'2026-06-13',
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\artifacts\corner-position-audit'),
    [int]$DelayMilliseconds = 80,
    [int]$MaxSamples = 0,
    [switch]$Refresh
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http

$baseUrl = 'https://www.keiba.go.jp'
$monthlyTopUrl = "$baseUrl/KeibaWeb/MonthlyConveneInfo/MonthlyConveneInfoTop"
$sampleCsv = Join-Path $OutputDirectory 'corner_position_samples.csv'
$summaryCsv = Join-Path $OutputDirectory 'corner_position_summary.csv'
$summaryMd = Join-Path $OutputDirectory 'corner_position_summary.md'
$scheduleCsv = Join-Path $OutputDirectory 'sample_schedule.csv'

$courseMap = @{
    '1' = '北見ば'; '2' = '岩見ば'; '3' = '帯広ば'; '4' = '旭川ば'
    '7' = '旭川'; '8' = '札幌'; '10' = '盛岡'; '11' = '水沢'; '12' = '上山'
    '13' = '新潟'; '14' = '三条'; '15' = '足利'; '16' = '宇都宮'; '17' = '高崎'
    '18' = '浦和'; '19' = '船橋'; '20' = '大井'; '21' = '川崎'; '22' = '金沢'
    '23' = '笠松'; '24' = '名古屋'; '25' = '中京'; '27' = '園田'; '28' = '姫路'
    '29' = '益田'; '30' = '福山'; '31' = '高知'; '32' = '佐賀'; '33' = '荒尾'
    '34' = '中津'; '36' = '門別'
}

function ConvertTo-PlainText {
    param([string]$Html)

    $text = [regex]::Replace($Html, '<br\s*/?>', ' ', 'IgnoreCase')
    $text = [regex]::Replace($text, '<[^>]+>', ' ')
    $text = [System.Net.WebUtility]::HtmlDecode($text)
    [regex]::Replace($text, '\s+', ' ').Trim()
}

function ConvertTo-AbsoluteUrl {
    param([string]$RelativeUrl)

    $clean = [System.Net.WebUtility]::HtmlDecode($RelativeUrl)
    if ($clean.StartsWith('http')) {
        return $clean
    }

    if ($clean.StartsWith('/')) {
        return "$baseUrl$clean"
    }

    "$baseUrl/KeibaWeb/TodayRaceInfo/$clean"
}

function New-RaceMarkUrl {
    param(
        [string]$RaceDate,
        [string]$BabaCode,
        [int]$RaceNo = 1
    )

    $escapedDate = [Uri]::EscapeDataString(([datetime]$RaceDate).ToString('yyyy/MM/dd'))
    "$baseUrl/KeibaWeb/TodayRaceInfo/RaceMarkTable?k_raceDate=$escapedDate&k_raceNo=$RaceNo&k_babaCode=$BabaCode"
}

function Get-Page {
    param(
        [System.Net.Http.HttpClient]$Client,
        [string]$Url
    )

    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            if ($DelayMilliseconds -gt 0) {
                Start-Sleep -Milliseconds $DelayMilliseconds
            }

            return $Client.GetStringAsync($Url).GetAwaiter().GetResult()
        }
        catch {
            if ($attempt -eq 3) {
                throw
            }

            Start-Sleep -Seconds (2 * $attempt)
        }
    }
}

function Get-MonthStarts {
    param(
        [datetime]$From,
        [datetime]$To
    )

    $month = Get-Date -Year $From.Year -Month $From.Month -Day 1 -Hour 0 -Minute 0 -Second 0
    $lastMonth = Get-Date -Year $To.Year -Month $To.Month -Day 1 -Hour 0 -Minute 0 -Second 0

    while ($month -le $lastMonth) {
        $month
        $month = $month.AddMonths(1)
    }
}

function Get-ScheduleSamples {
    param([System.Net.Http.HttpClient]$Client)

    $items = New-Object System.Collections.Generic.List[object]
    $seen = @{}

    foreach ($month in Get-MonthStarts -From $StartDate -To $EndDate) {
        $url = "$monthlyTopUrl`?k_year=$($month.Year)&k_month=$($month.Month)"
        Write-Host "Schedule $($month.ToString('yyyy-MM'))"
        $html = Get-Page -Client $Client -Url $url

        $matches = [regex]::Matches($html, 'RaceList\?k_raceDate=(?<date>\d{4}%2F\d{2}%2F\d{2})(?:&amp;|&)k_babaCode=(?<code>\d+)', 'IgnoreCase')
        foreach ($match in $matches) {
            $dateText = [Uri]::UnescapeDataString($match.Groups['date'].Value)
            $raceDate = [datetime]::ParseExact($dateText, 'yyyy/MM/dd', [Globalization.CultureInfo]::InvariantCulture)
            if ($raceDate.Date -lt $StartDate.Date -or $raceDate.Date -gt $EndDate.Date) {
                continue
            }

            $code = $match.Groups['code'].Value
            if (-not $courseMap.ContainsKey($code)) {
                continue
            }

            $place = $courseMap[$code]
            if ($place.EndsWith('ば')) {
                continue
            }

            $key = "$($raceDate.ToString('yyyy-MM-dd'))|$code"
            if ($seen.ContainsKey($key)) {
                continue
            }

            $seen[$key] = $true
            $raceListUrl = ConvertTo-AbsoluteUrl $match.Value
            $items.Add([pscustomobject]@{
                RaceDate = $raceDate.ToString('yyyy-MM-dd')
                Place = $place
                BabaCode = $code
                RaceListUrl = $raceListUrl
            })
        }
    }

    $items | Sort-Object RaceDate, Place
}

function Get-OrCreateSchedule {
    param([System.Net.Http.HttpClient]$Client)

    if ((Test-Path $scheduleCsv) -and -not $Refresh) {
        return Import-Csv -Path $scheduleCsv
    }

    $schedule = Get-ScheduleSamples -Client $Client
    $schedule | Export-Csv -Path $scheduleCsv -NoTypeInformation -Encoding UTF8
    $schedule
}

function Test-CornerText {
    param([string]$Text)

    if ($null -eq $Text) {
        $Text = ''
    }

    $normalized = [regex]::Replace($Text, '\s+', '')
    $normalized -match '^\d+(?:[-－ー―,、]\d+)+$'
}

function Get-CornerDetails {
    param([string]$ResultHtml)

    $rowCornerValues = New-Object System.Collections.Generic.List[string]
    $rows = [regex]::Matches($ResultHtml, '<tr\b[^>]*class\s*=\s*["''][^""'']*\btBorder\b[^""'']*["''][^>]*>(?<row>.*?)</tr>', 'IgnoreCase,Singleline')

    foreach ($row in $rows) {
        $cells = [regex]::Matches($row.Groups['row'].Value, '<td\b(?<attrs>[^>]*)>(?<cell>.*?)</td>', 'IgnoreCase,Singleline')
        if ($cells.Count -eq 0) {
            continue
        }

        $texts = @()
        $cornerText = ''
        for ($index = 0; $index -lt $cells.Count; $index++) {
            $text = ConvertTo-PlainText $cells[$index].Groups['cell'].Value
            $texts += $text
            if ($cells[$index].Groups['attrs'].Value -match '\bcorner_position\b') {
                $cornerText = $text
            }
        }

        if ([string]::IsNullOrWhiteSpace($cornerText) -and $texts.Count -gt 13 -and (Test-CornerText $texts[13])) {
            $cornerText = $texts[13]
        }

        if ([string]::IsNullOrWhiteSpace($cornerText)) {
            $cornerText = ($texts | Where-Object { Test-CornerText $_ } | Select-Object -First 1)
        }

        if (-not [string]::IsNullOrWhiteSpace($cornerText)) {
            $rowCornerValues.Add($cornerText)
        }
    }

    $distinctValues = $rowCornerValues | Sort-Object -Unique
    $tokenCounts = $distinctValues |
        ForEach-Object { ([regex]::Matches($_, '\d+')).Count } |
        Where-Object { $_ -gt 0 } |
        Sort-Object -Unique

    $delimiters = $distinctValues |
        ForEach-Object { [regex]::Matches($_, '[-－ー―,、]') | ForEach-Object Value } |
        Sort-Object -Unique

    $sectionLabels = [regex]::Matches($ResultHtml, '<td[^>]*>\s*(?<label>向正面|第?\s*[１２３４1-4一二三四]\s*(?:コーナー|角))\s*</td>', 'IgnoreCase') |
        ForEach-Object { ConvertTo-PlainText $_.Groups['label'].Value } |
        Sort-Object -Unique

    $style = if ($distinctValues.Count -eq 0) {
        '通過順セルなし'
    }
    elseif (($tokenCounts | Measure-Object).Count -eq 1) {
        "$($tokenCounts[0])点表記"
    }
    else {
        "混在:" + (($tokenCounts | ForEach-Object { "$_点" }) -join '/')
    }

    [pscustomobject]@{
        RowCount = $rows.Count
        RowCornerValues = (($distinctValues | Select-Object -First 20) -join '|')
        RowCornerValueCount = $distinctValues.Count
        TokenCounts = ($tokenCounts -join '|')
        Delimiters = ($delimiters -join '')
        SectionLabels = ($sectionLabels -join '|')
        Style = $style
    }
}

function Write-Summary {
    if (-not (Test-Path $sampleCsv)) {
        return
    }

    $records = Import-Csv -Path $sampleCsv | Where-Object { $_.Status -eq 'OK' }
    $summary = foreach ($group in ($records | Group-Object Place | Sort-Object Name)) {
        $tokenCounts = $group.Group.TokenCounts | Where-Object { $_ } | Sort-Object -Unique
        $styles = $group.Group.Style | Where-Object { $_ } | Sort-Object -Unique
        $sections = $group.Group.SectionLabels | Where-Object { $_ } | Sort-Object -Unique
        $examples = $group.Group |
            Where-Object { $_.RowCornerValues } |
            Select-Object -First 5 |
            ForEach-Object { "$($_.RaceDate) $($_.RowCornerValues)" }

        [pscustomobject]@{
            Place = $group.Name
            Samples = $group.Count
            Styles = ($styles -join ', ')
            TokenCounts = ($tokenCounts -join ', ')
            SectionLabels = ($sections -join ', ')
            Examples = ($examples -join ' / ')
        }
    }

    $summary | Export-Csv -Path $summaryCsv -NoTypeInformation -Encoding UTF8

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# 通過順表記サンプリング結果")
    $lines.Add("")
    $lines.Add("- 対象期間: $($StartDate.ToString('yyyy-MM-dd')) から $($EndDate.ToString('yyyy-MM-dd'))")
    $lines.Add("- 除外: 場名が「ば」で終わる競馬場")
    $lines.Add("- サンプル方法: 開催日・競馬場ごとに当日メニューの最初の競走成績ページを1件確認")
    $lines.Add("")
    $lines.Add("| 競馬場 | サンプル数 | 行内通過順 | 数字点数 | 全馬コーナー欄 | 例 |")
    $lines.Add("|---|---:|---|---|---|---|")
    foreach ($item in $summary) {
        $lines.Add("| $($item.Place) | $($item.Samples) | $($item.Styles) | $($item.TokenCounts) | $($item.SectionLabels) | $($item.Examples) |")
    }

    $lines | Set-Content -Path $summaryMd -Encoding UTF8
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
if ($Refresh) {
    Remove-Item -Path $sampleCsv, $summaryCsv, $summaryMd, $scheduleCsv -ErrorAction SilentlyContinue
}

$handler = [System.Net.Http.HttpClientHandler]::new()
$handler.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate
$client = [System.Net.Http.HttpClient]::new($handler)
$client.Timeout = [TimeSpan]::FromSeconds(30)
$client.DefaultRequestHeaders.UserAgent.ParseAdd('Mozilla/5.0 LocalHorceRaceCornerAudit/1.0')

try {
    $schedule = Get-OrCreateSchedule -Client $client

    $completed = @{}
    if (Test-Path $sampleCsv) {
        Import-Csv -Path $sampleCsv | ForEach-Object {
            $completed["$($_.RaceDate)|$($_.BabaCode)"] = $true
        }
    }

    $processed = 0
    $total = $schedule.Count
    $headerWritten = Test-Path $sampleCsv

    for ($i = 0; $i -lt $schedule.Count; $i++) {
        $item = $schedule[$i]
        $key = "$($item.RaceDate)|$($item.BabaCode)"
        if ($completed.ContainsKey($key)) {
            continue
        }

        if ($MaxSamples -gt 0 -and $processed -ge $MaxSamples) {
            break
        }

        Write-Host "Sample $($i + 1)/$total $($item.RaceDate) $($item.Place)"
        $record = $null
        try {
            $race = [pscustomobject]@{
                RaceNo = 1
                Url = New-RaceMarkUrl -RaceDate $item.RaceDate -BabaCode $item.BabaCode -RaceNo 1
            }

            $resultHtml = Get-Page -Client $client -Url $race.Url
            $details = Get-CornerDetails -ResultHtml $resultHtml

            if ($details.RowCount -eq 0) {
                $raceListHtml = Get-Page -Client $client -Url $item.RaceListUrl
                $raceLinks = [regex]::Matches($raceListHtml, 'RaceMarkTable\?k_raceDate=(?<date>\d{4}%2F\d{2}%2F\d{2})(?:&amp;|&)k_raceNo=(?<raceNo>\d+)(?:&amp;|&)k_babaCode=(?<code>\d+)', 'IgnoreCase') |
                    ForEach-Object {
                        [pscustomobject]@{
                            RaceNo = [int]$_.Groups['raceNo'].Value
                            Url = ConvertTo-AbsoluteUrl $_.Value
                        }
                    } |
                    Sort-Object RaceNo -Unique

                if (($raceLinks | Measure-Object).Count -eq 0) {
                    throw '当日メニューに競走成績リンクがありません。'
                }

                $race = $raceLinks | Select-Object -First 1
                $resultHtml = Get-Page -Client $client -Url $race.Url
                $details = Get-CornerDetails -ResultHtml $resultHtml
            }

            if ($details.RowCount -eq 0) {
                throw '競走成績行が見つかりません。'
            }

            $record = [pscustomobject]@{
                RaceDate = $item.RaceDate
                Place = $item.Place
                BabaCode = $item.BabaCode
                RaceNo = $race.RaceNo
                Status = 'OK'
                Style = $details.Style
                TokenCounts = $details.TokenCounts
                Delimiters = $details.Delimiters
                RowCount = $details.RowCount
                RowCornerValueCount = $details.RowCornerValueCount
                RowCornerValues = $details.RowCornerValues
                SectionLabels = $details.SectionLabels
                RaceListUrl = $item.RaceListUrl
                ResultUrl = $race.Url
                Error = ''
            }
        }
        catch {
            $record = [pscustomobject]@{
                RaceDate = $item.RaceDate
                Place = $item.Place
                BabaCode = $item.BabaCode
                RaceNo = ''
                Status = 'ERROR'
                Style = ''
                TokenCounts = ''
                Delimiters = ''
                RowCount = ''
                RowCornerValueCount = ''
                RowCornerValues = ''
                SectionLabels = ''
                RaceListUrl = $item.RaceListUrl
                ResultUrl = ''
                Error = $_.Exception.Message
            }
        }

        if ($headerWritten) {
            $record | Export-Csv -Path $sampleCsv -NoTypeInformation -Encoding UTF8 -Append
        }
        else {
            $record | Export-Csv -Path $sampleCsv -NoTypeInformation -Encoding UTF8
            $headerWritten = $true
        }

        $completed[$key] = $true
        $processed++

        if ($processed % 100 -eq 0) {
            Write-Summary
            Write-Host "Processed this run: $processed"
        }
    }

    Write-Summary
    Write-Host "Schedule count: $total"
    Write-Host "Processed this run: $processed"
    Write-Host "Samples: $sampleCsv"
    Write-Host "Summary: $summaryMd"
}
finally {
    $client.Dispose()
    $handler.Dispose()
}


