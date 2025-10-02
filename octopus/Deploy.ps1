# == Petclinic Production Deploy via Octopus ==
param()

$ErrorActionPreference = 'Stop'

# Values injected by Octopus variable substitution
$ImageTag   = "#{ImageTag}"
$ServerPort = "#{ServerPort}"

# Resolve compose file relative to this script
$compose = Join-Path $PSScriptRoot 'docker-compose.prod.yml'

if (-not (Test-Path $compose)) {
  throw "Compose file not found at: $compose"
}

Write-Host "== Petclinic Production Deploy via Octopus =="
Write-Host "ImageTag:   $ImageTag"
Write-Host "ServerPort: $ServerPort"

docker version
docker compose version

# Deploy/update the stack
Write-Host "Bringing up stack from $compose ..."
docker compose -f "$compose" up -d --remove-orphans

# Health gate against the app actuator on the host-exposed port
$healthUrl = "http://localhost:$ServerPort/actuator/health"
$max = 150      # seconds
$interval = 5   # seconds
$ok = $false

Write-Host "Waiting up to $max sec for health at $healthUrl ..."
for ($t = 0; $t -lt $max; $t += $interval) {
  try {
    $resp = Invoke-WebRequest -Uri $healthUrl -UseBasicParsing -TimeoutSec 5
    if ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 300) {
      Write-Host "Health OK (HTTP $($resp.StatusCode))"
      $ok = $true
      break
    }
  } catch {
    # keep waiting
  }
  Start-Sleep -Seconds $interval
}

if (-not $ok) {
  throw "Octopus: PROD health check failed"
}

Write-Host "== Deployment complete =="
