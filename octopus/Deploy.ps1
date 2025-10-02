# Runs on the target host (Tentacle/SSH). Requires Docker + Compose v2 on the target.
$ErrorActionPreference = "Stop"

Write-Host "== Petclinic Production Deploy via Octopus =="
Write-Host "ImageTag: #{ImageTag}"
Write-Host "ServerPort: #{ServerPort}"

docker --version
docker compose version

# Bring up (or update) the production stack from the package contents
docker compose -f "docker-compose.prod.yml" up -d --remove-orphans

# Optional local health check (Octopus-side) — safe & quick
$prodUrl = "http://localhost:#{ServerPort}/actuator/health"
$max = 120; $interval = 5; $ok = $false
for ($t = 0; $t -lt $max; $t += $interval) {
  try {
    $resp = Invoke-WebRequest -Uri $prodUrl -UseBasicParsing -TimeoutSec 5
    if ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 300) { Write-Host "Octopus: PROD Health OK ($($resp.StatusCode))"; $ok = $true; break }
  } catch { Start-Sleep -Seconds $interval; continue }
  Start-Sleep -Seconds $interval
}
if (-not $ok) { throw "Octopus: PROD health check failed" }
