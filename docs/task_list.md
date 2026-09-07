# Arthur Infrastructure Tasks

## Current Status

Umami is live and self-hosted on Arthur at https://umami.joeclark.photo (deployed 2026-08-03). Migrated off Umami Cloud — starting fresh, no historical data carried over.

**Health check 2026-09-07:** Arthur-side stack is fully healthy — service up 4
days, listening on 3002, Apache proxy OK, cert valid to 2026-11-01, disk 25%,
memory 1.1/3.7Gi, and a synthetic pageview posted to `/api/send` was accepted
(200) and written to `website_event`. Ingest is *not* the problem. Last real
event was 2026-08-17; 20 events total. Cause is client-side: the tracker is never able to report from
joeclark.photo. See Known Issues.

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

- **RESOLVED 2026-09-07 (pending confirmation of a live hit): WP Fastest
  Cache's "Combine JS" swallowed the Umami tracker, so it could never report.**
  Not a stale cache — an initial read of this as staleness was wrong; purging
  the cache does not fix it and pages cached seconds ago reproduce it.
  Mechanism: WPFC concatenates the remote tracker into
  `/wp-content/cache/wpfc-minified/<hash>/e0hrj.js` (the bundle literally
  contains `// source --> https://umami.joeclark.photo/script.js`) and comments
  out the original tag. The bundled copy cannot work:
    1. Umami reads its site ID from `document.currentScript`'s
       `data-website-id`. The bundle's tag carries only `src` and `type`, and
       the ID `86e39abc-...` appears **0 times** in the bundle. With no site ID
       the tracker's own guard suppresses every event.
    2. The collect URL is derived from `currentScript.src`, so it resolves to
       `joeclark.photo/wp-content/cache/wpfc-minified/api/send` — wrong origin.
  Confirmed by request path, independent of any clock: requests that WPFC
  serves or writes (plain GET, any UA, any cookie) return the commented tag;
  requests that bypass WPFC (POST, or any query string) return it active.
  **Fix (WP Admin, not Arthur):** WP Fastest Cache → Settings → Exclude → add a
  JS exclude rule matching `umami.joeclark.photo/script.js` (or disable
  Combine JS), then delete the cache. Verify:
  ```
  curl -s -L https://joeclark.photo/ | grep -c '<!-- <script defer src="https://umami'
  ```
  `0` means fixed. Then confirm a real hit lands in `website_event`.
  Note: WordPress stamps its cache timestamps in UTC, 2h behind Berlin local.

  **Update 2026-09-07 (later):** the WPFC "Exclude JS → Contains
  umami.joeclark.photo/script.js" rule did NOT resolve it. After adding the
  rule and a manual cache clear, the minified JS bundles disappeared from the
  page (so the exclude had some effect) but WPFC still comments the tag out on
  every cached response. Bypass paths (POST, any query string) remain ACTIVE,
  so WordPress itself still emits the tag correctly.

  **Resolution.** The inline-loader block was pasted into the theme's custom
  head content and the cache cleared. Verified 2026-09-07: the loader survives
  WPFC's pass uncommented on every page sampled (/, /art/, /architecture/,
  /interiors/, /on-running-berlin/, /50hertz/, /art-fairs/), and no
  wpfc-minified bundle absorbs the tracker any more. Wire path is clear too —
  script.js 200 with `Access-Control-Allow-Origin: *`, /api/send preflight 204,
  no CSP on the site.

  Still to confirm: one real browser hit landing in `website_event`. Joe's own
  IP is the one `IGNORE_IP` drops, so testing needs a different IP (phone on
  mobile data, WiFi off). Event count was 20, last 2026-08-17, at time of fix.

  **Durable fix — inject the tag from inline JS instead.** WPFC only rewrites
  static `<script src>` tags in the HTML; a script element created at runtime
  is invisible to its combine/comment pass, so this stops depending on plugin
  settings entirely. Replace the tag in the theme's custom head content with:

  ```html
  <script>
  (function () {
    var s = document.createElement('script');
    s.defer = true;
    s.src = 'https://umami.joeclark.photo/script.js';
    s.setAttribute('data-website-id', '86e39abc-34e4-4093-8352-ae2e81afbe5f');
    document.head.appendChild(s);
  })();
  </script>
  ```

  This keeps `data-website-id` on the real script element, so Umami's
  `document.currentScript` lookup still resolves both the site ID and the
  `/api/send` origin correctly — the two things the bundled copy destroyed.

- Own traffic to joeclark.photo shows up in Umami. `IGNORE_IP` is **deployed
  and verified working** as of 2026-09-07 (`/opt/umami/.env` =
  `95.89.139.176`, matches the current home IP; a probe from that IP is
  correctly rejected with 403 by `hasBlockedIp`). Home IP is dynamic so this
  still needs re-checking periodically. Note the interaction with the cache bug
  above: Joe bypasses the cache when logged in, so he was the only visitor
  getting the live tag — and his hits are dropped by `IGNORE_IP`. That is why
  the dashboard showed *exactly* zero rather than "just Joe". See "Excluding
  Your Own Visits" in `docs/umami-deployment.md`.

### Future Considerations
- CRM API deployment (separate from lead-pipeline)
- Centralized logging (ELK or similar)
- CDN for static assets
- Database replication for high availability
