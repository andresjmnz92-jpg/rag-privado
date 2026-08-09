# Manda al RAG las secciones descargadas, una por llamada.
#
# El webhook responde cuando TERMINA de indexar, no al recibir. Por eso el bucle
# es secuencial de verdad: nunca hay dos secciones vectorizandose a la vez, y el
# ritmo lo marca el servidor. Ollama corre en CPU sin GPU, y al lado hay
# workflows de un cliente en produccion.
#
# Ni el token ni la URL van escritos aqui: este archivo se publica, y una URL de
# webhook publicada es superficie regalada aunque exija token. Antes de correr:
#   $env:RAG_N8N   = "https://tu-n8n.ejemplo.com"
#   $env:RAG_TOKEN = "<el valor de la credencial RAG Carga>"

$ErrorActionPreference = 'Stop'

if (-not $env:RAG_N8N)   { throw 'Falta $env:RAG_N8N con la URL base de tu n8n.' }
if (-not $env:RAG_TOKEN) { throw 'Falta $env:RAG_TOKEN. Ponlo antes de correr este script.' }

$url = "$($env:RAG_N8N.TrimEnd('/'))/webhook/rag-cargar-seccion"
$cabeceras = @{ 'X-Carga-Token' = $env:RAG_TOKEN }
$archivos = Get-ChildItem (Join-Path $PSScriptRoot 'secciones') -Filter *.md | Sort-Object Name

Write-Output "$($archivos.Count) secciones por cargar"
$inicio = Get-Date
$ok = 0
$fallos = @()
$i = 0

foreach ($a in $archivos) {
  $i++
  $crudo = Get-Content $a.FullName -Raw -Encoding UTF8

  if ($crudo -notmatch '(?s)^---\r?\n(.*?)\r?\n---\r?\n(.*)$') {
    $fallos += "$($a.BaseName): sin frontmatter"
    continue
  }
  $frontmatter = $Matches[1]
  $cuerpo = $Matches[2].Trim()

  $meta = @{}
  foreach ($linea in ($frontmatter -split "`r?`n")) {
    if ($linea -match '^(\w+):\s*"?(.*?)"?\s*$') { $meta[$Matches[1]] = $Matches[2] }
  }

  $json = @{
    seccion   = $meta['section']
    citation  = $meta['citation']
    source    = $meta['source']
    retrieved = $meta['retrieved']
    texto     = $cuerpo
  } | ConvertTo-Json -Depth 3

  # PowerShell 5.1 manda el cuerpo en ISO-8859-1 si se le pasa como texto, y el
  # simbolo § llegaria corrupto. Se manda como bytes UTF-8 explicitos.
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)

  try {
    Invoke-RestMethod -Uri $url -Method Post -Body $bytes -Headers $cabeceras `
      -ContentType 'application/json; charset=utf-8' -TimeoutSec 600 | Out-Null
    $ok++
    Write-Output ("[{0,3}/{1}] {2}  ok" -f $i, $archivos.Count, $a.BaseName)
  }
  catch {
    $fallos += "$($a.BaseName): $($_.Exception.Message)"
    Write-Output ("[{0,3}/{1}] {2}  FALLO" -f $i, $archivos.Count, $a.BaseName)
  }
}

$minutos = [math]::Round(((Get-Date) - $inicio).TotalMinutes, 1)
Write-Output ""
Write-Output "Cargadas $ok de $($archivos.Count) en $minutos minutos"
if ($fallos.Count -gt 0) {
  Write-Output "Fallaron $($fallos.Count):"
  $fallos | ForEach-Object { Write-Output "  $_" }
}
