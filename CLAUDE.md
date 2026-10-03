# arthur-infrastructure

Infrastructure and services running on Arthur (Hetzner VPS CX23, 78.47.37.126).

## Server Context

**Host:** Arthur (Hetzner)  
**IP:** 78.47.37.126  
**OS:** Linux (CX23, 2 shared vCPU, 4GB RAM, 40GB SSD)  
**SSH:** `ssh hetzner` (configured in ~/.ssh/config)

### Users & Permissions
- **deploy** user: manages services and deploys via systemd
- Deployments use non-root user with sudo for service management only
- SSH key for deployments stored in `credentials/` (not committed)

### Key Directories
- `/opt/lead-pipeline/` — Lead pipeline code, data, and configs
- `/opt/lead-pipeline/crm-api/` — FastAPI backend (port 8001)
- `/var/www/crm/` — CRM frontend (Apache-served, port 80/443)
- `/var/www/umami/` — Umami installation (reverse-proxied by Apache)
- `/etc/systemd/system/` — Service files for crm-api, umami, etc.

### Running Services
- **crm-api** (systemd): FastAPI backend, auto-restart on failure
- **umami** (systemd): Analytics service
- **Apache2**: Reverse proxy for crm-frontend and umami
- **PostgreSQL** (if used by Umami): analytics database

## Deployment & Maintenance

### Before Any Change
1. Read the relevant service docs in `docs/`
2. Test locally if possible
3. Commit and push to `origin/main`
4. Deploy via the relevant deploy script

### Deploying Changes
Run from local machine:
```bash
ssh hetzner "cd /opt/arthur-infrastructure && git pull origin main && bash scripts/umami/deploy.sh"
```

If deploy scripts are not yet idempotent, coordinate with Joe before running.

### Monitoring & Logs
```bash
ssh hetzner "systemctl status umami"
ssh hetzner "journalctl -u umami -n 50"
ssh hetzner "journalctl -u umami --since '1 hour ago'"
```

## Session Protocol

- Always read `docs/task_list.md` at session start to understand current state
- After changes, update `docs/task_list.md` with results and any new tasks
- When services are deployed, document the change in `docs/CHANGELOG.md`
- Never make changes directly on the server — all changes come via git push + deploy script

## Structure
- `docs/` — Architecture, deployment guides, runbooks
- `scripts/` — Installation, deployment, backup, and maintenance scripts
- `config/` — Service configs (systemd, Apache, env templates)
- `monitoring/` — Health checks and alerting stubs

## Git Workflow
- Main branch is production. All changes committed and pushed before deploy.
- Tag releases: `git tag -a v1.0.0 -m "Umami deployment"` after successful deploy
- Never force-push. Rebase locally if needed, then push normally.
