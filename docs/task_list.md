# Arthur Infrastructure Tasks

## Current Status

Repository initialized. Umami configuration and deployment scripts ported from lead-pipeline repo.

## Completed

✅ Repo structure created
✅ CLAUDE.md with Arthur context
✅ README for quick reference
✅ Architecture documentation (docs/architecture.md)
✅ Umami deployment guide (docs/umami-deployment.md)
✅ Maintenance procedures (docs/maintenance.md)
✅ Copy Umami scripts from lead-pipeline
✅ Config templates (.env.example, Apache vhost)
✅ .gitignore for credentials and builds

## To Do

### Phase 1: Deployment Readiness
- [ ] Verify setup.sh runs without errors on fresh Ubuntu 22.04
- [ ] Test full install flow: git clone → setup.sh → service running
- [ ] Verify Apache vhost config is syntactically correct
- [ ] Test reverse proxy: curl http://localhost:3000 vs https://umami.joeclark.photo
- [ ] Document any manual steps still required on Arthur

### Phase 2: Operational Automation
- [ ] Create idempotent deploy script (scripts/umami/deploy.sh)
- [ ] Add health check script (scripts/monitoring/health-check.sh)
- [ ] Implement automated daily backups to local storage
- [ ] Add restore test procedure

### Phase 3: Monitoring & Alerting
- [ ] Prometheus metrics export from Umami (if available)
- [ ] Status page at status.joeclark.photo showing service health
- [ ] Email/Slack alerts on service failure
- [ ] Disk usage monitoring

### Phase 4: Documentation Updates
- [ ] Troubleshooting guide for common issues
- [ ] Runbook for incident response
- [ ] Upgrade procedure for Umami updates
- [ ] Data retention & archival policy

### Known Issues
- None yet

### Future Considerations
- CRM API deployment (separate from lead-pipeline)
- Centralized logging (ELK or similar)
- CDN for static assets
- Database replication for high availability
