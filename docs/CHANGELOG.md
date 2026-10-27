# Changelog

## 2026-10-27: Multi Gmail MCP deployed to Arthur

Self-hosted [multi-gmail-cowork-mcp](https://github.com/reconexus/multi-gmail-cowork-mcp)
at `https://mail.mcp.joeclark.photo`, instead of Google Cloud Run. Runbook: `docs/multi-gmail-mcp.md`.

- systemd unit `multi-gmail-mcp` (user `mgmail`, sandboxed) on port 3003, behind Apache with Let's Encrypt
- Node 22.23.4 in `/opt/node-22` for this service only; system Node 18 untouched
- Upstream pinned at `5d3fcd8` plus `deploy/multi-gmail-mcp/file-store.patch` (file token store in production, atomic mode-600 writes)
- Tokens in `/var/lib/multi-gmail-mcp/.local/`, secrets in `/etc/multi-gmail-mcp.env` (root, 600, not in git)
- DNS: `*.mcp.joeclark.photo` A record to `78.47.37.126` (Namecheap), so later MCP servers need no DNS change
- Admin and consent pages are public behind a 64-character random password (no IP allow-list: home IP can change)
- Verified: smoke test made no outbound connections; port 3003 blocked by ufw from outside

## 2026-08-03 — Self-hosted Umami deployed to Arthur

Migrated off Umami Cloud to a self-hosted instance at `https://umami.joeclark.photo`.

- Installed PostgreSQL 16, created `umami` DB/role
- Cloned Umami v2.20.2 to `/opt/umami`, built and running under systemd (`umami.service`)
- Running on port 3002 (3001 was already in use by another app on the box)
- Apache reverse proxy + Let's Encrypt cert via certbot
- DNS: `umami.joeclark.photo` A record → `78.47.37.126`
- Started fresh (no data imported from Umami Cloud) — websites need to be re-added and tracking scripts redeployed to joeclark.photo and the CRM frontend

Fixed along the way: `scripts/setup.sh` had drifted from the docs/Apache template (port 3000 vs 3001, `HASH_SALT` vs `APP_SECRET`, `umami_user` vs `umami`) — none of it had been run against the real box before. Also needed `--legacy-peer-deps` for `npm install` (react 19 vs `@hello-pangea/dnd`'s react 18 peer requirement) and had to run `prisma migrate deploy` after `npm run build-db` copies the schema in, before the full `npm run build`.
