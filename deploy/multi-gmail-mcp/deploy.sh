#!/usr/bin/env bash
# Idempotent deploy of multi-gmail-cowork-mcp on Arthur. Run as root:
#   ssh hetzner "cd /opt/arthur-infrastructure && git pull origin main && bash deploy/multi-gmail-mcp/deploy.sh"
# Safe to rerun: the env file and token files are never overwritten.
set -euo pipefail

UPSTREAM=https://github.com/reconexus/multi-gmail-cowork-mcp.git
COMMIT=5d3fcd83b589036cc9faa23447fc45275894a451
NODE_VERSION=v22.23.4
NODE_SHA256=1805bcd35e6815559bd2eb97db438d3fdb0eb3a5e6a977b7c1badca76337e9ce
HOST=mail.mcp.joeclark.photo
ARTHUR_IP=78.47.37.126

HERE="$(cd "$(dirname "$0")" && pwd)"
APP=/opt/multi-gmail-mcp/app
NODE_DIR=/opt/node-22
ENV_FILE=/etc/multi-gmail-mcp.env

# Node 22 for this service only. System Node 18 stays for Umami and diary.
if [ "$("$NODE_DIR/bin/node" -v 2>/dev/null)" != "$NODE_VERSION" ]; then
  tmp="$(mktemp -d)"
  curl -fsSL "https://nodejs.org/dist/$NODE_VERSION/node-$NODE_VERSION-linux-x64.tar.xz" -o "$tmp/node.tar.xz"
  echo "$NODE_SHA256  $tmp/node.tar.xz" | sha256sum -c --quiet -
  rm -rf "$NODE_DIR" && mkdir -p "$NODE_DIR"
  tar -xJf "$tmp/node.tar.xz" -C "$NODE_DIR" --strip-components=1
  rm -rf "$tmp"
fi
export PATH="$NODE_DIR/bin:$PATH"

id mgmail >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin mgmail

# Upstream at the pinned commit plus our patches, in order. Owned by root, read-only to the service.
[ -d "$APP/.git" ] || git clone --quiet "$UPSTREAM" "$APP"
git -C "$APP" fetch --quiet origin
git -C "$APP" reset --quiet --hard "$COMMIT"
git -C "$APP" clean -fdq
for patch in "$HERE"/[0-9][0-9]-*.patch; do git -C "$APP" apply "$patch"; done
(cd "$APP" && npm ci --ignore-scripts --no-audit --no-fund --loglevel=error && npm run --silent build && npm prune --omit=dev --no-audit --no-fund --loglevel=error)

# Secrets: created once, never overwritten, never printed.
if [ ! -f "$ENV_FILE" ]; then
  install -m 600 -o root -g root "$HERE/env.example" "$ENV_FILE"
  sed -i -e "s|^ADMIN_PASSWORD=$|ADMIN_PASSWORD=$(openssl rand -hex 32)|" \
         -e "s|^OAUTH_STATE_SECRET=$|OAUTH_STATE_SECRET=$(openssl rand -hex 32)|" "$ENV_FILE"
  echo "Created $ENV_FILE. Fill in GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET."
fi

install -m 644 "$HERE/multi-gmail-mcp.service" /etc/systemd/system/multi-gmail-mcp.service
systemctl daemon-reload
systemctl enable --quiet multi-gmail-mcp

install -m 644 "$HERE/apache-vhost.conf" /etc/apache2/sites-available/multi-gmail-mcp.conf
a2ensite -q multi-gmail-mcp
apache2ctl configtest
systemctl reload apache2

if [ ! -d "/etc/letsencrypt/live/$HOST" ]; then
  if [ "$(dig +short "$HOST" | tail -1)" = "$ARTHUR_IP" ]; then
    certbot --apache -d "$HOST" --non-interactive --agree-tos --redirect
  else
    echo "WARNING: $HOST does not resolve to $ARTHUR_IP yet; skipped certbot. Rerun once DNS is live."
  fi
fi

if grep -q '^GOOGLE_CLIENT_ID=.' "$ENV_FILE" && grep -q '^GOOGLE_CLIENT_SECRET=.' "$ENV_FILE"; then
  systemctl restart multi-gmail-mcp
  for _ in $(seq 10); do
    curl -fsS http://127.0.0.1:3003/status >/dev/null 2>&1 && { echo "multi-gmail-mcp is up."; exit 0; }
    sleep 1
  done
  echo "ERROR: multi-gmail-mcp did not come up. See: journalctl -u multi-gmail-mcp -n 50" >&2
  exit 1
else
  echo "Google client ID/secret not set in $ENV_FILE; service installed but not started."
fi
