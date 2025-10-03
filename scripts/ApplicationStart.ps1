$ErrorActionPreference = "Stop"

# Read variables produced by Jenkins (shipped in bundle)
#   IMAGE_TAG=<version>   e.g., 91-6498b93
#   SERVER_PORT=8086
$envFile = "release.env"
$vars = @{}
if (Test-Path $envFile) {
  Get-Content $envFile | ForEach-Object {
    if ($_ -match '^\s*([^#=]+?)\s*=\s*(.+?)\s*$') { $vars[$matches[1]] = $matches[2] }
  }
}

$tag  = $vars['IMAGE_TAG']
$port = if ($vars['SERVER_PORT']) { $vars['SERVER_PORT'] } else { "8086" }
if ([string]::IsNullOrWhiteSpace($tag)) { throw "IMAGE_TAG missing in release.env" }

# Render compose to pin the exact image tag and host port
$src = "docker-compose.prod.yml"
if (-not (Test-Path $src)) { throw "Missing $src" }

$yml = Get-Content -Raw -LiteralPath $src

# Replace image: spring-petclinic:*
$yml = [regex]::Replace(
  $yml,
  '^(?<i>\s*image:\s*")spring-petclinic:[^"]*(".*)$',
  { param($m) $m.Groups['i'].Value + "spring-petclinic:$tag" + $m.Groups[2].Value },
  [Text.RegularExpressions.RegexOptions]::Multiline
)

# Replace host port mapping (e.g., "8086:8080")
$yml = [regex]::Replace(
  $yml,
  '^(?<i>\s*-\s*")\d{2,5}(:8080".*)$',
  { param($m) $m.Groups['i'].Value + "$port" + $m.Groups[2].Value },
  [Text.RegularExpressions.RegexOptions]::Multiline
)

$tmp = Join-Path $env:TEMP ("prod.rendered.{0}.yml" -f ([guid]::NewGuid()))
Set-Content -LiteralPath $tmp -Encoding UTF8 -Value $yml

docker compose -p "petclinic-prod" -f $tmp up -d --remove-orphans
