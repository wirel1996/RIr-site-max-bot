#!/bin/bash
# Run on VPS after code archive is extracted into /opt/max_bot
set -euo pipefail

ROOT=/opt/max_bot
cd "$ROOT"

echo '--- bundle install ---'
bundle config set --local deployment 'true'
bundle config set --local without 'development'
bundle install --jobs 4

if [[ "${SKIP_TESTS:-0}" != "1" ]]; then
  echo '--- bundle exec rspec ---'
  bundle exec rspec
else
  echo '--- rspec skipped (SKIP_TESTS=1) ---'
fi

echo '--- npm run build ---'
cd "$ROOT/web-frontend"
npm ci
npm run build
chmod -R a+rX dist

echo '--- restart services ---'
systemctl restart maxbot-web
sleep 2
systemctl restart maxbot
systemctl restart caddy

echo '--- health check ---'
curl -sf http://127.0.0.1:4567/api/health >/dev/null
echo 'DEPLOY_OK'
