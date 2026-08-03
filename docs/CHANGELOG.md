# Changelog

## 2026-08-03 — Self-hosted Umami deployed to Arthur

Migrated off Umami Cloud to a self-hosted instance at `https://umami.joeclark.photo`.

- Installed PostgreSQL 16, created `umami` DB/role
- Cloned Umami v2.20.2 to `/opt/umami`, built and running under systemd (`umami.service`)
- Running on port 3002 (3001 was already in use by another app on the box)
- Apache reverse proxy + Let's Encrypt cert via certbot
- DNS: `umami.joeclark.photo` A record → `78.47.37.126`
- Started fresh (no data imported from Umami Cloud) — websites need to be re-added and tracking scripts redeployed to joeclark.photo and the CRM frontend

Fixed along the way: `scripts/setup.sh` had drifted from the docs/Apache template (port 3000 vs 3001, `HASH_SALT` vs `APP_SECRET`, `umami_user` vs `umami`) — none of it had been run against the real box before. Also needed `--legacy-peer-deps` for `npm install` (react 19 vs `@hello-pangea/dnd`'s react 18 peer requirement) and had to run `prisma migrate deploy` after `npm run build-db` copies the schema in, before the full `npm run build`.
