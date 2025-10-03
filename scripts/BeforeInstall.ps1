# Stop and clean any old prod stack (idempotent)
$ErrorActionPreference = "Stop"

docker --version     | Out-Null
docker compose version | Out-Null

$compose = "docker-compose.prod.yml"
$proj    = "petclinic-prod"

try {
  docker compose -p $proj -f $compose down --remove-orphans | Out-Null
} catch {
  Write-Host "compose down failed (probably nothing running): $($_.Exception.Message)"
}
