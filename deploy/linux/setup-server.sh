#!/bin/bash
set -euo pipefail

APP_ROOT=/opt/max_bot
REPO_URL="${REPO_URL:-https://github.com/wirel1996/RIr-site-max-bot.git}"

export DEBIAN_FRONTEND=noninteractive
timedatectl set-timezone Asia/Novosibirsk || true

apt-get update -qq
apt-get install -y -qq git curl unzip build-essential sqlite3 libsqlite3-dev \
  fonts-dejavu-core ca-certificates gnupg

# Ruby 3.3 from Ubuntu
apt-get install -y -qq ruby ruby-dev
gem install bundler --no-document

# Node.js 22
if ! command -v node >/dev/null 2>&1; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y -qq nodejs
fi

# Caddy
if ! command -v caddy >/dev/null 2>&1; then
  apt-get install -y -qq debian-keyring debian-archive-keyring apt-transport-https
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
  apt-get update -qq
  apt-get install -y -qq caddy
fi

mkdir -p "$APP_ROOT"/{log,storage,caddy/data,cache}
chmod 755 "$APP_ROOT"

if [[ ! -d "$APP_ROOT/.git" ]]; then
  git clone --depth 1 "$REPO_URL" "$APP_ROOT"
else
  cd "$APP_ROOT" && git pull --ff-only
fi

if [[ -f /root/migrate-pack.zip ]]; then
  unzip -o /root/migrate-pack.zip -d /root/migrate_unpack
  [[ -f /root/migrate_unpack/.env ]] && cp /root/migrate_unpack/.env "$APP_ROOT/.env"
  if [[ -d /root/migrate_unpack/storage ]]; then
    cp -a /root/migrate_unpack/storage/. "$APP_ROOT/storage/"
  fi
  rm -rf /root/migrate_unpack
fi

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
systemctl restart maxbot
systemctl restart caddy

echo "Setup complete. Check: systemctl status maxbot maxbot-web caddy"
