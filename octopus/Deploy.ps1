# octopus/Deploy.ps1
# Safe production deploy: force image tag and host port with whole-line replacements,
# isolate compose project, validate port, and show rendered lines.

$ErrorActionPreference = "Stop"

Write-Host "== Petclinic Production Deploy via Octopus (stable render) =="

# Isolate production resources from staging
$env:COMPOSE_PROJECT_NAME = "octopus-prod"

# --- Inputs from Octopus/Jenkins ---
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

# --- Locate compose template in the package ---
$composeBase = Join-Path $PSScriptRoot 'docker-compose.prod.yml'
if (-not (Test-Path $composeBase)) { $composeBase = 'octopus\docker-compose.prod.yml' }
if (-not (Test-Path $composeBase)) { throw "Cannot find docker-compose.prod.yml in package." }

# --- Read, then FORCE whole lines we care about ---
$content = Get-Content -Raw -LiteralPath $composeBase

# 1) App image line: replace the entire line for spring-petclinic (do not touch mysql)
$rxImage = [regex]::new('(?m)^(?<indent>\s*)image:\s*"?spring-petclinic:[^"\r\n]*"?\s*$')
if ($rxImage.IsMatch($content)) {
  $content = $rxImage.Replace($content, { param($m)
    $m.Groups['indent'].Value + 'image: "spring-petclinic:' + $tag + '"'
  })
}

# 2) Port mapping to container 8080: replace the entire mapping line, preserve indent
#    Handles quoted or unquoted variants.
$rxPort = [regex]::new('(?m)^(?<indent>\s*)-\s*"?\d{2,5}:8080"?\s*$')
if ($rxPort.IsMatch($content)) {
  $content = $rxPort.Replace($content, { param($m)
    $m.Groups['indent'].Value + '- "' + $port + ':8080"'
  })
}

# --- Write rendered compose to a temp file ---
$composeRendered = Join-Path $env:TEMP ("docker-compose.prod.rendered.{0}.yml" -f ([guid]::NewGuid()))
Set-Content -LiteralPath $composeRendered -Encoding UTF8 -Value $content

# --- Show exactly what we will deploy (audit/rubric evidence) ---
Write-Host "Rendered compose key lines:"
Select-String -LiteralPath $composeRendered -Pattern '^\s*image:\s*"spring-petclinic:','^\s*-\s*"\d{2,5}:8080"' | ForEach-Object { "  " + $_.Line }

# --- Guard: ensure we are not binding staging port 8085 ---
if (Select-String -LiteralPath $composeRendered -Pattern '^\s*-\s*"8085:8080"' -Quiet) {
  throw "Rendered compose still binds 8085:8080 (staging). Ensure this script runs after any Octopus substitution step, or disable that step."
}

# --- Check if chosen host port is already bound ---
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
if (Test-PortInUse -p "$port") {
  throw "Host port $port is already in use. Free it or choose a different ServerPort."
}

# --- Deploy (ignore warning if nothing to remove on first run) ---
try { docker compose -f $composeRendered down --remove-orphans | Out-Null } catch { Write-Warning $_ }
docker compose -f $composeRendered up -d

# --- Health gate on the chosen port ---
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

# --- Cleanup temp file ---
try { Remove-Item -LiteralPath $composeRendered -Force -ErrorAction SilentlyContinue } catch {}
