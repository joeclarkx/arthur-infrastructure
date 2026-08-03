# Arthur Infrastructure

Management and deployment of services on Arthur (Hetzner VPS).

## Quick Start

**Check service status:**
```bash
ssh hetzner "systemctl status umami"
```

**View logs:**
```bash
ssh hetzner "journalctl -u umami -n 100 -f"
```

**Deploy changes:**
```bash
git push origin main
ssh hetzner "cd /opt/arthur-infrastructure && git pull origin main && bash scripts/umami/deploy.sh"
```

## Services

### Umami Analytics
- **Status:** [Check logs](#view-logs)
- **Docs:** See `docs/umami-deployment.md`
- **Port:** 3000 (reverse-proxied via Apache)
- **Database:** PostgreSQL (credentials in `.env`)

## Documentation

- `docs/architecture.md` — Overview of Arthur setup
- `docs/umami-deployment.md` — Installation and configuration
- `docs/maintenance.md` — Backups, monitoring, upgrades
- `docs/task_list.md` — Current and completed tasks

## Credentials

Sensitive files live in `credentials/` (not in git):
- `.env` — Database passwords, API keys
- SSH keys for deployment automation

Create these locally and never commit them.
