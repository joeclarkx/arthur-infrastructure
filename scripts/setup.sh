#!/usr/bin/env bash
# Provisions self-hosted Umami on Arthur. Idempotent: safe to re-run.
#
# Run on Arthur as root:
#   ssh hetzner "bash -s" < scripts/setup.sh
set -euo pipefail

UMAMI_DIR=/opt/umami
DB_NAME=umami
DB_USER=umami
PORT=3001

if ! command -v psql >/dev/null 2>&1; then
    echo "Postgres not found. Installing..."
    apt-get update
    apt-get install -y postgresql
fi

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
git fetch --tags
LATEST_TAG=$(git tag -l 'v2.*' | sort -V | tail -1)
git checkout "$LATEST_TAG"

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
EOF
    chmod 600 .env
    echo "Wrote ${UMAMI_DIR}/.env with a generated DB password."
fi

npm install
npx prisma migrate deploy
npm run build

chown -R umami:umami "$UMAMI_DIR"

echo "Build complete. Next: install scripts/umami.service, enable it, then"
echo "configure the Apache vhost from scripts/apache-vhost-umami.conf and run certbot."
