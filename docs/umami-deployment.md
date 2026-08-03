# Umami Deployment & Configuration

## Overview

Umami is a privacy-focused analytics platform self-hosted on Arthur. It tracks analytics for joeclark.photo and the CRM frontend.

- **Repository:** This repo (`arthur-infrastructure`)
- **Installation:** `/opt/umami/` (or per setup.sh)
- **Database:** PostgreSQL (local, separate from CRM)
- **Port:** 3000 (reverse-proxied via Apache to `umami.joeclark.photo`)
- **Service:** systemd unit `umami.service`

## Installation (Fresh Setup)

**Prerequisites:**
- PostgreSQL installed and running
- Node.js 18+ available
- Apache2 with mod_proxy enabled

**Steps:**

1. **Pull the repo:**
   ```bash
   ssh hetzner "cd /opt && git clone https://github.com/joeclarkx/arthur-infrastructure.git"
   ```

2. **Run the setup script:**
   ```bash
   ssh hetzner "bash /opt/arthur-infrastructure/scripts/umami/setup.sh"
   ```

   This script:
   - Creates PostgreSQL database and user
   - Clones/updates Umami source
   - Installs Node dependencies
   - Builds the application
   - Copies systemd service file
   - Copies Apache vhost config
   - Starts the service

3. **Verify installation:**
   ```bash
   ssh hetzner "systemctl status umami"
   ssh hetzner "curl http://localhost:3000"
   ```

4. **Access the web UI:**
   - Navigate to `https://umami.joeclark.photo` in browser
   - Default credentials: `admin` / `umami` (change immediately)

## Configuration

### Environment Variables

Create `credentials/.env` (not in git):

```bash
DATABASE_URL=postgresql://umami_user:PASSWORD@localhost:5432/umami
HASH_SALT=your-random-string-here
NODE_ENV=production
```

**How to generate HASH_SALT:**
```bash
ssh hetzner "node -e \"console.log(require('crypto').randomBytes(16).toString('hex'))\""
```

### Apache Reverse Proxy

Located in `config/apache-vhost-umami.conf`. Deployed to `/etc/apache2/sites-enabled/umami.conf`.

Handles:
- HTTPS termination (Let's Encrypt cert)
- Reverse proxy to `http://localhost:3000`
- Static file caching
- Compression

## Operation

### Start / Stop / Restart

```bash
ssh hetzner "systemctl start umami"
ssh hetzner "systemctl stop umami"
ssh hetzner "systemctl restart umami"
```

### View Logs

```bash
# Last 50 lines
ssh hetzner "journalctl -u umami -n 50"

# Tail (live)
ssh hetzner "journalctl -u umami -f"

# Last hour
ssh hetzner "journalctl -u umami --since '1 hour ago'"
```

### Database Access

```bash
ssh hetzner "sudo -u postgres psql -d umami"
```

Check data:
```sql
SELECT COUNT(*) FROM events;
SELECT COUNT(*) FROM websites;
```

## Updates & Maintenance

### Upgrade Umami

Check for new releases: https://github.com/umami-software/umami/releases

To upgrade:
```bash
ssh hetzner "cd /opt/umami && git fetch && git checkout v2.X.X"
ssh hetzner "cd /opt/umami && npm install && npm run build"
ssh hetzner "systemctl restart umami"
```

Then verify: `https://umami.joeclark.photo`

### Database Maintenance

PostgreSQL maintenance (weekly):
```bash
ssh hetzner "sudo -u postgres vacuumdb umami"
ssh hetzner "sudo -u postgres reindexdb umami"
```

## Troubleshooting

### Service Won't Start

1. Check logs:
   ```bash
   ssh hetzner "journalctl -u umami -n 30"
   ```

2. Check database connection:
   ```bash
   ssh hetzner "psql 'postgresql://umami_user@localhost/umami' -c 'SELECT 1'"
   ```

3. Check Node.js version:
   ```bash
   ssh hetzner "node --version"
   ```

### High Memory Usage

Monitor: `ssh hetzner "free -h && ps aux | grep umami"`

Solutions:
- Archive old event data (see maintenance.md)
- Increase server RAM
- Check for database query slowness

### Apache Not Proxying

1. Check Apache status: `ssh hetzner "systemctl status apache2"`
2. Check mod_proxy is enabled: `ssh hetzner "apache2ctl -M | grep proxy"`
3. Check Apache config: `ssh hetzner "apache2ctl -t"`
4. Reload Apache: `ssh hetzner "systemctl reload apache2"`

## Monitoring Sites

1. **joeclark.photo:** Main portfolio site
   - Track visitors, page views, traffic sources
   - Identify high-performing content

2. **CRM Frontend (crm.joeclark.photo):** Internal tool
   - Track usage patterns
   - Identify UI pain points

Add sites via Umami web UI → Settings → Websites.

## Data Privacy

- Umami does not track personally identifiable information (PII)
- IP addresses are hashed
- No cookies used (GDPR/CCPA compliant)
- Data retention: Keep indefinitely (can be archived manually)

See https://umami.is/docs/privacy for full details.
