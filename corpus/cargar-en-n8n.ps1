# Sends the downloaded sections to the RAG, one per call.
#
# The webhook answers when it has FINISHED indexing, not when it receives. That
# is what makes this loop genuinely sequential: two sections are never being
# vectorised at once, and the server sets the pace instead of the script. Ollama
# runs on CPU with no GPU here, and a client's workflows are in production
# alongside it.
#
# Neither the token nor the URL is written in this file, because this file gets
# published — and a published webhook URL is free attack surface even when it
# demands a token. Set both before running:
#   $env:RAG_N8N   = "https://your-n8n.example.com"
#   $env:RAG_TOKEN = "<the header-auth token you created in n8n>"

$ErrorActionPreference = 'Stop'

if (-not $env:RAG_N8N)   { throw 'Missing $env:RAG_N8N with the base URL of your n8n.' }
if (-not $env:RAG_TOKEN) { throw 'Missing $env:RAG_TOKEN. Set it before running this script.' }

$url = "$($env:RAG_N8N.TrimEnd('/'))/webhook/rag-cargar-seccion"
$headers = @{ 'X-Carga-Token' = $env:RAG_TOKEN }
$files = Get-ChildItem (Join-Path $PSScriptRoot 'secciones') -Filter *.md | Sort-Object Name

Write-Output "$($files.Count) sections to load"
$started = Get-Date
$ok = 0
$failures = @()
$i = 0

foreach ($file in $files) {
  $i++
  $raw = Get-Content $file.FullName -Raw -Encoding UTF8

  if ($raw -notmatch '(?s)^---\r?\n(.*?)\r?\n---\r?\n(.*)$') {
    $failures += "$($file.BaseName): no frontmatter"
    continue
  }
  $frontmatter = $Matches[1]
  $body = $Matches[2].Trim()

  # The heading is glued to its first paragraph on purpose. n8n's recursive
  # splitter cuts on blank lines first, so when the following block nearly fills
  # the chunk the ~70-character heading does not fit alongside it and ends up
  # alone: 77 of the 653 fragments of the first load were headings with no body.
  # Measured across the 148 sections, heading plus first paragraph tops out at
  # 984 characters, so they always fit in one chunk once the blank line is gone.
  # No section sign in the pattern: PowerShell 5.1 reads a BOM-less .ps1 as ANSI
  # and would mangle it. Every section file carries exactly one '##' heading.
  $body = $body -replace '(?m)^(##[^\r\n]*)\r?\n\s*\r?\n', "`$1`n"

  $meta = @{}
  foreach ($line in ($frontmatter -split "`r?`n")) {
    if ($line -match '^(\w+):\s*"?(.*?)"?\s*$') { $meta[$Matches[1]] = $Matches[2] }
  }

  $json = @{
    seccion   = $meta['section']
    citation  = $meta['citation']
    source    = $meta['source']
    retrieved = $meta['retrieved']
    texto     = $body
  } | ConvertTo-Json -Depth 3

  # PowerShell 5.1 sends the body as ISO-8859-1 when handed a string, and the
  # section sign would arrive mangled. Sent as explicit UTF-8 bytes instead.
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)

  try {
    Invoke-RestMethod -Uri $url -Method Post -Body $bytes -Headers $headers `
      -ContentType 'application/json; charset=utf-8' -TimeoutSec 600 | Out-Null
    $ok++
    Write-Output ("[{0,3}/{1}] {2}  ok" -f $i, $files.Count, $file.BaseName)
  }
  catch {
    $failures += "$($file.BaseName): $($_.Exception.Message)"
    Write-Output ("[{0,3}/{1}] {2}  FAILED" -f $i, $files.Count, $file.BaseName)
  }
}

$minutes = [math]::Round(((Get-Date) - $started).TotalMinutes, 1)
Write-Output ""
Write-Output "Loaded $ok of $($files.Count) in $minutes minutes"
if ($failures.Count -gt 0) {
  Write-Output "$($failures.Count) failed:"
  $failures | ForEach-Object { Write-Output "  $_" }
}
