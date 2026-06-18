param(
    [datetime]$StartDate = [datetime]'2006-06-13',
    [datetime]$EndDate = [datetime]'2026-06-13',
    [int]$MinimumDistance = 2000,
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\artifacts\long-distance-corner-audit'),
    [int]$DelayMilliseconds = 80,
    [switch]$Refresh
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

$baseUrl = 'https://www.keiba.go.jp'
$downloadUrl = "$baseUrl/KeibaWeb/DataDownload/RaceDataDownload"
$zipDirectory = Join-Path $OutputDirectory 'race_data_zips'
$extractDirectory = Join-Path $OutputDirectory 'race_data_extract'
$raceCsv = Join-Path $OutputDirectory 'long_distance_races.csv'
$patternCsv = Join-Path $OutputDirectory 'long_distance_corner_patterns.csv'
$placeCsv = Join-Path $OutputDirectory 'long_distance_place_summary.csv'
$monthlyLogCsv = Join-Path $OutputDirectory 'monthly_download_log.csv'
$summaryMd = Join-Path $OutputDirectory 'long_distance_corner_summary.md'

$courseMap = @{
    '1' = '北見ば'; '2' = '岩見ば'; '3' = '帯広ば'; '4' = '旭川ば'
    '7' = '旭川'; '8' = '札幌'; '10' = '盛岡'; '11' = '水沢'; '12' = '上山'
    '13' = '新潟'; '14' = '三条'; '15' = '足利'; '16' = '宇都宮'; '17' = '高崎'
    '18' = '浦和'; '19' = '船橋'; '20' = '大井'; '21' = '川崎'; '22' = '金沢'
    '23' = '笠松'; '24' = '名古屋'; '25' = '中京'; '27' = '園田'; '28' = '姫路'
    '29' = '益田'; '30' = '福山'; '31' = '高知'; '32' = '佐賀'; '33' = '荒尾'
    '34' = '中津'; '36' = '門別'
}

$placeToCode = @{}
foreach ($entry in $courseMap.GetEnumerator()) {
    if (-not $placeToCode.ContainsKey($entry.Value)) {
        $placeToCode[$entry.Value] = $entry.Key
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

function Add-CsvRecord {
    param(
        [string]$Path,
        [object]$Record
    )

    if (Test-Path $Path) {
        $Record | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8 -Append
    }
    else {
        $Record | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8
    }
}

function Invoke-DownloadFile {
    param(
        [string]$Url,
        [string]$Path
    )

    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            if ($DelayMilliseconds -gt 0) {
                Start-Sleep -Milliseconds $DelayMilliseconds
            }

            Invoke-WebRequest -Uri $Url -UseBasicParsing -OutFile $Path
            return
        }
        catch {
            if ($attempt -eq 3) {
                throw
            }

            Start-Sleep -Seconds (2 * $attempt)
        }
    }
}

function Get-RaceDataZipPath {
    param([datetime]$Month)

    $zipPath = Join-Path $zipDirectory "$($Month.ToString('yyyyMM'))_race.zip"
    if ((Test-Path $zipPath) -and -not $Refresh) {
        return $zipPath
    }

    $url = "$downloadUrl`?type=monthly&k_year=$($Month.Year)&k_month=$($Month.Month)"
    Write-Host "Download $($Month.ToString('yyyy-MM'))"
    Invoke-DownloadFile -Url $url -Path $zipPath
    $zipPath
}

function Get-RaceListCsvPath {
    param(
        [datetime]$Month,
        [string]$ZipPath
    )

    $monthKey = $Month.ToString('yyyyMM')
    $monthExtractDirectory = Join-Path $extractDirectory $monthKey
    $raceListCsv = Join-Path $monthExtractDirectory "$($monthKey)_racelist.csv"

    if ((Test-Path $raceListCsv) -and -not $Refresh) {
        return $raceListCsv
    }

    if (Test-Path $monthExtractDirectory) {
        Remove-Item -LiteralPath $monthExtractDirectory -Recurse -Force
    }
    New-Item -ItemType Directory -Path $monthExtractDirectory -Force | Out-Null

    [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $monthExtractDirectory)
    if (-not (Test-Path $raceListCsv)) {
        $found = Get-ChildItem -LiteralPath $monthExtractDirectory -Filter '*_racelist.csv' -File | Select-Object -First 1
        if ($found) {
            return $found.FullName
        }

        throw "racelist.csv が見つかりません: $ZipPath"
    }

    $raceListCsv
}

function Get-OrderedValues {
    param(
        [object]$Row,
        [string]$Prefix,
        [int]$Count = 8
    )

    $values = New-Object System.Collections.Generic.List[string]
    for ($index = 1; $index -le $Count; $index++) {
        $name = "$Prefix$index"
        $value = $Row.$name
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            $values.Add($value.Trim()) | Out-Null
        }
    }

    $values
}

function Get-SymbolPattern {
    param([string[]]$Texts)

    $symbols = New-Object System.Collections.Generic.List[string]
    $seen = @{}
    foreach ($text in $Texts) {
        $targetText = if ($null -eq $text) { '' } else { $text }
        foreach ($match in [regex]::Matches($targetText, '[,，、()（）\-＝=]')) {
            $value = $match.Value
            if (-not $seen.ContainsKey($value)) {
                $symbols.Add($value) | Out-Null
                $seen[$value] = $true
            }
        }
    }

    $symbols -join ''
}

function New-RaceMarkUrl {
    param(
        [datetime]$RaceDate,
        [string]$BabaCode,
        [string]$RaceNo
    )

    $escapedDate = [Uri]::EscapeDataString($RaceDate.ToString('yyyy/MM/dd'))
    "$baseUrl/KeibaWeb/TodayRaceInfo/RaceMarkTable?k_raceDate=$escapedDate&k_raceNo=$RaceNo&k_babaCode=$BabaCode"
}

function New-RaceListUrl {
    param(
        [datetime]$RaceDate,
        [string]$BabaCode
    )

    $escapedDate = [Uri]::EscapeDataString($RaceDate.ToString('yyyy/MM/dd'))
    "$baseUrl/KeibaWeb/TodayRaceInfo/RaceList?k_raceDate=$escapedDate&k_babaCode=$BabaCode"
}

function Convert-RaceDataRow {
    param([object]$Row)

    $raceDate = [datetime]::ParseExact($Row.'競走年月日', 'yyyyMMdd', [Globalization.CultureInfo]::InvariantCulture)
    if ($raceDate.Date -lt $StartDate.Date -or $raceDate.Date -gt $EndDate.Date) {
        return $null
    }

    $distance = 0
    if (-not [int]::TryParse($Row.'距離', [ref]$distance) -or $distance -lt $MinimumDistance) {
        return $null
    }

    $place = $Row.'競馬場'
    $babaCode = if ($placeToCode.ContainsKey($place)) { $placeToCode[$place] } else { '' }
    $cornerLabels = @(Get-OrderedValues -Row $Row -Prefix 'コーナー名称')
    $cornerPassages = @(Get-OrderedValues -Row $Row -Prefix 'コーナー通過順')
    $raceNo = $Row.'レース番号'

    [pscustomobject]@{
        RaceDate = $raceDate.ToString('yyyy-MM-dd')
        Place = $place
        BabaCode = $babaCode
        RaceNo = $raceNo
        RaceName = $Row.'レース名'
        RaceType = $Row.'競走種類名称'
        Direction = $Row.'回り'
        Distance = $distance
        HeadCount = $Row.'頭数'
        TrackCondition = $Row.'馬場'
        CornerLabelCount = $cornerLabels.Count
        CornerLabels = ($cornerLabels -join '|')
        CornerPassageCount = $cornerPassages.Count
        CornerPassages = ($cornerPassages -join '|')
        PassageSymbols = Get-SymbolPattern -Texts $cornerPassages
        RaceListUrl = if ($babaCode) { New-RaceListUrl -RaceDate $raceDate -BabaCode $babaCode } else { '' }
        ResultUrl = if ($babaCode) { New-RaceMarkUrl -RaceDate $raceDate -BabaCode $babaCode -RaceNo $raceNo } else { '' }
    }
}

function Export-LongDistanceRaces {
    $records = New-Object System.Collections.Generic.List[object]
    foreach ($month in Get-MonthStarts -From $StartDate -To $EndDate) {
        try {
            $zipPath = Get-RaceDataZipPath -Month $month
            $csvPath = Get-RaceListCsvPath -Month $month -ZipPath $zipPath
            $monthRows = @(Import-Csv -Path $csvPath -Encoding UTF8)
            $monthRecords = New-Object System.Collections.Generic.List[object]
            foreach ($row in $monthRows) {
                $record = Convert-RaceDataRow -Row $row
                if ($null -ne $record) {
                    $records.Add($record) | Out-Null
                    $monthRecords.Add($record) | Out-Null
                }
            }

            Add-CsvRecord -Path $monthlyLogCsv -Record ([pscustomobject]@{
                Month = $month.ToString('yyyy-MM')
                Status = 'OK'
                RaceRows = $monthRows.Count
                LongDistanceRows = $monthRecords.Count
                ZipPath = $zipPath
                CsvPath = $csvPath
                Error = ''
            })
        }
        catch {
            Add-CsvRecord -Path $monthlyLogCsv -Record ([pscustomobject]@{
                Month = $month.ToString('yyyy-MM')
                Status = 'ERROR'
                RaceRows = ''
                LongDistanceRows = ''
                ZipPath = ''
                CsvPath = ''
                Error = $_.Exception.Message
            })
        }
    }

    $records |
        Sort-Object RaceDate, Place, {[int]$_.RaceNo} |
        Export-Csv -Path $raceCsv -NoTypeInformation -Encoding UTF8
}

function Write-Summary {
    $records = @(Import-Csv -Path $raceCsv -Encoding UTF8)

    $patternSummary = foreach ($group in ($records | Group-Object CornerLabels | Sort-Object Count -Descending)) {
        $distances = $group.Group.Distance | ForEach-Object { [int]$_ } | Sort-Object -Unique
        $places = $group.Group.Place | Sort-Object -Unique
        $symbols = $group.Group.PassageSymbols | Where-Object { $_ } | Sort-Object -Unique
        $example = $group.Group | Select-Object -First 1
        [pscustomobject]@{
            CornerLabels = if ($group.Name) { $group.Name } else { '(空欄)' }
            RaceCount = $group.Count
            Places = ($places -join '|')
            MinDistance = if ($distances.Count -gt 0) { $distances[0] } else { '' }
            MaxDistance = if ($distances.Count -gt 0) { $distances[$distances.Count - 1] } else { '' }
            PassageSymbols = ($symbols -join '|')
            Example = "$($example.RaceDate) $($example.Place) $($example.RaceNo)R $($example.Distance)m $($example.RaceName)"
            ExampleResultUrl = $example.ResultUrl
        }
    }

    $placeSummary = foreach ($group in ($records | Group-Object Place | Sort-Object Name)) {
        $distances = $group.Group.Distance | ForEach-Object { [int]$_ } | Sort-Object -Unique
        $labels = $group.Group.CornerLabels | Where-Object { $_ } | Sort-Object -Unique
        $symbols = $group.Group.PassageSymbols | Where-Object { $_ } | Sort-Object -Unique
        [pscustomobject]@{
            Place = $group.Name
            RaceCount = $group.Count
            MinDistance = if ($distances.Count -gt 0) { $distances[0] } else { '' }
            MaxDistance = if ($distances.Count -gt 0) { $distances[$distances.Count - 1] } else { '' }
            CornerLabelPatterns = ($labels -join ', ')
            PassageSymbols = ($symbols -join '|')
        }
    }

    $patternSummary | Export-Csv -Path $patternCsv -NoTypeInformation -Encoding UTF8
    $placeSummary | Export-Csv -Path $placeCsv -NoTypeInformation -Encoding UTF8

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# 2000m以上レース コーナー通過順表記確認結果")
    $lines.Add("")
    $lines.Add("- 対象期間: $($StartDate.ToString('yyyy-MM-dd')) から $($EndDate.ToString('yyyy-MM-dd'))")
    $lines.Add("- 抽出条件: 月別レースデータの距離が $MinimumDistance m 以上")
    $lines.Add("- 元情報: $downloadUrl")
    $lines.Add("- 抽出レース数: $($records.Count)")
    $lines.Add("")
    $lines.Add("## コーナー名称パターン")
    $lines.Add("")
    $lines.Add("| コーナー名称 | レース数 | 競馬場 | 距離範囲 | 通過順内の記号 | 例 |")
    $lines.Add("|---|---:|---|---|---|---|")
    foreach ($item in $patternSummary) {
        $lines.Add("| $($item.CornerLabels) | $($item.RaceCount) | $($item.Places) | $($item.MinDistance)-$($item.MaxDistance)m | $($item.PassageSymbols) | $($item.Example) |")
    }
    $lines.Add("")
    $lines.Add("## 競馬場別")
    $lines.Add("")
    $lines.Add("| 競馬場 | レース数 | 距離範囲 | コーナー名称パターン | 通過順内の記号 |")
    $lines.Add("|---|---:|---|---|---|")
    foreach ($item in $placeSummary) {
        $lines.Add("| $($item.Place) | $($item.RaceCount) | $($item.MinDistance)-$($item.MaxDistance)m | $($item.CornerLabelPatterns) | $($item.PassageSymbols) |")
    }

    $lines | Set-Content -Path $summaryMd -Encoding UTF8
}

New-Item -ItemType Directory -Path $OutputDirectory, $zipDirectory, $extractDirectory -Force | Out-Null
if ($Refresh) {
    Remove-Item -Path $raceCsv, $patternCsv, $placeCsv, $monthlyLogCsv, $summaryMd -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $extractDirectory -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $extractDirectory -Force | Out-Null
}

Export-LongDistanceRaces
Write-Summary

Write-Host "Races: $raceCsv"
Write-Host "Patterns: $patternCsv"
Write-Host "Places: $placeCsv"
Write-Host "Summary: $summaryMd"

