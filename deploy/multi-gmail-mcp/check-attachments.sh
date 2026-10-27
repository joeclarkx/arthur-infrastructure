#!/usr/bin/env bash
# Regression check for get_email(body) and get_attachment against real messages in
# conni-personal. Prints metadata and PASS/FAIL only, never file contents. Run as root:
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

console.log(failed ? `${failed} FAILED` : 'ALL PASSED');
process.exit(failed ? 1 : 0);
EOF

cd /var/lib/multi-gmail-mcp
set -a; . /etc/multi-gmail-mcp.env; set +a
setpriv --reuid mgmail --regid mgmail --init-groups /opt/node-22/bin/node "$SCRIPT" "$DIST"
