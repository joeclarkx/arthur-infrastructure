#!/usr/bin/env bash
# Idempotent deploy of the static apps.joeclark.photo site on Arthur. Run as root:
#   ssh hetzner "cd /opt/arthur-infrastructure && git pull origin main && bash deploy/apps-site/deploy.sh"
# Needs an A record apps.joeclark.photo -> 78.47.37.126 (the *.joeclark.photo wildcard points at dave).
set -euo pipefail

HOST=apps.joeclark.photo
ARTHUR_IP=78.47.37.126
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT=/var/www/apps-joeclark-photo

mkdir -p "$ROOT"
rsync -a --delete --chown=www-data:www-data "$HERE/www/" "$ROOT/"

install -m 644 "$HERE/apache-vhost.conf" /etc/apache2/sites-available/$HOST.conf
a2ensite -q $HOST
apache2ctl configtest
systemctl reload apache2

if [ ! -d "/etc/letsencrypt/live/$HOST" ]; then
  if [ "$(dig +short "$HOST" | tail -1)" = "$ARTHUR_IP" ]; then
    certbot --apache -d "$HOST" --non-interactive --agree-tos --redirect
  else
    echo "WARNING: $HOST does not resolve to $ARTHUR_IP yet; skipped certbot. Rerun once DNS is live."
  fi
fi

curl -fsS --resolve "$HOST:80:127.0.0.1" "http://$HOST/docs-quick-look/privacy.html" -o /dev/null && echo "$HOST is serving."
