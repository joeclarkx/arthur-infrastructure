#!/usr/bin/env bash
# Provisions self-hosted Umami on Arthur. NOT YET RUN — written in a cloud
# session with no SSH access, so nothing here has been verified against the
# real box. Read docs/plans/umami-self-hosted-analytics.md first, in
# particular the "check on Arthur first" list (Postgres presence, Node
# version, RAM/disk headroom) before running this.
#
# Run on Arthur as root:
#   ssh hetzner "bash -s" < scripts/umami/setup.sh
set -euo pipefail

UMAMI_DIR=/opt/umami
DB_NAME=umami
DB_USER=umami

if ! command -v psql >/dev/null 2>&1; then
    echo "Postgres not found. Installing..."
    apt-get update
    apt-get install -y postgresql
fi

if ! id umami >/dev/null 2>&1; then
    useradd --system --home "$UMAMI_DIR" --shell /usr/sbin/nologin umami
fi

sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'" | grep -q 1 || \
    sudo -u postgres psql -c "CREATE USER ${DB_USER} WITH PASSWORD '$(openssl rand -hex 24)';"
sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1 || \
    sudo -u postgres psql -c "CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};"

echo "Postgres DB '${DB_NAME}' ready. Set the matching password in ${UMAMI_DIR}/.env's DATABASE_URL."

if [ ! -d "$UMAMI_DIR" ]; then
    git clone https://github.com/umami-software/umami.git "$UMAMI_DIR"
fi

cd "$UMAMI_DIR"

if [ ! -f .env ]; then
    cat > .env <<EOF
DATABASE_URL=postgresql://${DB_USER}:CHANGE_ME@localhost:5432/${DB_NAME}
APP_SECRET=$(openssl rand -hex 32)
EOF
    echo "Wrote ${UMAMI_DIR}/.env with a placeholder DB password. Edit DATABASE_URL to match what was set above before continuing."
    exit 0
fi

npm install
npx prisma migrate deploy
npm run build

chown -R umami:umami "$UMAMI_DIR"

echo "Build complete. Next: install scripts/umami/umami.service, enable it, then"
echo "configure the Apache vhost from scripts/umami/apache-vhost-umami.conf and run certbot."
