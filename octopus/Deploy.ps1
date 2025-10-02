# octopus/Deploy.ps1
# Force image tag + port safely using MatchEvaluator (no format strings),
# then deploy with a rendered compose file.

$ErrorActionPreference = "Stop"

Write-Host "== Petclinic Production Deploy via Octopus (safe regex) =="

# Isolate compose names for PROD
$env:COMPOSE_PROJECT_NAME = "octopus"

# Variables from Octopus (Jenkins passes via --variable)
$tag  = $OctopusParameters['ImageTag']
$port = $OctopusParameters['ServerPort']

Write-Host "Parameters received:"
Write-Host ("  ImageTag   = '{0}'" -f $tag)
Write-Host ("  ServerPort = '{0}'" -f $port)

if ([string]::IsNullOrWhiteSpace($tag))  { throw "ImageTag is empty." }
if ([string]::IsNullOrWhiteSpace($port)) { throw "ServerPort is empty." }

# Find base compose (inside the package)
$composeBase = Join-Path $PSScriptRoot 'docker-compose.prod.yml'
if (-not (Test-Path $composeBase)) { $composeBase = 'octopus\docker-compose.prod.yml' }
if (-not (Test-Path $composeBase)) { throw "Cannot find docker-compose.prod.yml in package." }

# Read file
$content = Get-Content -Raw -LiteralPath $composeBase

# --- Force image tag line:   image: "spring-petclinic:<ANY>"
$rxImage = [regex]::new('(?m)^(?<indent>\s*image:\s*"?spring-petclinic:)[^"\r\n]*("?)(\s*)$')
$content = $rxImage.Replace($content, { param($m)
    $m.Groups['indent'].Value + $tag + $m.Groups[2].Value + $m.Groups[3].Value
})

# --- Force host port mapping that targets container 8080:   - "<PORT>:8080"
$rxPort = [regex]::new('(?m)^(?<indent>\s*-\s*")\d{2,5}(:8080")')
$content = $rxPort.Replace($content, { param($m)
    $m.Groups['indent'].Value + $port + $m.Groups[2].Value
})

# Write rendered compose (temp)
$composeRendered = Join-Path $env:TEMP ("docker-compose.prod.rendered.{0}.yml" -f ([guid]::NewGuid()))
Set-Content -LiteralPath $composeRendered -Encoding UTF8 -Value $content

# Show what we'll use
Write-Host "Rendered compose key lines:"
Select-String -LiteralPath $composeRendered -Pattern '^\s*image:\s*"*spring-petclinic:','^\s*-\s*"\d{2,5}:8080"' | ForEach-Object { "  " + $_.Line }

# Guard: fail if it still binds the staging port
if (Select-String -LiteralPath $composeRendered -Pattern '^\s*-\s*"8085:8080"' -Quiet) {
  throw "Rendered compose is still binding 8085:8080 (staging port). Ensure this script runs AFTER any Octopus substitution step, or disable that step."
}

# Port-in-use check
function Test-PortInUse([int]$p) {
  try {
    $lines = docker ps --format '{{.Ports}}' 2>$null
    foreach ($ln in $lines) {
      if ($ln -match "0\.0\.0\.0:$p->" -or $ln -match "\[::\]:$p->") { return $true }
    }
    return $false
  } catch { return $false }
}
if (Test-PortInUse -p [int]$port) { throw "Host port $port is already in use. Free it or choose a different ServerPort." }

# Clean & deploy with rendered compose
docker compose -f $composeRendered down --remove-orphans
docker compose -f $composeRendered up -d

# Health gate
$healthUrl = "http://localhost:$port/actuator/health"
$max = 150; $step = 5; $ok = $false
Write-Host "Waiting up to $max sec for PROD health at $healthUrl ..."
for ($t=0; $t -lt $max; $t += $step) {
  try {
    $r = Invoke-WebRequest -Uri $healthUrl -UseBasicParsing -TimeoutSec 5
    if ($r.StatusCode -ge 200 -and $r.StatusCode -lt 300) { Write-Host "PROD Health OK (HTTP $($r.StatusCode))"; $ok = $true; break }
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

# Cleanup
try { Remove-Item -LiteralPath $composeRendered -Force -ErrorAction SilentlyContinue } catch {}
