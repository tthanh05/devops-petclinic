# octopus/Deploy.ps1
$ErrorActionPreference = "Stop"

# --- Read vars that Jenkins passed to Octopus ---
$tag  = $OctopusParameters['ImageTag']
$port = $OctopusParameters['ServerPort']

Write-Host "== Petclinic Production Deploy via Octopus =="
Write-Host "ImageTag   : $tag"
Write-Host "ServerPort : $port"

if ([string]::IsNullOrWhiteSpace($tag)) {
  throw "ImageTag is empty. Ensure 'Substitute Variables in Files' is enabled for octopus\docker-compose.prod.yml and the deploy used --variable ImageTag=<value>."
}

# Compose file lives in the same 'octopus' folder as this script
$composePath = Join-Path $PSScriptRoot 'docker-compose.prod.yml'
if (-not (Test-Path $composePath)) { $composePath = 'docker-compose.prod.yml' }  # fallback if layout differs

Write-Host "Using compose file: $composePath"
Get-Content $composePath -TotalCount 30 | ForEach-Object { Write-Host $_ }

# --- Sanity info (optional) ---
docker --version
docker compose version

# --- Deploy ---
docker compose -f $composePath up -d --remove-orphans

# --- Health check (same URL your Jenkins gate uses, or service URL on the host) ---
$max = 150; $interval = 5; $ok = $false
$health = "http://localhost:$port/actuator/health"
Write-Host "Waiting up to $max sec for health at $health ..."
for ($t = 0; $t -lt $max; $t += $interval) {
  try {
    $resp = Invoke-WebRequest -Uri $health -UseBasicParsing -TimeoutSec 5
    if ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 300) { Write-Host "PROD health OK"; $ok = $true; break }
  } catch { Start-Sleep -Seconds $interval; continue }
  Start-Sleep -Seconds $interval
}
if (-not $ok) { throw "Octopus: PROD health check failed" }
