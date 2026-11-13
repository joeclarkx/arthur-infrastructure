#!/usr/bin/env bash
# Provisions self-hosted Umami on Arthur. Idempotent: safe to re-run.
#
# Run on Arthur as root:
#   ssh hetzner "bash -s" < scripts/setup.sh
set -euo pipefail

UMAMI_DIR=/opt/umami
DB_NAME=umami
DB_USER=umami
PORT=3002
# Comma-separated IPs/CIDRs whose pageviews Umami drops (hasBlockedIp in
# src/lib/detect.ts). Joe's home IP is dynamic, so treat this as best-effort and
# rely on the per-browser localStorage opt-out documented in
# docs/umami-deployment.md as the durable exclusion.
IGNORE_IP="${IGNORE_IP:-95.89.139.176}"
# Umami v3 needs Node >= 20.19. Arthur's apt Node (18) is shared with
# multi-gmail-mcp and pm2, so Umami gets its own copy instead of a system upgrade.
NODE_VERSION=v22.23.5
NODE_SHA256=cdeb8670a0c81f51b4dc4ac61919f9b1ad917b304bf8221eb939570663d240f8
NODE_DIR=/opt/node-umami

if ! command -v psql >/dev/null 2>&1; then
    echo "Postgres not found. Installing..."
    apt-get update
    apt-get install -y postgresql
fi

if [ ! -x "$NODE_DIR/bin/node" ] || [ "$("$NODE_DIR/bin/node" -v)" != "$NODE_VERSION" ]; then
    tmp="$(mktemp -d)"
    curl -fsSL "https://nodejs.org/dist/${NODE_VERSION}/node-${NODE_VERSION}-linux-x64.tar.xz" -o "$tmp/node.tar.xz"
    echo "${NODE_SHA256}  $tmp/node.tar.xz" | sha256sum -c -
    rm -rf "$NODE_DIR" && mkdir -p "$NODE_DIR"
    tar -xJf "$tmp/node.tar.xz" -C "$NODE_DIR" --strip-components=1
    rm -rf "$tmp"
fi
export PATH="$NODE_DIR/bin:$PATH"

if ! id umami >/dev/null 2>&1; then
    useradd --system --home "$UMAMI_DIR" --shell /usr/sbin/nologin umami
fi

DB_PASSWORD_GENERATED=""
if ! sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'" | grep -q 1; then
    DB_PASSWORD_GENERATED="$(openssl rand -hex 24)"
    sudo -u postgres psql -c "CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASSWORD_GENERATED}';"
fi
sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1 || \
    sudo -u postgres psql -c "CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};"

if [ ! -d "$UMAMI_DIR" ]; then
    git clone https://github.com/umami-software/umami.git "$UMAMI_DIR"
fi

cd "$UMAMI_DIR"
# Dump before any migration runs. Kept in root's home, not /tmp.
if sudo -u postgres psql -lqt | cut -d'|' -f1 | grep -qw "$DB_NAME"; then
    mkdir -p /root/umami-backups
    sudo -u postgres pg_dump "$DB_NAME" | gzip > "/root/umami-backups/umami-$(date +%Y%m%d-%H%M%S).sql.gz"
fi
# The tree is chowned to umami: at the end of this script, so on re-runs root
# sees it as "dubious ownership". Pass the exception per-command rather than
# writing it into root's global gitconfig.
GIT="git -c safe.directory=${UMAMI_DIR}"
$GIT fetch --tags
LATEST_TAG=$($GIT tag -l 'v3.*' | sort -V | tail -1)
$GIT checkout "$LATEST_TAG"

if [ ! -f .env ]; then
    if [ -n "$DB_PASSWORD_GENERATED" ]; then
        DB_PASSWORD="$DB_PASSWORD_GENERATED"
    else
        echo "No .env present and DB user already existed, so its password is unknown."
        echo "Set DATABASE_URL manually in ${UMAMI_DIR}/.env, then re-run this script."
        exit 1
    fi
    cat > .env <<EOF
DATABASE_URL=postgresql://${DB_USER}:${DB_PASSWORD}@localhost:5432/${DB_NAME}
APP_SECRET=$(openssl rand -hex 32)
PORT=${PORT}
IGNORE_IP=${IGNORE_IP}
EOF
    chmod 600 .env
    echo "Wrote ${UMAMI_DIR}/.env with a generated DB password."
fi

# v3 requires APP_SECRET to be set (no DATABASE_URL fallback); MCP_ENABLED
# exposes the read-only /mcp endpoint, authenticated by an Umami API key.
grep -q '^APP_SECRET=.' .env || { echo "APP_SECRET missing from .env"; exit 1; }
grep -q '^MCP_ENABLED=' .env || echo "MCP_ENABLED=1" >> .env

# Keep IGNORE_IP in sync on an .env that already exists.
if grep -q '^IGNORE_IP=' .env; then
    sed -i "s|^IGNORE_IP=.*|IGNORE_IP=${IGNORE_IP}|" .env
else
    echo "IGNORE_IP=${IGNORE_IP}" >> .env
fi

npm install --legacy-peer-deps
npx prisma migrate deploy
npm run build

chown -R umami:umami "$UMAMI_DIR"

echo "Build complete. Next: install scripts/umami.service, enable it, then"
echo "configure the Apache vhost from scripts/apache-vhost-umami.conf and run certbot."
