# Deploy max_bot to Linux VPS: push (optional) -> upload code -> rspec -> build -> restart
# Usage from repo root:
#   .\scripts\deploy-vps.ps1
#   .\scripts\deploy-vps.ps1 -SkipPush
#   .\scripts\deploy-vps.ps1 -SkipTests

param(
  [switch]$SkipPush,
  [switch]$SkipTests
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$envFile = Join-Path $repoRoot '.env.deploy'

if (-not (Test-Path $envFile)) {
  Write-Host "Create $envFile from env.deploy.example (DEPLOY_HOST, DEPLOY_USER, DEPLOY_PASSWORD)" -ForegroundColor Red
  exit 1
}

Get-Content $envFile | ForEach-Object {
  if ($_ -match '^\s*#' -or $_ -notmatch '^\s*([A-Za-z_][A-Za-z0-9_]*)=(.*)$') { return }
  $name = $matches[1]
  $value = $matches[2].Trim().Trim('"').Trim("'")
  Set-Item -Path "Env:$name" -Value $value
}

foreach ($key in @('DEPLOY_HOST', 'DEPLOY_PASSWORD')) {
  if ([string]::IsNullOrWhiteSpace((Get-Item "Env:$key" -ErrorAction SilentlyContinue).Value)) {
    throw "Missing $key in .env.deploy"
  }
}
if (-not $env:DEPLOY_USER) { $env:DEPLOY_USER = 'root' }

Set-Location $repoRoot

if (-not $SkipPush) {
  Write-Host '--- git push origin main ---' -ForegroundColor Cyan
  git push origin main
  if ($LASTEXITCODE -ne 0) { throw 'git push failed' }
} else {
  Write-Host '--- git push skipped ---' -ForegroundColor Yellow
}

$archive = Join-Path $env:TEMP "max_bot_deploy_$(Get-Date -Format 'yyyyMMdd_HHmmss').tgz"
Write-Host "--- git archive -> $archive ---" -ForegroundColor Cyan
git archive --format=tar.gz -o $archive HEAD
if ($LASTEXITCODE -ne 0) { throw 'git archive failed' }

Write-Host '--- upload archive ---' -ForegroundColor Cyan
$env:DEPLOY_LOCAL = $archive
$env:DEPLOY_REMOTE = '/root/code-deploy.tgz'
ruby (Join-Path $PSScriptRoot 'upload-migrate.rb')
if ($LASTEXITCODE -ne 0) { throw 'upload failed' }

Write-Host '--- deploy on server ---' -ForegroundColor Cyan
$skipTestsFlag = if ($SkipTests) { '1' } else { '0' }
$remote = @"
set -e
cd /opt/max_bot
tar -xzf /root/code-deploy.tgz
sed -i 's/\r$//' deploy/linux/deploy.sh
chmod +x deploy/linux/deploy.sh
SKIP_TESTS=$skipTestsFlag bash deploy/linux/deploy.sh
"@ -replace "`r", ''
ruby (Join-Path $PSScriptRoot 'ssh-run.rb') $remote
if ($LASTEXITCODE -ne 0) { throw 'remote deploy failed' }

Remove-Item $archive -Force -ErrorAction SilentlyContinue
Write-Host '--- done ---' -ForegroundColor Green
