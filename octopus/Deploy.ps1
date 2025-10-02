# octopus/Deploy.ps1
# Robust deploy: renders compose with our variables, validates port, and shows what's used.

$ErrorActionPreference = "Stop"

Write-Host "== Petclinic Production Deploy via Octopus (Deploy.ps1 running) =="

# 0) Force a distinct compose project for prod to avoid name collisions with staging
$env:COMPOSE_PROJECT_NAME = "octopus"

# 1) Read variables coming from Octopus/Jenkins
$tag  = $OctopusParameters['ImageTag']
$port = $OctopusParameters['ServerPort']

Write-Host "Parameters received:"
Write-Host ("  ImageTag   = '{0}'" -f $tag)
Write-Host ("  ServerPort = '{0}'" -f $port)

if ([string]::IsNullOrWhiteSpace($tag)) { throw "ImageTag is empty. Jenkins must pass --variable ImageTag=<value>." }
if ([string]::IsNullOrWhiteSpace($port)) { throw "ServerPort is empty. Jenkins must pass --variable ServerPort=8086 (or set a Project variable scoped to Production)." }

# 2) Locate the source compose file (from package contents)
$composeBase = Join-Path $PSScriptRoot 'docker-compose.prod.yml'
if (-not (Test-Path $composeBase)) { $composeBase = 'octopus\docker-compose.prod.yml' }
if (-not (Test-Path $composeBase)) { throw "Cannot find docker-compose.prod.yml in package." }

# 3) Render a temp compose with tokens replaced (independent of Octopus substitution)
$composeRendered = Join-Path $env:TEMP ("docker-compose.prod.rendered.{0}.yml" -f ([guid]::NewGuid()))
(Get-Content -Raw -LiteralPath $composeBase) `
  -replace '#{ImageTag}',   [System.Text.RegularExpressions.Regex]::Escape($tag) `
  -replace '#{ServerPort}', [System.Text.RegularExpressions.Regex]::Escape($port) `
  | Set-Content -LiteralPath $composeRendered -Encoding UTF8

# Show the lines we care about (for debugging)
Write-Host "Rendered compose key lines:"
Select-String -LiteralPath $composeRendered -Pattern '^ *image:','^ *ports:' -SimpleMatch | ForEach-Object { "  " + $_.Line } 

# 4) Guard: if the rendered file still contains '#{ServerPort}', fail
if (Select-String -LiteralPath $composeRendered -Pattern '#{ServerPort}' -Quiet) {
  throw "Token substitution failed: '#{ServerPort}' still present in rendered compose."
}

# 5) If the rendered file ended up with 8085, fail fast (we expect 8086 for prod)
if (Select-String -LiteralPath $composeRendered -Pattern '^\s*-\s*"8085:8080"' -Quiet) {
  throw "Rendered compose is binding 8085:8080 (staging port). Production must use 8086. Check which variables Octopus passed."
}

# 6) Check whether the chosen host port is already in use
function Test-PortInUse([int]$p) {
  try {
    $lines = docker ps --format '{{.Ports}}' 2>$null
    foreach ($ln in $lines) {
      if ($ln -match "0\.0\.0\.0:$p->" -or $ln -match "\[::\]:$p->") { return $true }
    }
    return $false
  } catch { return $false }
}
if (Test-PortInUse -p [int]$port) {
  throw "Host port $port is already in use. Staging is 8085; production should be 8086. Free the port or pick another."
}

# 7) Clean slate for this project, then bring up with rendered compose
docker compose -f $composeRendered down --remove-orphans
docker compose -f $composeRendered up -d

# 8) Health gate
$healthUrl = "http://localhost:$port/actuator/health"
$max = 150; $step = 5; $ok = $false
Write-Host "Waiting up to $max sec for PROD health at $healthUrl ..."
for ($t=0; $t -lt $max; $t += $step) {
  try {
    $r = Invoke-WebRequest -Uri $healthUrl -UseBasicParsing -TimeoutSec 5
    if ($r.StatusCode -ge 200 -and $r.StatusCode -lt 300) {
      Write-Host "PROD Health OK (HTTP $($r.StatusCode))"
      $ok = $true; break
    }
  } catch { Start-Sleep -Seconds $step; continue }
  Start-Sleep -Seconds $step
}

if (-not $ok) {
  Write-Warning "Health check failed. Diagnostics:"
  try {
    docker compose -f $composeRendered ps
    docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
  } catch {}
  throw "Octopus: PROD health check failed"
}

# 9) Cleanup temp file (best-effort)
try { Remove-Item -LiteralPath $composeRendered -Force -ErrorAction SilentlyContinue } catch {}
