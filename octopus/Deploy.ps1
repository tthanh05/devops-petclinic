# octopus/Deploy.ps1
# Safe production deploy: force image tag and host port by whole-line replacement,
# isolate compose project, validate port, and show rendered lines.

$ErrorActionPreference = "Stop"
Write-Host "== Petclinic Production Deploy via Octopus (stable render) =="

# Isolate production resources from staging
$env:COMPOSE_PROJECT_NAME = "octopus-prod"

# Inputs from Octopus/Jenkins
$rawTag  = $OctopusParameters['ImageTag']
$rawPort = $OctopusParameters['ServerPort']

Write-Host "Parameters received:"
Write-Host ("  ImageTag   = '{0}'" -f $rawTag)
Write-Host ("  ServerPort = '{0}'" -f $rawPort)

if ([string]::IsNullOrWhiteSpace($rawTag))  { throw "ImageTag is empty." }
if ([string]::IsNullOrWhiteSpace($rawPort)) { throw "ServerPort is empty." }

# Port: strip non-digits, then validate range
$portDigits = ($rawPort -replace '[^\d]', '')
[int]$portNum = 0
if (-not [int]::TryParse($portDigits, [ref]$portNum)) { throw "ServerPort '$rawPort' is not a valid integer." }
if ($portNum -lt 1 -or $portNum -gt 65535) { throw "ServerPort '$portNum' is out of range (1..65535)." }
$tag = "$rawTag"
$port = $portNum

# Locate compose template
$composeBase = Join-Path $PSScriptRoot 'docker-compose.prod.yml'
if (-not (Test-Path $composeBase)) { $composeBase = 'octopus\docker-compose.prod.yml' }
if (-not (Test-Path $composeBase)) { throw "Cannot find docker-compose.prod.yml in package." }

# Read and force the exact lines we care about
$content = Get-Content -Raw -LiteralPath $composeBase

# 1) Replace the entire app image line for spring-petclinic
$rxImage = [regex]::new('(?m)^(?<indent>\s*)image:\s*"?spring-petclinic:[^"\r\n]*"?\s*$')
if ($rxImage.IsMatch($content)) {
  $content = $rxImage.Replace($content, { param($m)
    $m.Groups['indent'].Value + 'image: "spring-petclinic:' + $tag + '"'
  })
}

# 2) Replace the entire host->container 8080 port mapping line
$rxPort = [regex]::new('(?m)^(?<indent>\s*)-\s*"?\d{2,5}:8080"?\s*$')
if ($rxPort.IsMatch($content)) {
  $content = $rxPort.Replace($content, { param($m)
    $m.Groups['indent'].Value + '- "' + $port + ':8080"'
  })
}

# Write rendered compose to a temp file
$composeRendered = Join-Path $env:TEMP ("docker-compose.prod.rendered.{0}.yml" -f ([guid]::NewGuid()))
Set-Content -LiteralPath $composeRendered -Encoding UTF8 -Value $content

# Show what we will deploy (evidence for rubric)
Write-Host "Rendered compose key lines:"
Select-String -LiteralPath $composeRendered -Pattern '^\s*image:\s*"spring-petclinic:','^\s*-\s*"\d{2,5}:8080"' | ForEach-Object { "  " + $_.Line }

# Guard: we must not bind staging port 8085
if (Select-String -LiteralPath $composeRendered -Pattern '^\s*-\s*"8085:8080"' -Quiet) {
  throw "Rendered compose still binds 8085:8080 (staging)."
}

# Port-in-use check
function Test-PortInUse {
  param([Parameter(Mandatory=$true)][string]$p)
  $pDigits = ($p -replace '[^\d]', '')
  try {
    $lines = docker ps --format '{{.Ports}}' 2>$null
    foreach ($ln in $lines) {
      if ($ln -match "0\.0\.0\.0:$pDigits->" -or $ln -match "\[::\]:$pDigits->") { return $true }
    }
    return $false
  } catch { return $false }
}
if (Test-PortInUse -p "$port") { throw "Host port $port is already in use. Free it or choose a different ServerPort." }

# Deploy
try { docker compose -f $composeRendered down --remove-orphans | Out-Null } catch { }
docker compose -f $composeRendered up -d

# Health gate on chosen port + helpful logs if it fails
$healthUrl = "http://localhost:$port/actuator/health"
$max = 150; $step = 5; $ok = $false
Write-Host "Waiting up to $max sec for PROD health at $healthUrl ..."
Start-Sleep -Seconds 5
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
    $appName = (docker compose -f $composeRendered ps --format json | ConvertFrom-Json | Where-Object { $_.Service -eq 'app' } | Select-Object -First 1 -ExpandProperty Name)
    if ($appName) {
      Write-Host "`n==== docker logs $appName (last 200) ===="
      docker logs --tail 200 $appName
      Write-Host "==== end logs ====`n"
    }
  } catch {}
  throw "Octopus: PROD health check failed"
}

# Cleanup temp file
try { Remove-Item -LiteralPath $composeRendered -Force -ErrorAction SilentlyContinue } catch {}
