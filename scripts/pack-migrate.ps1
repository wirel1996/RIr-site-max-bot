# Pack secrets and data for VPS migration (do not commit the zip).
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$out = Join-Path $root 'migrate-pack.zip'
$staging = Join-Path $env:TEMP "max_bot_migrate_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
New-Item -ItemType Directory -Path $staging -Force | Out-Null

function Copy-IfExists($src, $dstDir) {
  if (Test-Path $src) {
    Copy-Item $src -Destination $dstDir -Force
  }
}

Copy-IfExists (Join-Path $root '.env') $staging
$dataDir = Join-Path $staging 'storage'
New-Item -ItemType Directory -Path $dataDir -Force | Out-Null

Get-ChildItem (Join-Path $root 'storage') -File -Filter '*.db' -ErrorAction SilentlyContinue | ForEach-Object {
  Copy-Item $_.FullName -Destination $dataDir -Force
}
@(
  'users.json', 'session_secret', 'app_settings.json',
  'journal_index.json', 'journal_notify_state.json', 'short_links.json'
) | ForEach-Object {
  Copy-IfExists (Join-Path $root "storage\$_") $dataDir
}

if (Test-Path $out) { Remove-Item $out -Force }
Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $out -Force
Remove-Item $staging -Recurse -Force
Write-Host "Created: $out"
Get-Item $out | Select-Object FullName, Length
