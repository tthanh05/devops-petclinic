# octopus/Deploy.ps1

$ErrorActionPreference = "Stop"

Write-Host "== Petclinic Production Deploy via Octopus (safe render) =="

# 0) Isolate prod compose names (prevents collisions with staging)
$env:COMPOSE_PROJECT_NAME = "octopus-prod"

# 1) Inputs from Octopus/Jenkins
#    Jenkins sends: --variable="ImageTag=%VERSION%" --variable="ServerPort=8086"
$rawTag  = $OctopusParameters['ImageTag']
$rawPort = $OctopusParameters['ServerPort']

Write-Host "Parameters received:"
Write-Host ("  ImageTag   = '{0}'" -f $rawTag)
Write-Host ("  ServerPort = '{0}'" -f $rawPort)

if ([string]::IsNullOrWhiteSpace($rawTag))  { throw "ImageTag is empty." }
if ([string]::IsNullOrWhiteSpace($rawPort)) { throw "ServerPort is empty." }

# 1a) Sanitize/validate port (strip non-digits, then TryParse)
$portDigits = ($rawPort -replace '[^\d]', '')
[int]$portNum = 0
if (-not [int]::TryParse($portDigits, [ref]$portNum)) {
  throw "ServerPort '$rawPort' is not a valid integer."
}
if ($portNum -lt 1 -or $portNum -gt 65535) {
  throw "ServerPort '$portNum' is out of valid range (1-65535)."
}
$tag = "$rawTag"
$port = $portNum

# 2) Locate the base compose file from the package
$composeBase = Join-Path $PSScriptRoot 'docker-compose.prod.yml'
if (-not (Test-Path $composeBase)) { $composeBase = 'octopus\docker-compose.prod.yml' }
if (-not (Test-Path $composeBase)) { throw "Cannot find docker-compose.prod.yml in package." }

# 3) Read & FORCE image tag and host port (regardless of prior substitution)
$content = Get-Content -Raw -LiteralPath $composeBase

# --- Force image tag: lines like    image: "spring-petclinic:<ANY>"
$rxImage = [regex]::new('(?m)^(?<indent>\s*image:\s*"?spring-petclinic:)[^"\r\n]*("?)(\s*)$')
$content = $rxImage.Replace($content, { param($m)
  $m.Groups['indent'].Value + $tag + $m.Groups[2].Value + $m.Groups[3].Value
})

# --- Force host port mapping to container 8080.
# Handle double-quoted, single-quoted, or unquoted variants:
#   - "8085:8080"
#   - '8085:8080'
#   - 8085:8080
$rxPortDq = [regex]::new('(?m)^(?<indent>\s*-\s*")\d{2,5}(:8080"\s*)$')
$content = $rxPortDq.Replace($content, { param($m)
  $m.Groups['indent'].Value + $port + $m.Groups[2].Value
})
$rxPortSq = [regex]::new("(?m)^(?<indent>\s*-\s*')\d{2,5}(:8080'\s*)$")
$content = $rxPortSq.Replace($content, { param($m)
  $m.Groups['indent'].Value + $port + $m.Groups[2].Value
})
$rxPortNq = [regex]::new('(?m)^(?<indent>\s*-\s*)\d{2,5}(:8080\s*)$')
$content = $rxPortNq.Replace($content, { param($m)
  $m.Groups['indent'].Value + $port + $m.Groups[2].Value
})

# 4) Write a temporary rendered compose
$composeRendered = Join-Path $env:TEMP ("docker-compose.prod.rendered.{0}.yml" -f ([guid]::NewGuid()))
Set-Content -LiteralPath $composeRendered -Encoding UTF8 -Value $content

# 5) Show exactly what will be used (for audit/rubric)
Write-Host "Rendered compose key lines:"
Select-String -LiteralPath $composeRendered -Pattern '^\s*image:\s*"*spring-petclinic:','^\s*-\s*"?\d{2,5}:8080' | ForEach-Object { "  " + $_.Line }

# 6) Guardrail: fail if it still binds 8085 (staging)
if (Select-String -LiteralPath $composeRendered -Pattern '^\s*-\s*"*8085:8080' -Quiet) {
  throw "Rendered compose still binds 8085:8080 (staging). Ensure this script runs AFTER any Octopus substitution step, or disable that step."
}

# 7) Port-in-use check (robust/typeless)
function Test-PortInUse {
  param([Parameter(Mandatory=$true)][string]$p)
  $pDigits = ($p -replace '[^\d]', '')
  if (-not [int]::TryParse($pDigits, [ref]([int]$null))) { return $false }
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

# 8) Clean & deploy
docker compose -f $composeRendered down --remove-orphans
docker compose -f $composeRendered up -d

# 9) Health gate
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

# 10) Cleanup
try { Remove-Item -LiteralPath $composeRendered -Force -ErrorAction SilentlyContinue } catch {}
