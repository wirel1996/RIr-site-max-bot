#!/bin/bash
set -euo pipefail

APP_ROOT=/opt/max_bot
export DEBIAN_FRONTEND=noninteractive

timedatectl set-timezone Asia/Novosibirsk || true

apt-get update -qq
apt-get install -y -qq curl unzip build-essential sqlite3 libsqlite3-dev \
  fonts-dejavu-core ca-certificates gnupg apt-transport-https \
  ruby ruby-dev zip

gem install bundler --no-document

if ! command -v node >/dev/null 2>&1; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y -qq nodejs
fi

if ! command -v caddy >/dev/null 2>&1; then
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
  apt-get update -qq
  apt-get install -y -qq caddy
fi

mkdir -p "$APP_ROOT"
find "$APP_ROOT" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
tar -xzf /root/code-pack.tgz -C "$APP_ROOT"

if [[ -f /root/migrate-pack.zip ]]; then
  rm -rf /root/migrate_unpack
  unzip -o /root/migrate-pack.zip -d /root/migrate_unpack
  [[ -f /root/migrate_unpack/.env ]] && cp /root/migrate_unpack/.env "$APP_ROOT/.env"
  if [[ -d /root/migrate_unpack/storage ]]; then
    mkdir -p "$APP_ROOT/storage"
    cp -a /root/migrate_unpack/storage/. "$APP_ROOT/storage/"
  fi
fi

mkdir -p "$APP_ROOT/log" "$APP_ROOT/caddy/data" "$APP_ROOT/cache"

cd "$APP_ROOT"
bundle config set --local deployment 'true'
bundle config set --local without 'development'
bundle install --jobs 4

cd "$APP_ROOT/web-frontend"
npm ci
npm run build

cp "$APP_ROOT/deploy/linux/Caddyfile" /etc/caddy/Caddyfile
cp "$APP_ROOT/deploy/linux/maxbot.service" /etc/systemd/system/
cp "$APP_ROOT/deploy/linux/maxbot-web.service" /etc/systemd/system/

systemctl daemon-reload
systemctl enable maxbot maxbot-web caddy
systemctl restart maxbot-web
sleep 2
systemctl restart maxbot
systemctl restart caddy

systemctl is-active maxbot maxbot-web caddy
curl -sS -o /dev/null -w 'local_api=%{http_code}\n' http://127.0.0.1:4567/api/health || true

echo "INSTALL_OK"
