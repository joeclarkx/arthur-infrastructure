# Multi Gmail MCP

Self-hosted [multi-gmail-cowork-mcp](https://github.com/reconexus/multi-gmail-cowork-mcp)
(MIT): one Claude custom connector that searches, reads, drafts and sends across
several Gmail accounts. Upstream targets Google Cloud Run; here it runs on Arthur
with its token files on local disk.

- URL: https://mail.mcp.joeclark.photo (connector endpoint `/claude-mcp`, admin `/admin`)
- DNS: `*.mcp.joeclark.photo` A record to 78.47.37.126 (Namecheap), so future MCP
  servers can use `<name>.mcp.joeclark.photo` without a DNS change. Each MCP
  server needs its own hostname, because its OAuth endpoints sit at the root.
- Runs as systemd unit `multi-gmail-mcp`, user `mgmail`, on 127.0.0.1:3003 behind Apache.
- Node 22 in `/opt/node-22`, used only by this service (system Node 18 is left for Umami and diary).

## Files on Arthur

| Path | What |
|---|---|
| `/opt/multi-gmail-mcp/app` | Upstream checkout at the commit pinned in `deploy.sh`, plus our patches |
| `/etc/multi-gmail-mcp.env` | Secrets (root, mode 600). Not in git. |
| `/var/lib/multi-gmail-mcp/.local/accounts.json` | Gmail refresh tokens, plain text, mode 600 |
| `/var/lib/multi-gmail-mcp/.local/mcp-oauth-state.json` | Claude connector registrations and hashed refresh tokens |

Patches in `deploy/multi-gmail-mcp/`, applied in number order by `deploy.sh`:

- `01-file-store.patch`: allows the file token store in production when
  `ALLOW_FILE_TOKEN_STORE=true`, and writes token files atomically (temp file then
  rename, mode 600) so a crash or full disk cannot truncate them.
- `02-get-attachment.patch` (for bookkeeping):
  - `get_email` gains `body: none | text | html | both` (default `both`, as upstream)
    and returns a `partId` for each attachment.
  - New read-only tool `get_attachment`: `account`, `message_id`, `part_id` or exact
    `filename`, `max_bytes` (default 10 MB, maximum 25 MB). Returns `filename`
    (sanitised), `original_filename`, `mimeType`, `size`, `sha256` and `data_base64`,
    or metadata with `truncated: true` if too large. Nothing is written to disk.
  - MIME allowlist: PDF, PNG, JPEG, `text/calendar`, `text/plain` (Deutsche Bahn sends
    `.ics` files as plain text), `application/octet-stream` (DB and bahn.de PDFs) and
    every Office Open XML type.
  - Selection is by `partId`, not Gmail's `attachmentId`: the latter changes on every
    fetch, so it cannot identify an attachment between two calls.
  - Each call logs alias, message id, part id, type and size. It does not log
    filenames, in line with upstream's rule of never logging content.
- `03-attachment-link.patch`: tool `get_attachment_link`, for saving files without
  the bytes passing through Claude (base64 through the model is too expensive past
  a few KB). Same selection, allowlist and 25 MB cap as `get_attachment`; returns
  `filename`, `size`, `sha256`, `download_url` and `expires_at`, no content.
  - `download_url` is `/attachments/<token>/<filename>`. The token is the alias,
    message id, part id and an expiry, signed with HMAC-SHA256 under
    `OAUTH_STATE_SECRET`. The link is the auth (no login), so it lives for 1 hour.
    Rotating `OAUTH_STATE_SECRET` kills all outstanding links.
  - Stateless: each download re-fetches from Gmail and is served with
    `Content-Disposition: attachment`. Nothing is written on Arthur.
  - Use: in claude.ai, click the link and the file lands in `~/Downloads`; move it from
    there. In Claude Code, `curl -fsSL -o <path> <download_url>` saves it anywhere.
  - Not done from the save_attachment handoff: named save roots, `save_all_attachments`,
    `list_save_roots`. The server runs on Arthur, so its disk is not the Mac's;
    direct-to-Drive saving would need a sync folder (Syncthing) or the Drive API.

All three are small enough to offer upstream. After an upstream update, rerun the
attachment check (it reads three Deutsche Bahn mails in `conni-personal`, downloads one
through a link, and prints metadata only):

```bash
ssh hetzner "bash /opt/arthur-infrastructure/deploy/multi-gmail-mcp/check-attachments.sh"
```

Tokens are not encrypted at rest. The key would have to live in the env file on the
same disk, so it would not stop anyone who can already read `/var/lib`. Protection is
file permissions, a dedicated user and the systemd sandbox. Treat backups as secrets.

## Deploy or update

```bash
ssh hetzner "cd /opt/arthur-infrastructure && git pull origin main && bash deploy/multi-gmail-mcp/deploy.sh"
```

To pick up a new upstream version: read the upstream changes, set `COMMIT` in
`deploy/multi-gmail-mcp/deploy.sh` to the new commit, commit, push, deploy. If
`git apply` fails, upstream has touched the patched lines: regenerate that patch
against the new commit. Connected accounts and the Claude connector survive updates.

## First-time setup

1. Run the deploy. It creates `/etc/multi-gmail-mcp.env` with a random admin
   password and state secret, installs everything, gets the TLS certificate, and
   leaves the service stopped until the Google values are in.
2. Google Cloud Console (a free project, no billing needed):
   - APIs & Services > Library: enable **Gmail API**.
   - Google Auth Platform > Branding: app name `Multi Gmail`; home page
     `https://mail.mcp.joeclark.photo/`; privacy policy
     `https://mail.mcp.joeclark.photo/privacy`; terms
     `https://mail.mcp.joeclark.photo/terms`; authorised domain `joeclark.photo`.
   - Audience: **External**.
   - Data Access: add scope `https://www.googleapis.com/auth/gmail.modify`.
   - Clients > Create client: type **Web application**, authorised redirect URI
     `https://mail.mcp.joeclark.photo/oauth/google/callback` (exactly; no
     JavaScript origins needed).
   - Audience > **Publish app** (In production). Unverified is fine. In Testing,
     Google expires the Gmail refresh tokens every 7 days.
3. Put the client ID and secret into `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET`:
   `ssh hetzner`, then `nano /etc/multi-gmail-mcp.env`. Rerun the deploy.
4. Get the admin password and keep it in your password manager:
   `ssh hetzner "grep ^ADMIN_PASSWORD /etc/multi-gmail-mcp.env"`
5. https://mail.mcp.joeclark.photo/admin (user `admin`): add each Gmail account
   with a short alias such as `personal` or `work`. Google warns the app is
   unverified; continue past it.
6. Claude: Settings > Connectors > Add custom connector. Name `Multi Gmail`, URL
   `https://mail.mcp.joeclark.photo/claude-mcp`, OAuth Client ID and Secret blank.
   Connect, then approve on the consent page with the admin credentials. In the
   connector's tool settings keep `create_draft` and `send_email` on Needs approval.

## Rotate the admin password

```bash
ssh hetzner 'sed -i "s|^ADMIN_PASSWORD=.*|ADMIN_PASSWORD=$(openssl rand -hex 32)|" /etc/multi-gmail-mcp.env && systemctl restart multi-gmail-mcp'
```

The Claude connector stays connected; the new password is only needed for `/admin`
and the next time Claude asks for approval. Rotating `OAUTH_STATE_SECRET` the same
way disconnects Claude (reconnect it) but leaves Gmail accounts alone.

## Remove a Gmail account

`/admin` > **Disconnect** next to the alias. This revokes the grant with Google and
deletes the token. Belt and braces: also check https://myaccount.google.com/permissions
for that account.

## Back up and restore

The state directory holds live Gmail refresh tokens. Keep backups on an encrypted
disk and delete old ones.

```bash
# Back up to this Mac
ssh hetzner 'tar -C /var/lib -czf - multi-gmail-mcp' > ~/multi-gmail-mcp-$(date +%F).tgz

# Restore
ssh hetzner 'systemctl stop multi-gmail-mcp && rm -rf /var/lib/multi-gmail-mcp && tar -C /var/lib -xzf - && chown -R mgmail:mgmail /var/lib/multi-gmail-mcp && systemctl start multi-gmail-mcp' < ~/multi-gmail-mcp-YYYY-MM-DD.tgz
```

The env file is not needed to restore accounts. If it is lost, rerun the deploy to
generate new secrets, re-enter the Google values, and reconnect Claude.

## Logs

```bash
ssh hetzner "journalctl -u multi-gmail-mcp -n 50"
```

The app never logs tokens or email content. journald rotates its own logs; Apache's
`multi-gmail-mcp-*.log` files are rotated by the stock `logrotate.d/apache2`.
