# octopus/Deploy.ps1
# Robust deploy: performs its own token substitution and checks port availability.

$ErrorActionPreference = "Stop"

# 1) Variables from Octopus (from Jenkins we pass --variable ImageTag=... --variable ServerPort=8086)
$tag  = $OctopusParameters['ImageTag']
$port = $OctopusParameters['ServerPort']

Write-Host "== Petclinic Production Deploy via Octopus =="
Write-Host "ImageTag   : $tag"
Write-Host "ServerPort : $port"

if ([string]::IsNullOrWhiteSpace($tag)) {
  throw "ImageTag is empty. Ensure Jenkins passes --variable ImageTag=<value> to Octopus."
}
if (-not $port) {
  throw "ServerPort is empty. Ensure Jenkins passes --variable ServerPort=8086 (or set a project variable scoped to Production)."
}

# 2) Locate base compose file and render a temp copy with tokens replaced
$composeBase = Join-Path $PSScriptRoot 'docker-compose.prod.yml'
if (-not (Test-Path $composeBase)) { $composeBase = 'octopus\docker-compose.prod.yml' }
if (-not (Test-Path $composeBase)) { throw "Cannot find docker-compose.prod.yml" }

$composeRendered = Join-Path $env:TEMP ("docker-compose.prod.rendered.{0}.yml" -f ([guid]::NewGuid()))
Write-Host "Base compose : $composeBase"
Write-Host "Rendered file: $composeRendered"

# Do a simple, safe token replacement for #{ImageTag} and #{ServerPort}
(Get-Content -Raw -LiteralPath $composeBase) `
  -replace '#{ImageTag}',   [Regex]::Escape($tag) `
  -replace '#{ServerPort}', [Regex]::Escape($port) `
  | Set-Content -LiteralPath $composeRendered -Encoding UTF8

# 3) Check whether $port is already bound on the host
function Test-PortInUse([int]$p) {
  try {
    $lines = docker ps --format '{{.Ports}}' 2>$null
    if ($LASTEXITCODE -ne 0) { return $false } # if Docker not running, don't block here
    foreach ($ln in $lines) {
      if ($ln -match "0\.0\.0\.0:$p->" -or $ln -match "\[::\]:$p->") { return $true }
    }
    return $false
  } catch { return $false }
}

if (Test-PortInUse -p $port) {
  Write-Error "Host port $port is already in use. Staging uses 8085; Production should use 8086. Free the port or set a different ServerPort."
  throw "Port $port is in use"
}

# 4) Clean slate to avoid orphan conflicts within this project
docker compose -f $composeRendered down --remove-orphans

# 5) Bring the stack up (will use the rendered port and tag)
docker compose -f $composeRendered up -d

# 6) Health gate against the running app
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
  Write-Warning "Health check failed. Capturing diagnostics..."
  try {
    docker compose -f $composeRendered ps
    docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
  } catch {}
  throw "Octopus: PROD health check failed"
}

# 7) Cleanup temp file
try { Remove-Item -LiteralPath $composeRendered -Force -ErrorAction SilentlyContinue } catch {}
