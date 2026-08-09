# Descarga las partes 160, 162 y 164 del titulo 45 (HIPAA) desde la API del eCFR
# y escribe un archivo Markdown por seccion.
#
# La API entrega cada seccion como un <DIV8 TYPE="SECTION"> con su numero y su
# cita oficial. Por eso no hace falta partir el texto a ciegas: la fuente ya
# viene partida. Sin llave de API.

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$destino = Join-Path $PSScriptRoot 'secciones'
New-Item -ItemType Directory -Force -Path $destino | Out-Null

# La fecha de vigencia la dice la propia API, para que el corpus no envejezca en duro.
$titulos = Invoke-RestMethod 'https://www.ecfr.gov/api/versioner/v1/titles.json'
$fecha = ($titulos.titles | Where-Object { $_.number -eq 45 }).up_to_date_as_of
Write-Output "Titulo 45 vigente al $fecha"

$total = 0
$vacias = @()

foreach ($parte in 160, 162, 164) {
  $url = "https://www.ecfr.gov/api/versioner/v1/full/$fecha/title-45.xml?part=$parte"
  $xml = [xml](Invoke-WebRequest -Uri $url -UseBasicParsing).Content

  foreach ($sec in $xml.SelectNodes("//DIV8[@TYPE='SECTION']")) {
    $n = $sec.GetAttribute('N')
    $encabezado = $sec.SelectSingleNode('HEAD').InnerText.Trim()
    # Las cursivas del XML (<I> y <E T="04">) marcan el titulo de cada inciso
    # -- "Standard", "General rule", "Elements". No son adorno: son la senal de
    # donde empieza cada unidad, y sirven para partir las secciones largas.
    $cuerpo = ($sec.SelectNodes('.//P') | ForEach-Object {
      $t = $_.InnerXml -replace '</?I>', '*' -replace '<E[^>]*>', '*' -replace '</E>', '*'
      [System.Net.WebUtility]::HtmlDecode($t).Trim()
    }) -join "`r`n`r`n"

    if ([string]::IsNullOrWhiteSpace($cuerpo)) { $vacias += $n }

    $md = @"
---
section: "$n"
citation: "45 CFR $n"
source: "https://www.ecfr.gov/current/title-45/section-$n"
title: "$($encabezado -replace '"', "'")"
retrieved: $fecha
---

## $encabezado

$cuerpo
"@
    $md | Out-File -FilePath (Join-Path $destino "$n.md") -Encoding utf8
    $total++
  }
}

Write-Output "$total secciones escritas en $destino"
if ($vacias.Count -gt 0) {
  Write-Output "Sin texto (reservadas o solo tablas): $($vacias -join ', ')"
}
