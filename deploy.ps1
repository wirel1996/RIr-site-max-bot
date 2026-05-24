# Тесты (RSpec), сборка фронтенда и перезапуск сервисов сайта.
# Запуск из PowerShell от имени администратора:
#   C:\max_bot\deploy.ps1

$ErrorActionPreference = 'Stop'

$script = Join-Path $PSScriptRoot 'web-frontend\build-and-deploy.ps1'
& $script
