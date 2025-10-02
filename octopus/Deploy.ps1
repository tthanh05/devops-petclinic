# octopus/Deploy.ps1

$ErrorActionPreference = "Stop"

# 1) Read variables provided by Octopus/Jenkins
$tag  = $OctopusParameters['ImageTag']
$port = $OctopusParameters['ServerPort']

Write-Host "== Petclinic Production Deploy via Octopus =="
Write-Host "ImageTag   : $tag"
Write-Host "ServerPort : $port"

if ([string]::IsNullOrWhiteSpace($tag)) { throw "ImageTag is empty." }

# 2) Locate the compose file (we packed it under octopus/)
$composePath = Join-Path $PSScriptRoot 'docker-compose.prod.yml'
if (-not (Test-Path $composePath)) { $composePath = 'docker-compose.prod.yml' }

Write-Host "Using: $composePath"

# --- CLEANUP (your question) ---
# If you kept fixed container_name values
# docker rm -f petclinic-db 2>$null
# docker rm -f petclinic-app 2>$null

# (Optional, safer if you didn’t keep container_name)
docker compose -f $composePath down --remove-orphans

# 3) Bring the stack up
docker compose -f $composePath up -d

# 4) Simple health gate (optional)
$healthUrl = "http://localhost:$port/actuator/health"
$max = 150; $step = 5; $ok = $false
for ($t=0; $t -lt $max; $t += $step) {
  try {
    $r = Invoke-WebRequest -Uri $healthUrl -UseBasicParsing -TimeoutSec 5
    if ($r.StatusCode -ge 200 -and $r.StatusCode -lt 300) { Write-Host "Health OK"; $ok = $true; break }
  } catch { Start-Sleep -Seconds $step; continue }
  Start-Sleep -Seconds $step
}
if (-not $ok) { throw "Octopus: PROD health check failed" }
