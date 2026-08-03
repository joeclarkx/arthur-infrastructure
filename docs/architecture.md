# Arthur Server Architecture

## Overview

Arthur is a single Hetzner CX23 VPS hosting:
- CRM frontend (React/Vite)
- CRM API (FastAPI/uvicorn)
- Umami analytics platform
- Lead pipeline (background jobs)

## Network & Ports

| Port | Service | Details |
|------|---------|---------|
| 22 | SSH | Deployment and admin access |
| 80 | HTTP | Apache reverse proxy (redirects to 443) |
| 443 | HTTPS | Apache (TLS termination, Let's Encrypt) |
| 8001 | uvicorn | CRM API (localhost only, proxied via Apache) |
| 3002 | Umami | Application (localhost only, proxied via Apache) |
| 5432 | PostgreSQL | Database (localhost only, no remote access) |

## Service Architecture

```
┌─────────────────────────────────────────┐
│        Internet (users)                  │
└────────────────┬────────────────────────┘
                 │
         ┌───────▼────────┐
         │    Apache2     │ (TLS termination, reverse proxy)
         └───┬────────┬───┘
             │        │
        ┌────▼──┐  ┌──▼────────────┐
        │ CRM   │  │ Umami          │
        │ (8001)│  │ (3002)         │
        └────┬──┘  └──┬────────────┘
             │        │
             │    ┌───▼─────────────┐
             │    │  PostgreSQL     │
             │    │  (analytics DB) │
             │    └─────────────────┘
             │
     ┌───────▼─────────┐
     │ Lead Pipeline   │
     │ (/opt/lead-...) │
     └─────────────────┘
```

## Key Files & Paths

### Apache Configuration
- **Main config:** `/etc/apache2/sites-enabled/joeclark.photo.conf`
- **Umami vhost:** `/etc/apache2/sites-enabled/umami.conf` (managed by this repo)
- **SSL certs:** `/etc/letsencrypt/live/joeclark.photo/`

### Services
- **CRM API:** `/etc/systemd/system/crm-api.service`
- **Umami:** `/etc/systemd/system/umami.service` (managed by this repo)

### Deployment
- **This repo:** `/opt/arthur-infrastructure/` (auto-deploy via git pull)
- **Lead pipeline:** `/opt/lead-pipeline/` (separate repo, auto-deploy via git pull)
- **Frontend build:** `/opt/lead-pipeline/crm-frontend/dist/` → `/var/www/crm/` (rsync)

### Data
- **Analytics DB:** `/var/lib/postgresql/` (PostgreSQL data directory)
- **Umami config:** `/opt/umami/` or env-based (check setup.sh)

## Deployment Flow

1. **Code change** committed + pushed to `origin/main`
2. **Cron or manual trigger** on local machine: `ssh hetzner "cd /opt/arthur-infrastructure && git pull"`
3. **Deploy script** runs: applies config, restarts services
4. **Status check:** logs reviewed, service health verified

## Resource Limits

- **RAM:** 2GB total
  - Apache + services: ~600MB
  - PostgreSQL: ~500MB
  - Umami + uvicorn: ~600MB
  - Headroom: ~300MB

Monitor via `free -h` on server. If approaching limit, consider:
- Database optimization
- Archiving old analytics data
- Migration to larger instance

## DNS & SSL

- **Domain:** joeclark.photo
- **DNS:** Configured externally (not managed here)
- **SSL:** Let's Encrypt (auto-renewed by certbot)
- **Renewal:** Handled by system cron, check `/var/log/letsencrypt/`

## Security

- **Firewall:** UFW (allow SSH, HTTP, HTTPS only)
- **Updates:** Unattended-upgrades configured (check `/etc/apt/apt.conf.d/50unattended-upgrades`)
- **SSH keys:** Configured in `~/.ssh/authorized_keys` for deploy user
- **Passwords:** Never stored in git; use `.env` file in `credentials/`

## Backups

Currently: **Not automated** (TODO: implement in this repo)

Planned:
- Daily PostgreSQL dumps to local storage
- Weekly rotation to cold storage (Backblaze B2)
- Restore procedure documented

See `docs/maintenance.md` for manual backup steps.

## Monitoring

Currently: **Minimal** (TODO: implement health checks)

Check service status manually:
```bash
ssh hetzner "systemctl status umami && journalctl -u umami -n 20"
```

Planned:
- Automated health checks every 5 minutes
- Alerts on service failure or high resource usage
- Status dashboard
