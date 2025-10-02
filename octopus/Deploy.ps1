# octopus/Deploy.ps1
# Robust deploy: force image tag and host port regardless of prior substitutions.

$ErrorActionPreference = "Stop"

Write-Host "== Petclinic Production Deploy via Octopus (forced render) =="

# Distinct compose project name for PROD
$env:COMPOSE_PROJECT_NAME = "octopus"

# Variables coming from Octopus/Jenkins
$tag  = $OctopusParameters['ImageTag']
$port = $OctopusParameters['ServerPort']

Write-Host "Parameters received:"
Write-Host ("  ImageTag   = '{0}'" -f $tag)
Write-Host ("  ServerPort = '{0}'" -f $port)

if ([string]::IsNullOrWhiteSpace($tag))  { throw "ImageTag is empty." }
if ([string]::IsNullOrWhiteSpace($port)) { throw "ServerPort is empty." }

# Locate compose template (whatever Octopus unpacked)
$composeBase = Join-Path $PSScriptRoot 'docker-compose.prod.yml'
if (-not (Test-Path $composeBase)) { $composeBase = 'octopus\docker-compose.prod.yml' }
if (-not (Test-Path $composeBase)) { throw "Cannot find docker-compose.prod.yml in package." }

# Read and FORCE the values we want, regardless of earlier substitutions
$content = Get-Content -Raw -LiteralPath $composeBase

# 1) Force the image tag for spring-petclinic
#    Matches lines like: image: "spring-petclinic:XYZ"  (with or without quotes)
$content = [System.Text.RegularExpressions.Regex]::Replace(
  $content,
  '(?m)^(?<indent>\s*image:\s*"?spring-petclinic:)[^"\r\n]*("?)(\s*)$',
  ('${indent}{0}"$3' -f $tag)
)

# 2) Force any host port that maps to container 8080 to our desired $port
#    Matches lines like: - "8085:8080" or - "12345:8080"
$content = [System.Text.RegularExpressions.Regex]::Replace(
  $content,
  '(?m)^(?<indent>\s*-\s*")\d{2,5}(:8080")',
  ('${indent}{0}$2' -f $port)
)

# Write rendered temp compose
$composeRendered = Join-Path $env:TEMP ("docker-compose.prod.rendered.{0}.yml" -f ([guid]::NewGuid()))
Set-Content -LiteralPath $composeRendered -Encoding UTF8 -Value $content

# Show the exact lines we care about
Write-Host "Rendered compose key lines:"
Select-String -LiteralPath $composeRendered -Pattern '^\s*image:\s*"*spring-petclinic:','^\s*-\s*"\d{2,5}:8080"' | ForEach-Object { "  " + $_.Line }

# Guard: fail if it's still binding 8085 (staging)
if (Select-String -LiteralPath $composeRendered -Pattern '^\s*-\s*"8085:8080"' -Quiet) {
  throw "Rendered compose is still binding 8085:8080 (staging port). A prior Octopus step rewrote it; this script must run AFTER any substitution, or remove that step."
}

# Check if target host port is already in use
function Test-PortInUse([int]$p) {
  try {
    $lines = docker ps --format '{{.Ports}}' 2>$null
    foreach ($ln in $lines) {
      if ($ln -match "0\.0\.0\.0:$p->" -or $ln -match "\[::\]:$p->") { return $true }
    }
    return $false
  } catch { return $false }
}
if (Test-PortInUse -p [int]$port) { throw "Host port $port is already in use. Free it or choose another ServerPort." }

# Clean and deploy using the rendered file
docker compose -f $composeRendered down --remove-orphans
docker compose -f $composeRendered up -d

# Health gate on chosen port
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

# Best-effort cleanup
try { Remove-Item -LiteralPath $composeRendered -Force -ErrorAction SilentlyContinue } catch {}
