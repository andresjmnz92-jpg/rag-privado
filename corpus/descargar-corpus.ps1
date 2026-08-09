# Pulls parts 160, 162 and 164 of Title 45 (HIPAA) from the eCFR API and writes
# one Markdown file per section.
#
# The API hands back each section as its own <DIV8 TYPE="SECTION">, with its
# number and official citation as attributes. So there is nothing to split by
# hand here: the source arrives already split. No API key needed.

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$outDir = Join-Path $PSScriptRoot 'secciones'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

# The effective date comes from the API, not from a date written in here. A
# corpus that hardcodes its own currency goes stale without telling you.
$titles = Invoke-RestMethod 'https://www.ecfr.gov/api/versioner/v1/titles.json'
$asOf = ($titles.titles | Where-Object { $_.number -eq 45 }).up_to_date_as_of
Write-Output "Title 45 current as of $asOf"

$written = 0
$empty = @()

foreach ($part in 160, 162, 164) {
  $url = "https://www.ecfr.gov/api/versioner/v1/full/$asOf/title-45.xml?part=$part"
  $xml = [xml](Invoke-WebRequest -Uri $url -UseBasicParsing).Content

  foreach ($section in $xml.SelectNodes("//DIV8[@TYPE='SECTION']")) {
    $number = $section.GetAttribute('N')
    $heading = $section.SelectSingleNode('HEAD').InnerText.Trim()

    # The italics in the XML (<I> and <E T="04">) mark the title of each
    # paragraph -- "Standard", "General rule", "Elements". They are not
    # decoration: they are the signal for where one unit ends and the next
    # begins, which is what makes the long sections splittable later.
    $body = ($section.SelectNodes('.//P') | ForEach-Object {
      $text = $_.InnerXml -replace '</?I>', '*' -replace '<E[^>]*>', '*' -replace '</E>', '*'
      [System.Net.WebUtility]::HtmlDecode($text).Trim()
    }) -join "`r`n`r`n"

    if ([string]::IsNullOrWhiteSpace($body)) { $empty += $number }

    $md = @"
---
section: "$number"
citation: "45 CFR $number"
source: "https://www.ecfr.gov/current/title-45/section-$number"
title: "$($heading -replace '"', "'")"
retrieved: $asOf
---

## $heading

$body
"@
    $md | Out-File -FilePath (Join-Path $outDir "$number.md") -Encoding utf8
    $written++
  }
}

Write-Output "$written sections written to $outDir"
if ($empty.Count -gt 0) {
  Write-Output "No text (reserved sections, or tables only): $($empty -join ', ')"
}
