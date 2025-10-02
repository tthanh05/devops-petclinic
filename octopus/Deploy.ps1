# octopus/Deploy.ps1
# Runs on the Windows target (Tentacle). It deploys/refreshes the compose stack cleanly.

$ErrorActionPreference = "Stop"

# 1) Variables from Octopus
$tag  = $OctopusParameters['ImageTag']
$port = $OctopusParameters['ServerPort']

Write-Host "== Petclinic Production Deploy via Octopus =="
Write-Host "ImageTag   : $tag"
Write-Host "ServerPort : $port"

if ([string]::IsNullOrWhiteSpace($tag)) {
  throw "ImageTag is empty. Ensure 'Substitute Variables in Files' includes octopus\docker-compose.prod.yml and that Jenkins passed --variable ImageTag=<value>."
}

# 2) Locate compose file (we ship it in the octopus/ folder)
$composePath = Join-Path $PSScriptRoot 'docker-compose.prod.yml'
if (-not (Test-Path $composePath)) { $composePath = 'octopus\docker-compose.prod.yml' }

Write-Host "Using compose file: $composePath"

# 3) Clean slate to avoid "name already in use" conflicts
docker compose -f $composePath down --remove-orphans

# 4) Bring the stack up
docker compose -f $composePath up -d

# 5) Simple health gate against the running app
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
    docker compose -f $composePath ps
    docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
  } catch {}

  throw "Octopus: PROD health check failed"
}
