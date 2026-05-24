$ErrorActionPreference = 'Stop'

$env:PATH = [System.Environment]::GetEnvironmentVariable('PATH','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('PATH','User')
$repoRoot = Split-Path -Parent $PSScriptRoot

Write-Host '--- bundle install (backend gems) ---' -ForegroundColor Cyan
Set-Location $repoRoot
bundle install
if ($LASTEXITCODE -ne 0) { throw 'bundle install failed' }

Write-Host '--- bundle exec rspec ---' -ForegroundColor Cyan
bundle exec rspec
if ($LASTEXITCODE -ne 0) { throw 'rspec failed' }

Write-Host '--- npm run build ---' -ForegroundColor Cyan
Set-Location (Join-Path $PSScriptRoot '')
npm run build
if ($LASTEXITCODE -ne 0) { throw 'build failed' }

Write-Host '--- restarting MaxBotWeb (API/Ruby) ---' -ForegroundColor Cyan
Restart-Service MaxBotWeb

Write-Host '--- restarting CaddyContacts (serves dist) ---' -ForegroundColor Cyan
Restart-Service CaddyContacts

Write-Host '--- restarting MaxBot ---' -ForegroundColor Cyan
Restart-Service MaxBot

Write-Host '--- done ---' -ForegroundColor Green
