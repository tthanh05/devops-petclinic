$ErrorActionPreference = "Stop"

$proj = "petclinic-prod"
$port = [int]($env:SERVER_PORT ?? 8086)
$url  = "http://localhost:$port/actuator/health"
$max  = 180
$int  = 5

Start-Sleep -Seconds 5

$ok = $false
Write-Host "Waiting up to $max sec for PROD health at $url ..."
for ($t=0; $t -lt $max; $t += $int) {
  try {
    $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 5
    if ($r.StatusCode -ge 200 -and $r.StatusCode -lt 300) { 
      Write-Host "PROD Health OK (HTTP $($r.StatusCode))"
      $ok = $true; break
    }
  } catch {
    Start-Sleep -Seconds $int; continue
  }
  Start-Sleep -Seconds $int
}

if (-not $ok) {
  Write-Warning "Health check failed. Capturing diagnostics..."
  try { docker compose -p $proj -f "docker-compose.prod.yml" ps } catch {}

  # Try to print last 200 lines of app logs
  try {
    $appName = (docker ps --format "{{.Names}}" | Select-String "$proj.*app" | Select-Object -First 1).Line
    if ($appName) {
      Write-Host "`n==== docker logs $appName (tail 200) ===="
      docker logs --tail 200 $appName
      Write-Host "==== end logs ====`n"
    }
  } catch {}

  throw "CodeDeploy validation failed"
}
