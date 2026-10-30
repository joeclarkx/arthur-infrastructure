#!/usr/bin/env bash
# Regression check for get_email(body), get_attachment and get_attachment_link against real messages in
# conni-personal (plus one in joe-personal). Prints metadata and PASS/FAIL only, never file contents. Run as root:
#   ssh hetzner "bash /opt/arthur-infrastructure/deploy/multi-gmail-mcp/check-attachments.sh [dist-dir]"
set -euo pipefail
DIST="${1:-/opt/multi-gmail-mcp/app/dist}"
SCRIPT="$(mktemp /tmp/check-attachments.XXXXXX.mjs)"
trap 'rm -f "$SCRIPT"' EXIT
chmod 644 "$SCRIPT"

cat > "$SCRIPT" <<'EOF'
const dist = process.argv[2];
const { getMessage, getAttachment, sanitizeFilename, AttachmentSelectionError } = await import(`${dist}/gmail.js`);
const { getAccountStore } = await import(`${dist}/accountStore.js`);

let failed = 0;
const check = (ok, label) => { console.log(`${ok ? 'PASS' : 'FAIL'}  ${label}`); if (!ok) failed++; };

check(!/[/\\]/.test(sanitizeFilename('../../etc/passwd')) && !sanitizeFilename('../x').startsWith('.'), 'sanitizeFilename strips separators and leading dots');
check(sanitizeFilename('a\x00b\nc.pdf') === 'a_b_c.pdf' && sanitizeFilename('') === 'attachment', 'sanitizeFilename strips control characters');

const { refreshToken } = await getAccountStore().get('conni-personal');
const MB = 10 * 1024 * 1024;
const cases = [
  ['1980f836359fd931', 'Ticket_880005145326_19.07.2025__H.pdf', '%PDF-'],
  ['1980f836359fd931', 'BAHN_2025-07-19_Hinrueckfahrt_.ics', 'BEGIN:VCALENDAR'],
  ['199cd4c7ef2383d2', 'BahnCard_Rechnung.pdf', '%PDF-'],
  ['196c3c7cac0f8369', 'BAHN_2025-05-12_Hinfahrt_.ics', 'BEGIN:VCALENDAR'],
];
for (const [id, name, magic] of cases) {
  try {
    const msg = await getMessage(refreshToken, id, 'none');
    check(msg.body.text === undefined && msg.body.html === undefined, `${id} body "none" omits text and html`);
    const meta = msg.attachments.find((a) => a.filename === name);
    if (!meta) { check(false, `${id} lists ${name}`); continue; }
    const a = await getAttachment(refreshToken, id, { partId: meta.partId }, MB);
    const b = await getAttachment(refreshToken, id, { filename: name }, MB);
    const bytes = Buffer.from(a.data_base64, 'base64');
    check(Math.abs(a.size - meta.sizeEstimate) <= meta.sizeEstimate * 0.05, `${name}: ${a.size} bytes vs estimate ${meta.sizeEstimate} (${a.mimeType})`);
    check(bytes.subarray(0, 40).toString('latin1').includes(magic), `${name}: starts with ${magic}`);
    check(a.sha256 === b.sha256, `${name}: sha256 ${a.sha256.slice(0, 12)}... stable across part_id and filename fetches`);
  } catch (err) {
    check(false, `${name}: ${err.message}`);
  }
}

const capped = await getAttachment(refreshToken, '199cd4c7ef2383d2', { filename: 'BahnCard_Rechnung.pdf' }, 1000);
check(capped.truncated === true && capped.data_base64 === undefined, 'max_bytes 1000 returns metadata only, truncated');
try {
  await getAttachment(refreshToken, '199cd4c7ef2383d2', { partId: '99' }, MB);
  check(false, 'unknown part_id is rejected');
} catch (err) {
  check(err instanceof AttachmentSelectionError, 'unknown part_id is rejected');
}

// Gmail labels many .ics files application/ics (Rembrandt House ticket, joe-personal).
try {
  const joe = (await getAccountStore().get('joe-personal')).refreshToken;
  const ics = await getAttachment(joe, '1a15a6a611bcbcdb', { partId: '2' }, MB);
  check(ics.mimeType === 'application/ics' && Buffer.from(ics.data_base64, 'base64').toString('latin1').includes('BEGIN:VCALENDAR'), 'application/ics attachment is allowed');
} catch (err) {
  check(false, `application/ics attachment is allowed: ${err.message}`);
}

// get_attachment_link: tokens verify, tampering fails, and the live endpoint serves the same bytes.
const { attachmentLink, verifyToken } = await import(`${dist}/attachmentLinks.js`);
const ref = await getAttachment(refreshToken, '199cd4c7ef2383d2', { filename: 'BahnCard_Rechnung.pdf' }, MB);
const link = attachmentLink('conni-personal', '199cd4c7ef2383d2', ref.part_id, ref.filename);
const token = link.url.split('/attachments/')[1].split('/')[0];
const [payload, sig] = token.split('.');
const forged = Buffer.from(JSON.stringify({ a: 'conni-personal', m: 'x', p: '1', e: 9e9 })).toString('base64url');
check(verifyToken(token)?.p === ref.part_id, 'attachment link token verifies');
check(verifyToken(`${forged}.${sig}`) === undefined && verifyToken(`${payload}.x${sig.slice(1)}`) === undefined, 'tampered link tokens are rejected');
const local = link.url.replace(process.env.PUBLIC_BASE_URL, `http://127.0.0.1:${process.env.PORT}`);
const res = await fetch(local);
const got = Buffer.from(await res.arrayBuffer());
const { createHash } = await import('node:crypto');
check(res.ok && createHash('sha256').update(got).digest('hex') === ref.sha256, `link download: ${res.status}, ${got.length} bytes, sha256 matches`);
check(/^attachment;/.test(res.headers.get('content-disposition') ?? ''), 'link download is served as an attachment');
check((await fetch(local.replace(`.${sig}`, `.x${sig.slice(1)}`))).status === 403, 'bad link signature returns 403');

console.log(failed ? `${failed} FAILED` : 'ALL PASSED');
process.exit(failed ? 1 : 0);
EOF

cd /var/lib/multi-gmail-mcp
set -a; . /etc/multi-gmail-mcp.env; set +a
setpriv --reuid mgmail --regid mgmail --init-groups /opt/node-22/bin/node "$SCRIPT" "$DIST"
