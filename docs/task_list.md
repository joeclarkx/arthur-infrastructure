# Arthur Infrastructure Tasks

## Current Status

Umami is live and self-hosted on Arthur at https://umami.joeclark.photo (deployed 2026-08-03). Migrated off Umami Cloud — starting fresh, no historical data carried over.

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
✅ Deployed self-hosted Umami v2.20.2 to Arthur (Postgres 16, systemd, Apache reverse proxy, Let's Encrypt)
✅ DNS: `umami.joeclark.photo` A record added by Joe, pointing to 78.47.37.126
✅ Verified full install flow end-to-end on the real box; fixed drift between setup.sh/docs (port, secret env var names) found in the process

## To Do

### Immediate (post-install)
- [ ] Log into https://umami.joeclark.photo (admin/umami) and change the default password immediately
- [ ] Add joeclark.photo and the CRM frontend as tracked websites in the Umami UI, grab new tracking scripts, deploy them
- [ ] Cancel/downgrade Umami Cloud subscription once tracking is confirmed working on the new sites
- [ ] Note for future reference: port 3001 on Arthur is already used by another app (`/var/www/d...`, likely "diary") — Umami runs on 3002 instead

### Phase 1: Deployment Readiness
- [x] Verify setup.sh runs without errors (fixed npm peer-dep conflict with --legacy-peer-deps, fixed prisma migrate ordering)
- [x] Test full install flow: git clone → setup.sh → service running
- [x] Verify Apache vhost config is syntactically correct
- [x] Test reverse proxy: curl http://localhost:3002 vs https://umami.joeclark.photo
- [x] Document any manual steps still required on Arthur

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
- Own traffic to joeclark.photo shows up in Umami. `IGNORE_IP` added to
  `scripts/setup.sh` (commit d1f4291) but **not yet deployed**; home IP is
  dynamic so it needs re-checking periodically. See "Excluding Your Own Visits"
  in `docs/umami-deployment.md`.

### Under Consideration: Minecraft Bedrock server for Casper
Investigated 2026-10-03. Arthur has the room (4GB RAM; Bedrock server needs ~0.5-1GB for a few players) if capped via systemd (CPUQuota/MemoryMax) so it can't starve crm-api/Umami.
- Casper plays on iPad (can add a custom server directly); friends may be on Switch
- Console limitation: Xbox/PlayStation/Switch have no "Add Server" button (platform restriction, not mentioned on Mojang's server download page). Consoles only see featured servers, Realms, LAN and friends' worlds
- Console workaround 1, BedrockConnect: each Switch owner sets primary DNS to a BedrockConnect address (e.g. 104.238.130.180), then picks a featured server to get a menu for entering our IP. Every family has to change settings, and it depends on a third-party DNS service
- Console workaround 2, MCXboxBroadcast (unofficial, open source, Java): runs next to the server on Arthur, signs into a spare Xbox/Microsoft account and advertises the server as a joinable friend session. Switch players add that account as a friend and join from the Friends tab, with no console settings changed. Costs: needs a second Microsoft account, ~150-200MB extra RAM (fits in 4GB), can break when Minecraft updates. Preferred over BedrockConnect if self-hosting
- Alternative: Minecraft Realm (£3.29/month for 2 friends, £6.69 Realms Plus for 10), works on Switch with no setup
- [ ] Decision pending from Joe: self-host on Arthur vs Realm
- If self-hosting: scripts/minecraft/ (install, capped systemd unit, auto-update + world backup timer), UFW allow 19132-19133/udp, allow-list of friends' gamertags, docs/minecraft.md

### Future Considerations
- CRM API deployment (separate from lead-pipeline)
- Centralized logging (ELK or similar)
- CDN for static assets
- Database replication for high availability
