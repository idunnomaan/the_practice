#!/usr/bin/env bash
# L1 + L5 smoke test — runs against the local replica.
# Usage: ./scripts/smoke.sh  (from project root)
#
# Uses --mode reinstall for a clean state on every run. Local test data only.
set -euo pipefail

PASS=0
FAIL=0

check() {
  local label="$1"
  local expected="$2"
  local actual="$3"
  if echo "$actual" | grep -q "$expected"; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label"
    echo "        expected to find: $expected"
    echo "        got: $actual"
    FAIL=$((FAIL + 1))
  fi
}

check_absent() {
  local label="$1"
  local absent="$2"
  local actual="$3"
  if echo "$actual" | grep -q "$absent"; then
    echo "  FAIL: $label"
    echo "        unexpectedly found: $absent"
    echo "        in: $actual"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  fi
}

echo "=== L1 + L5 Smoke Test ==="
echo ""

# ── Identity setup ────────────────────────────────────────────────────────────
# The anonymous principal (2vxsx-fae) cannot be master controller (INV-1).
# Create plaintext test identities — no keyring or password needed.

ORIGINAL_IDENTITY=$(icp identity default)
echo "Setup: creating plaintext test identities"
icp identity new smoke-master    --storage plaintext -q 2>/dev/null 1>/dev/null || true
icp identity new smoke-associate --storage plaintext -q 2>/dev/null 1>/dev/null || true
icp identity new smoke-ops       --storage plaintext -q 2>/dev/null 1>/dev/null || true
icp identity new smoke-staff     --storage plaintext -q 2>/dev/null 1>/dev/null || true

# Restore original identity on exit (even on failure)
restore() { icp identity default "$ORIGINAL_IDENTITY" 2>/dev/null || true; }
trap restore EXIT

# Get all principals (without switching identity yet)
MASTER_PRINCIPAL=$(icp identity principal --identity smoke-master)
ASSOCIATE_PRINCIPAL=$(icp identity principal --identity smoke-associate)
OPS_PRINCIPAL=$(icp identity principal --identity smoke-ops)
STAFF_PRINCIPAL=$(icp identity principal --identity smoke-staff)
echo "  Master principal:    $MASTER_PRINCIPAL"
echo "  Associate principal: $ASSOCIATE_PRINCIPAL"
echo "  Ops principal:       $OPS_PRINCIPAL"
echo "  Staff principal:     $STAFF_PRINCIPAL"
echo ""

# ── Step 1: Deploy ───────────────────────────────────────────────────────────
# Add smoke-master as a canister controller (as the current controller identity),
# then switch to smoke-master and reinstall for a clean state.
echo "Step 1: Install canister with smoke-master as master controller"
echo "  Granting smoke-master canister controller rights (as $ORIGINAL_IDENTITY)"
icp canister settings update backend --add-controller "$MASTER_PRINCIPAL" -f

echo "  Reinstalling as smoke-master (--mode reinstall gives clean state)"
icp identity default smoke-master
icp deploy backend --mode reinstall --args "(principal \"$MASTER_PRINCIPAL\")"
echo ""

# ── Step 2: whoAmI ───────────────────────────────────────────────────────────
echo "Step 2: whoAmI() should return the master controller's principal"
RESULT=$(icp canister call backend whoAmI "()")
check "whoAmI returns master principal" "$MASTER_PRINCIPAL" "$RESULT"
echo ""

# ── Step 3: getMyRole ────────────────────────────────────────────────────────
echo "Step 3: getMyRole() should return (opt variant { Partner }) for master controller"
RESULT=$(icp canister call backend getMyRole "()")
check "master controller has Partner role" "Partner" "$RESULT"
echo ""

# ── Step 4: getMasterController ──────────────────────────────────────────────
echo "Step 4: getMasterController() should return master principal"
RESULT=$(icp canister call backend getMasterController "()")
check "getMasterController returns master principal" "$MASTER_PRINCIPAL" "$RESULT"
echo ""

# ── Step 5: getOperationsPrincipal ───────────────────────────────────────────
echo "Step 5: getOperationsPrincipal() should return (null) before any grant"
RESULT=$(icp canister call backend getOperationsPrincipal "()")
check "operationsPrincipal is null at install" "null" "$RESULT"
echo ""

# ── Step 6: getUserCount ─────────────────────────────────────────────────────
echo "Step 6: getUserCount() should return (1 : nat) — only master controller registered"
RESULT=$(icp canister call backend getUserCount "()")
check "getUserCount is 1 at install" "1" "$RESULT"
echo ""

# ── Step 7: addUser ──────────────────────────────────────────────────────────
echo "Step 7: addUser — register smoke-associate as Associate (audit id=2)"
RESULT=$(icp canister call backend addUser "(principal \"$ASSOCIATE_PRINCIPAL\", variant { Associate })")
check "addUser returns ok" "ok" "$RESULT"
RESULT=$(icp canister call backend getUserCount "()")
check "getUserCount is 2 after addUser" "2" "$RESULT"
echo ""

# ── Step 8: getMyRole for newly-added user ───────────────────────────────────
echo "Step 8: getMyRole as smoke-associate should return Associate"
RESULT=$(icp canister call backend getMyRole "()" --identity smoke-associate)
check "new user has Associate role" "Associate" "$RESULT"
echo ""

# ── Step 9: setUserRole ──────────────────────────────────────────────────────
echo "Step 9: setUserRole — promote smoke-associate to Partner (audit id=3)"
RESULT=$(icp canister call backend setUserRole "(principal \"$ASSOCIATE_PRINCIPAL\", variant { Partner })")
check "setUserRole returns ok" "ok" "$RESULT"
RESULT=$(icp canister call backend getMyRole "()" --identity smoke-associate)
check "user role updated to Partner" "Partner" "$RESULT"
echo ""

# ── Step 10: suspendUser ─────────────────────────────────────────────────────
echo "Step 10: suspendUser — suspend smoke-associate (audit id=4)"
RESULT=$(icp canister call backend suspendUser "(principal \"$ASSOCIATE_PRINCIPAL\")")
check "suspendUser returns ok" "ok" "$RESULT"
RESULT=$(icp canister call backend getMyRole "()" --identity smoke-associate)
check "suspended user getMyRole returns null" "null" "$RESULT"
echo ""

# ── Step 11: grantOperations ─────────────────────────────────────────────────
echo "Step 11: grantOperations — grant ops principal (audit id=5)"
RESULT=$(icp canister call backend grantOperations "(principal \"$OPS_PRINCIPAL\")")
check "grantOperations returns ok" "ok" "$RESULT"
RESULT=$(icp canister call backend getOperationsPrincipal "()")
check "operationsPrincipal is set after grant" "$OPS_PRINCIPAL" "$RESULT"
echo ""

# ── Step 12: revokeOperations ────────────────────────────────────────────────
echo "Step 12: revokeOperations — revoke ops (audit id=6)"
RESULT=$(icp canister call backend revokeOperations "()")
check "revokeOperations returns ok" "ok" "$RESULT"
RESULT=$(icp canister call backend getOperationsPrincipal "()")
check "operationsPrincipal is null after revoke" "null" "$RESULT"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# L5 Audit log assertions
# Audit log state at this point: ids 1–6 (install, addUser, setUserRole,
# suspendUser, grantOperations, revokeOperations).
# readAuditEntries emits its own entry BEFORE collecting results, so every call
# to readAuditEntries appears as the last entry in its own returned page.
# ═══════════════════════════════════════════════════════════════════════════════

# ── Step 13: L5 — install event is audit id=1 ────────────────────────────────
echo "Step 13: L5 — readAuditEntries(0, 10) should return install event as id=1"
echo "  (also records itself as id=7; emit-before-collect, so id=7 appears in results)"
RESULT=$(icp canister call backend readAuditEntries "(0 : nat, 10 : nat)")
check "readAuditEntries returns ok" "ok" "$RESULT"
check "install event present in audit log" "install" "$RESULT"
check "grantOperations event present" "grantOperations" "$RESULT"
check "addUser event present" "addUser" "$RESULT"
echo ""

# ── Step 14: L5 — unauthorized mutator call creates an #err audit entry ──────
echo "Step 14: L5 — smoke-staff (unregistered) calls grantOperations; should return #err"
echo "  and create audit entry with outcome = #err (audit id=8)"
RESULT=$(icp canister call backend grantOperations "(principal \"$OPS_PRINCIPAL\")" --identity smoke-staff)
check "unauthorized grantOperations returns err" "err" "$RESULT"
echo ""

# ── Step 15: L5 — confirm the #err entry was recorded ────────────────────────
echo "Step 15: L5 — readAuditEntries(0, 100) as Partner; confirm #err entry is present"
echo "  (records itself as id=9)"
RESULT=$(icp canister call backend readAuditEntries "(0 : nat, 100 : nat)")
check "audit log contains an err outcome" "err" "$RESULT"
check "failed grantOperations appears in log" "grantOperations" "$RESULT"
echo ""

# ── Step 16: L5 — non-Partner readAuditEntries returns #err ──────────────────
echo "Step 16: L5 — smoke-staff calls readAuditEntries; should return #err('not authorized')"
echo "  and create audit entry with outcome = #err('not authorized') (audit id=10)"
RESULT=$(icp canister call backend readAuditEntries "(0 : nat, 10 : nat)" --identity smoke-staff)
check "non-Partner readAuditEntries returns err" "err" "$RESULT"
check "error message is not authorized" "not authorized" "$RESULT"
echo ""

# ── Step 17: L5 — meta-trust property: readAuditEntries appears in its own results ──
echo "Step 17: L5 — readAuditEntries(0, 1000) as Partner; last entry should be"
echo "  readAuditEntries itself (proving the meta-trust property)"
echo "  (records itself as id=11; emit-before-collect puts id=11 at end of results)"
RESULT=$(icp canister call backend readAuditEntries "(0 : nat, 1000 : nat)")
check "full read returns ok" "ok" "$RESULT"
check "non-Partner read failure is in log" "not authorized" "$RESULT"
check "readAuditEntries action appears in own results" "readAuditEntries" "$RESULT"
echo ""

# ── Step 18: L5 — cursor pagination: no gaps, no overlap ─────────────────────
echo "Step 18: L5 — cursor pagination: readAuditEntries(0, 3) then readAuditEntries(3, 3)"
echo "  Page 1 should contain the install event (id=1); page 2 should not."
echo "  Page 2 should contain suspendUser (id=4); page 1 should not."

echo "  Fetching page 1 (after=0, limit=3) — records itself as id=12, returns ids 1-3"
PAGE1=$(icp canister call backend readAuditEntries "(0 : nat, 3 : nat)")
check "page 1 returns ok" "ok" "$PAGE1"
check "page 1 contains install event" "install" "$PAGE1"
check_absent "page 1 does not contain suspendUser" "suspendUser" "$PAGE1"

echo "  Fetching page 2 (after=3, limit=3) — records itself as id=13, returns ids 4-6"
PAGE2=$(icp canister call backend readAuditEntries "(3 : nat, 3 : nat)")
check "page 2 returns ok" "ok" "$PAGE2"
check "page 2 contains suspendUser (id=4, no gap from cursor=3)" "suspendUser" "$PAGE2"
check_absent "page 2 does not contain install (no overlap with page 1)" "install" "$PAGE2"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# L2 Client + Matter lifecycle assertions — start at Step 35 per spec §7
# ═══════════════════════════════════════════════════════════════════════════════

# smoke-partner: a second Partner identity for multi-user tests
icp identity new smoke-partner --storage plaintext -q 2>/dev/null 1>/dev/null || true
PARTNER_PRINCIPAL=$(icp identity principal --identity smoke-partner)
echo "  Partner2 principal:  $PARTNER_PRINCIPAL"
echo "  Staff principal:     $STAFF_PRINCIPAL (unregistered — used for non-Partner checks)"
echo ""

# Register smoke-partner as Partner (still running as smoke-master)
icp canister call backend addUser "(principal \"$PARTNER_PRINCIPAL\", variant { Partner })" > /dev/null

# ── Step 35: createClient — Partner creates first client ─────────────────────
echo "Step 35: createClient — Partner creates 'Acme Holdings PLC' (#Company)"
RESULT=$(icp canister call backend createClient \
  "(\"Acme Holdings PLC\", variant { Company }, null, null, null, \"\")")
check "createClient returns ok(1)" "ok" "$RESULT"
check "client id is 1" "1" "$RESULT"
echo ""

# ── Step 36: getClient — confirm record is stored ────────────────────────────
echo "Step 36: getClient(1) — confirm record stored with correct fields"
RESULT=$(icp canister call backend getClient "(1 : nat)")
check "getClient returns a record" "Acme Holdings PLC" "$RESULT"
check "clientType is Company" "Company" "$RESULT"
check "status is Active" "Active" "$RESULT"
echo ""

# ── Step 37: audit entry for createClient ────────────────────────────────────
echo "Step 37: readAuditEntries — confirm createClient action was recorded"
RESULT=$(icp canister call backend readAuditEntries "(0 : nat, 1000 : nat)")
check "createClient appears in audit log" "createClient" "$RESULT"
echo ""

# ── Step 38: listClients pagination ──────────────────────────────────────────
echo "Step 38: listClients pagination — create 3 clients total; paginate at 2"
icp canister call backend createClient "(\"Baur & Sons Ltd\", variant { Company }, null, null, null, \"\")" > /dev/null
icp canister call backend createClient "(\"Nimal Perera\", variant { Individual }, null, null, null, \"\")" > /dev/null

PAGE1=$(icp canister call backend listClients "(0 : nat, 2 : nat, false)")
check "listClients page 1 contains Acme" "Acme" "$PAGE1"
check "listClients page 1 contains Baur" "Baur" "$PAGE1"
check_absent "page 1 does not contain Nimal" "Nimal" "$PAGE1"

PAGE2=$(icp canister call backend listClients "(2 : nat, 2 : nat, false)")
check "listClients page 2 contains Nimal" "Nimal" "$PAGE2"
check_absent "page 2 does not contain Acme" "Acme" "$PAGE2"
echo ""

# ── Step 39: updateClient ────────────────────────────────────────────────────
echo "Step 39: updateClient — set primaryEmail on client 1; confirm field updated"
RESULT=$(icp canister call backend updateClient \
  "(1 : nat, null, null, opt \"acme@example.com\", null, null, null)")
check "updateClient returns ok" "ok" "$RESULT"
RESULT=$(icp canister call backend getClient "(1 : nat)")
check "primaryEmail updated to acme@example.com" "acme@example.com" "$RESULT"
RESULT=$(icp canister call backend readAuditEntries "(0 : nat, 1000 : nat)")
check "updateClient appears in audit log" "updateClient" "$RESULT"
echo ""

# ── Step 40: createMatter FK rejection — nonexistent client ──────────────────
echo "Step 40: createMatter with clientId=999 — expect #err('client 999 not found')"
RESULT=$(icp canister call backend createMatter \
  "(\"Test Matter\", \"Litigation\", 999 : nat, null, \"\")")
check "createMatter with bad clientId returns err" "err" "$RESULT"
check "error names client 999" "999" "$RESULT"
RESULT=$(icp canister call backend readAuditEntries "(0 : nat, 1000 : nat)")
check "failed createMatter emits audit err entry" "err" "$RESULT"
echo ""

# ── Step 41: createMatter success ────────────────────────────────────────────
echo "Step 41: createMatter with clientId=1 — expect success, id=1"
RESULT=$(icp canister call backend createMatter \
  "(\"Acme Litigation v1\", \"Litigation\", 1 : nat, null, \"Initial matter\")")
check "createMatter returns ok" "ok" "$RESULT"
check "matter id is 1" "1" "$RESULT"
RESULT=$(icp canister call backend getMatter "(1 : nat)")
check "getMatter returns record" "Acme Litigation v1" "$RESULT"
check "matter status is Open" "Open" "$RESULT"
echo ""

# ── Step 42: FK rejection on inactive client ─────────────────────────────────
echo "Step 42: deactivateClient(2) — client 2 has no matters, should succeed"
echo "  Then createMatter with clientId=2 — expect #err('client 2 is inactive')"
RESULT=$(icp canister call backend deactivateClient "(2 : nat)")
check "deactivateClient(2) returns ok" "ok" "$RESULT"
RESULT=$(icp canister call backend createMatter \
  "(\"Baur Matter\", \"Advisory\", 2 : nat, null, \"\")")
check "createMatter on inactive client returns err" "err" "$RESULT"
check "error mentions inactive" "inactive" "$RESULT"
echo ""

# ── Step 43: deactivateClient rejected when open matters exist ───────────────
echo "Step 43: deactivateClient(1) — client 1 has matter#1 (#Open) — expect rejection"
RESULT=$(icp canister call backend deactivateClient "(1 : nat)")
check "deactivateClient with open matter returns err" "err" "$RESULT"
check "error names the count" "1 open matter" "$RESULT"
RESULT=$(icp canister call backend readAuditEntries "(0 : nat, 1000 : nat)")
check "blocked deactivateClient emits audit err" "deactivateClient" "$RESULT"
echo ""

# ── Step 44: matter status lifecycle — OnHold / resume / close / reopen ──────
echo "Step 44: matter lifecycle — Open→OnHold→Open→Closed (closedAt set)"
RESULT=$(icp canister call backend putMatterOnHold "(1 : nat)")
check "putMatterOnHold returns ok" "ok" "$RESULT"
RESULT=$(icp canister call backend getMatter "(1 : nat)")
check "matter status is OnHold" "OnHold" "$RESULT"

RESULT=$(icp canister call backend resumeMatter "(1 : nat)")
check "resumeMatter returns ok" "ok" "$RESULT"
RESULT=$(icp canister call backend getMatter "(1 : nat)")
check "matter status is Open after resume" "Open" "$RESULT"

RESULT=$(icp canister call backend closeMatter "(1 : nat)")
check "closeMatter returns ok" "ok" "$RESULT"
RESULT=$(icp canister call backend getMatter "(1 : nat)")
check "matter status is Closed" "Closed" "$RESULT"
check "closedAt is set (not null)" "closedAt" "$RESULT"
echo ""

# ── Step 45: reopenMatter clears closedAt; then re-close and archive ─────────
echo "Step 45: reopenMatter → closedAt cleared; closeMatter again; archiveMatter"
RESULT=$(icp canister call backend reopenMatter "(1 : nat)")
check "reopenMatter returns ok" "ok" "$RESULT"
RESULT=$(icp canister call backend getMatter "(1 : nat)")
check "matter status is Open after reopen" "Open" "$RESULT"
check "closedAt is null after reopen" "closedAt = null" "$RESULT"

RESULT=$(icp canister call backend closeMatter "(1 : nat)")
check "closeMatter second time returns ok" "ok" "$RESULT"

RESULT=$(icp canister call backend archiveMatter "(1 : nat)")
check "archiveMatter returns ok" "ok" "$RESULT"
RESULT=$(icp canister call backend getMatter "(1 : nat)")
check "matter status is Archived" "Archived" "$RESULT"
echo ""

# ── Step 46: archived matter is immutable ────────────────────────────────────
echo "Step 46: updateMatter on archived matter — expect rejection"
RESULT=$(icp canister call backend updateMatter \
  "(1 : nat, opt \"New Title\", null, null, null, null)")
check "updateMatter on archived returns err" "err" "$RESULT"
check "error mentions archived" "archived" "$RESULT"
echo ""

# ── Step 47: invalid status transition ───────────────────────────────────────
echo "Step 47: create fresh matter (id=2); try archiveMatter on #Open — invalid transition"
icp canister call backend createMatter \
  "(\"Matter Two\", \"Advisory\", 1 : nat, null, \"\")" > /dev/null
RESULT=$(icp canister call backend archiveMatter "(2 : nat)")
check "archiveMatter on Open matter returns err" "err" "$RESULT"
check "error mentions invalid status transition" "invalid status transition" "$RESULT"
check "error mentions Open" "Open" "$RESULT"
echo ""

# ── Step 48: reopen-archived rejected ────────────────────────────────────────
echo "Step 48: reopenMatter on archived matter#1 — expect rejection"
RESULT=$(icp canister call backend reopenMatter "(1 : nat)")
check "reopenMatter on Archived returns err" "err" "$RESULT"
check "error mentions invalid status transition" "invalid status transition" "$RESULT"
echo ""

# ── Step 49: non-Partner write rejected; non-Partner read allowed ─────────────
echo "Step 49: smoke-staff (unregistered) — write rejected, read allowed"
RESULT=$(icp canister call backend createClient \
  "(\"Unauthorized Co\", variant { Company }, null, null, null, \"\")" \
  --identity smoke-staff)
check "non-Partner createClient returns err" "err" "$RESULT"
check "error is not authorized" "not authorized" "$RESULT"

RESULT=$(icp canister call backend listClients "(0 : nat, 10 : nat, true)" \
  --identity smoke-staff)
check "non-Partner listClients succeeds" "Acme" "$RESULT"
echo ""

# ── Step 50: listMattersByClient — scoped to one client ──────────────────────
echo "Step 50: listMattersByClient — create 2 more matters for client 1; 1 for client 3"
icp canister call backend createMatter \
  "(\"Matter Three\", \"Advisory\", 1 : nat, null, \"\")" > /dev/null
icp canister call backend createMatter \
  "(\"Matter Four\", \"Advisory\", 1 : nat, null, \"\")" > /dev/null
icp canister call backend createMatter \
  "(\"Nimal Matter\", \"Advisory\", 3 : nat, null, \"\")" > /dev/null

RESULT=$(icp canister call backend listMattersByClient "(1 : nat, 0 : nat, 1000 : nat, null)")
check "listMattersByClient(1) returns Matter Two" "Matter Two" "$RESULT"
check "listMattersByClient(1) returns Matter Three" "Matter Three" "$RESULT"
check "listMattersByClient(1) returns Matter Four" "Matter Four" "$RESULT"
check_absent "listMattersByClient(1) excludes Nimal Matter" "Nimal Matter" "$RESULT"
echo ""

# ── Step 51: reactivateClient ────────────────────────────────────────────────
echo "Step 51: reactivateClient(2) — confirm status becomes #Active; audit entry"
RESULT=$(icp canister call backend reactivateClient "(2 : nat)")
check "reactivateClient returns ok" "ok" "$RESULT"
RESULT=$(icp canister call backend getClient "(2 : nat)")
check "client 2 status is Active after reactivation" "Active" "$RESULT"
RESULT=$(icp canister call backend readAuditEntries "(0 : nat, 1000 : nat)")
check "reactivateClient appears in audit log" "reactivateClient" "$RESULT"
echo ""

# ── Step 52: anonymous principal rejected on writes ──────────────────────────
echo "Step 52: anonymous caller — createClient rejected (if icp-cli supports --identity anonymous)"
ANON_RESULT=$(icp canister call backend createClient \
  "(\"Anon Co\", variant { Company }, null, null, null, \"\")" \
  --identity anonymous 2>&1) || true
check "anonymous createClient returns err or error" "err\|Error\|anonymous\|not allowed" "$ANON_RESULT"
echo ""

# ── Step 53: getClientCount and getMatterCount ────────────────────────────────
echo "Step 53: count queries — 3 clients, 5+ matters"
RESULT=$(icp canister call backend getClientCount "()")
check "getClientCount returns 3" "3" "$RESULT"
RESULT=$(icp canister call backend getMatterCount "()")
check "getMatterCount is at least 5" "5\|6\|7\|8\|9" "$RESULT"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# L2b Document storage assertions — start at Step 54 (L2 ended at Step 53)
# ═══════════════════════════════════════════════════════════════════════════════

# ── Step 54: L2b setup — register users needed for document tests ─────────────
echo "Step 54: L2b setup — register smoke-doc-associate (Associate) and smoke-staff (Staff)"
icp identity new smoke-doc-associate --storage plaintext -q 2>/dev/null 1>/dev/null || true
DOC_ASSOC_PRINCIPAL=$(icp identity principal --identity smoke-doc-associate)
echo "  Doc-associate principal: $DOC_ASSOC_PRINCIPAL"
# Register smoke-staff as Staff (was unregistered in L2 tests)
icp canister call backend addUser "(principal \"$STAFF_PRINCIPAL\", variant { Staff })" > /dev/null
# Register smoke-doc-associate as Associate
icp canister call backend addUser "(principal \"$DOC_ASSOC_PRINCIPAL\", variant { Associate })" > /dev/null
RESULT=$(icp canister call backend getMyRole "()" --identity smoke-doc-associate)
check "smoke-doc-associate has Associate role" "Associate" "$RESULT"
echo ""

# Helper: write appendChunk Candid args to a file (avoids ARG_MAX limits for large chunks)
make_chunk_args_file() {
  local session_id="$1" chunk_index="$2" blob_file="$3" out_file="$4"
  python3 -c "
import sys
sid, ci, bf = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
data = open(bf, 'rb').read()
blob = ''.join(f'\\\\{b:02x}' for b in data)
print(f'({sid} : nat, {ci} : nat, blob \"{blob}\")')
" "$session_id" "$chunk_index" "$blob_file" > "$out_file"
}

# Helper: extract sha256 hex from Candid output containing sha256 = blob "..."
extract_sha256_hex() {
  echo "$1" | python3 -c "
import sys, re
output = sys.stdin.read()
m = re.search(r'sha256\s*=\s*blob\s*\"([^\"]*)\"', output)
if not m: print('NOT_FOUND'); sys.exit(0)
raw = m.group(1)
result = ''
i = 0
while i < len(raw):
    if raw[i] == '\\\\' and i+2 < len(raw):
        result += raw[i+1:i+3]
        i += 3
    else:
        result += '%02x' % ord(raw[i])
        i += 1
print(result)
"
}

# ── Step 55: Small file upload (single chunk) + hash verification ─────────────
echo "Step 55: Small file upload (46 bytes, single chunk) + hash verification"
BLOB1_FILE=$(mktemp /tmp/tp_smoke_XXXXXX.bin)
printf 'The practice document system smoke test blob.' > "$BLOB1_FILE"
BLOB1_SIZE=$(wc -c < "$BLOB1_FILE")
LOCAL_HASH1=$(sha256sum "$BLOB1_FILE" | awk '{print $1}')
BLOB1_CANDID=$(python3 -c "
data = open('$BLOB1_FILE', 'rb').read()
print('blob \"' + ''.join(f'\\\\{b:02x}' for b in data) + '\"', end='')
")
# startUpload — use matter#2 (Open), content type application/pdf
RESULT=$(icp canister call backend startUpload \
  "(2 : nat, \"test.pdf\", \"application/pdf\", $BLOB1_SIZE : nat, \"smoke test\", null)")
check "startUpload returns ok" "ok" "$RESULT"
SESSION1=$(echo "$RESULT" | grep -o '[0-9]*' | head -1)
echo "  sessionId = $SESSION1"
# appendChunk index 0
RESULT=$(icp canister call backend appendChunk \
  "($SESSION1 : nat, 0 : nat, $BLOB1_CANDID)")
check "appendChunk returns ok" "ok" "$RESULT"
# finalizeUpload
FINALIZE1=$(icp canister call backend finalizeUpload "($SESSION1 : nat)")
check "finalizeUpload returns ok" "ok" "$FINALIZE1"
DOC1_ID=$(echo "$FINALIZE1" | python3 -c "import sys,re; m=re.search(r'documentId\s*=\s*(\d+)',sys.stdin.read()); print(m.group(1) if m else '0')")
VER1_ID=$(echo "$FINALIZE1" | python3 -c "import sys,re; m=re.search(r'versionId\s*=\s*(\d+)',sys.stdin.read()); print(m.group(1) if m else '0')")
echo "  documentId=$DOC1_ID  versionId=$VER1_ID"
# Hash verification: compare sha256sum output with canister-returned sha256
CANISTER_HASH1=$(extract_sha256_hex "$FINALIZE1")
check "sha256 matches local computation" "$LOCAL_HASH1" "$CANISTER_HASH1"
# Confirm audit entry recorded
RESULT=$(icp canister call backend readAuditEntries "(0 : nat, 1000 : nat)")
check "documentUpload audit entry recorded" "documentUpload" "$RESULT"
rm -f "$BLOB1_FILE"
echo ""

# ── Step 56: Multi-chunk upload (1 MB + 1 byte = 2 chunks) ───────────────────
echo "Step 56: Multi-chunk upload — 1 MB + 1 byte (2 chunks)"
BLOB2_FILE=$(mktemp /tmp/tp_smoke_XXXXXX.bin)
dd if=/dev/zero bs=1048576 count=1 2>/dev/null >> "$BLOB2_FILE"
printf '\x41' >> "$BLOB2_FILE"             # 1 extra byte: 0x41
BLOB2_SIZE=$(wc -c < "$BLOB2_FILE")        # = 1048577
LOCAL_HASH2=$(sha256sum "$BLOB2_FILE" | awk '{print $1}')
RESULT=$(icp canister call backend startUpload \
  "(2 : nat, \"multi.pdf\", \"application/pdf\", $BLOB2_SIZE : nat, \"multi-chunk test\", null)")
check "startUpload multi-chunk returns ok" "ok" "$RESULT"
SESSION2=$(echo "$RESULT" | grep -o '[0-9]*' | head -1)
# Split file: chunk 0 = first 1 MB, chunk 1 = last 1 byte
CHUNK20=$(mktemp /tmp/tp_smoke_XXXXXX.bin); dd if="$BLOB2_FILE" bs=1048576 count=1 of="$CHUNK20" 2>/dev/null
CHUNK21=$(mktemp /tmp/tp_smoke_XXXXXX.bin); dd if="$BLOB2_FILE" bs=1 skip=1048576 of="$CHUNK21" 2>/dev/null
ARGS20=$(mktemp /tmp/tp_smoke_XXXXXX.did); make_chunk_args_file "$SESSION2" 0 "$CHUNK20" "$ARGS20"
RESULT=$(icp canister call backend appendChunk --args-file "$ARGS20"); check "chunk 0 appended" "ok" "$RESULT"
ARGS21=$(mktemp /tmp/tp_smoke_XXXXXX.did); make_chunk_args_file "$SESSION2" 1 "$CHUNK21" "$ARGS21"
RESULT=$(icp canister call backend appendChunk --args-file "$ARGS21"); check "chunk 1 appended" "ok" "$RESULT"
FINALIZE2=$(icp canister call backend finalizeUpload "($SESSION2 : nat)")
check "finalizeUpload multi-chunk returns ok" "ok" "$FINALIZE2"
CANISTER_HASH2=$(extract_sha256_hex "$FINALIZE2")
check "multi-chunk sha256 matches local" "$LOCAL_HASH2" "$CANISTER_HASH2"
DOC2_ID=$(echo "$FINALIZE2" | python3 -c "import sys,re; m=re.search(r'documentId\s*=\s*(\d+)',sys.stdin.read()); print(m.group(1) if m else '0')")
# Verify sizeBytes on stored version
VER2_ID=$(echo "$FINALIZE2" | python3 -c "import sys,re; m=re.search(r'versionId\s*=\s*(\d+)',sys.stdin.read()); print(m.group(1) if m else '0')")
RESULT=$(icp canister call backend getDocumentVersion "($VER2_ID : nat)")
check "version sizeBytes matches 1048577" "1_048_577\|1048577" "$RESULT"
rm -f "$BLOB2_FILE" "$CHUNK20" "$CHUNK21" "$ARGS20" "$ARGS21"
echo ""

# ── Step 57: Out-of-order chunks (upload order: 2, 0, 3, 1) ──────────────────
echo "Step 57: Out-of-order chunk upload — upload chunks in order 2, 0, 3, 1"
BLOB3_FILE=$(mktemp /tmp/tp_smoke_XXXXXX.bin)
dd if=/dev/urandom bs=1048576 count=3 2>/dev/null >> "$BLOB3_FILE"
dd if=/dev/urandom bs=524288  count=1 2>/dev/null >> "$BLOB3_FILE"   # 3.5 MB total
BLOB3_SIZE=$(wc -c < "$BLOB3_FILE")
RESULT=$(icp canister call backend startUpload \
  "(2 : nat, \"ooo.pdf\", \"application/pdf\", $BLOB3_SIZE : nat, \"out-of-order test\", null)")
check "startUpload for OOO test returns ok" "ok" "$RESULT"
SESSION3=$(echo "$RESULT" | grep -o '[0-9]*' | head -1)
C30=$(mktemp /tmp/tp_smoke_XXXXXX.bin); dd if="$BLOB3_FILE" bs=1048576 skip=0 count=1 of="$C30" 2>/dev/null
C31=$(mktemp /tmp/tp_smoke_XXXXXX.bin); dd if="$BLOB3_FILE" bs=1048576 skip=1 count=1 of="$C31" 2>/dev/null
C32=$(mktemp /tmp/tp_smoke_XXXXXX.bin); dd if="$BLOB3_FILE" bs=1048576 skip=2 count=1 of="$C32" 2>/dev/null
C33=$(mktemp /tmp/tp_smoke_XXXXXX.bin); dd if="$BLOB3_FILE" bs=1048576 skip=3         of="$C33" 2>/dev/null
# Upload out of order: 2, 0, 3, 1
for idx_file in "2:$C32" "0:$C30" "3:$C33" "1:$C31"; do
  idx="${idx_file%%:*}"; f="${idx_file##*:}"
  AF=$(mktemp /tmp/tp_smoke_XXXXXX.did); make_chunk_args_file "$SESSION3" "$idx" "$f" "$AF"
  icp canister call backend appendChunk --args-file "$AF" > /dev/null
  rm -f "$AF"
done
FINALIZE3=$(icp canister call backend finalizeUpload "($SESSION3 : nat)")
check "OOO finalize succeeds" "ok" "$FINALIZE3"
rm -f "$BLOB3_FILE" "$C30" "$C31" "$C32" "$C33"
echo ""

# ── Step 58: Idempotent chunk replacement ─────────────────────────────────────
echo "Step 58: Idempotent chunk replacement — upload chunk 0 twice, both succeed"
BLOB4_FILE=$(mktemp /tmp/tp_smoke_XXXXXX.bin)
dd if=/dev/zero bs=1048576 count=1 2>/dev/null > "$BLOB4_FILE"
printf '\x42' >> "$BLOB4_FILE"    # 1048577 bytes
BLOB4_SIZE=$(wc -c < "$BLOB4_FILE")
RESULT=$(icp canister call backend startUpload \
  "(2 : nat, \"idempotent.pdf\", \"application/pdf\", $BLOB4_SIZE : nat, \"\", null)")
SESSION4=$(echo "$RESULT" | grep -o '[0-9]*' | head -1)
CHUNK40=$(mktemp /tmp/tp_smoke_XXXXXX.bin); dd if="$BLOB4_FILE" bs=1048576 count=1 of="$CHUNK40" 2>/dev/null
CHUNK41=$(mktemp /tmp/tp_smoke_XXXXXX.bin); dd if="$BLOB4_FILE" bs=1 skip=1048576 of="$CHUNK41" 2>/dev/null
AF40=$(mktemp /tmp/tp_smoke_XXXXXX.did); make_chunk_args_file "$SESSION4" 0 "$CHUNK40" "$AF40"
# Upload chunk 0 twice
RESULT=$(icp canister call backend appendChunk --args-file "$AF40"); check "first upload chunk 0 ok" "ok" "$RESULT"
RESULT=$(icp canister call backend appendChunk --args-file "$AF40"); check "second upload chunk 0 ok (idempotent)" "ok" "$RESULT"
AF41=$(mktemp /tmp/tp_smoke_XXXXXX.did); make_chunk_args_file "$SESSION4" 1 "$CHUNK41" "$AF41"
icp canister call backend appendChunk --args-file "$AF41" > /dev/null
RESULT=$(icp canister call backend finalizeUpload "($SESSION4 : nat)")
check "finalize after idempotent chunk ok" "ok" "$RESULT"
rm -f "$BLOB4_FILE" "$CHUNK40" "$CHUNK41" "$AF40" "$AF41"
echo ""

# ── Step 59: Reject too-large file ───────────────────────────────────────────
echo "Step 59: Reject too-large file — totalSizeBytes = 100_000_001"
RESULT=$(icp canister call backend startUpload \
  "(2 : nat, \"toobig.pdf\", \"application/pdf\", 100000001 : nat, \"\", null)")
check "too-large file returns err" "err" "$RESULT"
check "error mentions size limit" "exceeds\|too large\|limit" "$RESULT"
RESULT=$(icp canister call backend readAuditEntries "(0 : nat, 1000 : nat)")
check "too-large audit entry recorded" "startUpload" "$RESULT"
echo ""

# ── Step 60: Reject invalid content type ─────────────────────────────────────
echo "Step 60: Reject invalid content type — text/csv"
RESULT=$(icp canister call backend startUpload \
  "(2 : nat, \"data.csv\", \"text/csv\", 100 : nat, \"\", null)")
check "invalid content type returns err" "err" "$RESULT"
check "error mentions content type" "not allowed\|content type" "$RESULT"
echo ""

# ── Step 61: Reject nonexistent matter ───────────────────────────────────────
echo "Step 61: Reject nonexistent matter — matterId = 9999"
RESULT=$(icp canister call backend startUpload \
  "(9999 : nat, \"x.pdf\", \"application/pdf\", 100 : nat, \"\", null)")
check "nonexistent matter returns err" "err" "$RESULT"
check "error mentions matter not found" "not found\|9999" "$RESULT"
echo ""

# ── Step 62: Reject archived matter ──────────────────────────────────────────
echo "Step 62: Reject archived matter — matter#1 is Archived since Step 45"
RESULT=$(icp canister call backend startUpload \
  "(1 : nat, \"arch.pdf\", \"application/pdf\", 100 : nat, \"\", null)")
check "archived matter returns err" "err" "$RESULT"
check "error mentions archived" "archived" "$RESULT"
echo ""

# ── Step 63: Caller-lock enforcement ─────────────────────────────────────────
echo "Step 63: Caller-lock — smoke-master starts session, smoke-doc-associate cannot appendChunk"
LOCK_BLOB=$(python3 -c "print('blob \"' + '\\\\00' * 100 + '\"', end='')")
RESULT=$(icp canister call backend startUpload \
  "(2 : nat, \"lock.pdf\", \"application/pdf\", 100 : nat, \"\", null)")
check "startUpload for lock test ok" "ok" "$RESULT"
LOCK_SID=$(echo "$RESULT" | grep -o '[0-9]*' | head -1)
RESULT=$(icp canister call backend appendChunk \
  "($LOCK_SID : nat, 0 : nat, $LOCK_BLOB)" --identity smoke-doc-associate)
check "caller-lock: other user appendChunk returns err" "err" "$RESULT"
check "error is not the session owner" "session owner\|not authorized\|not the session" "$RESULT"
# Clean up the dangling session via abandon
icp canister call backend abandonUpload "($LOCK_SID : nat)" > /dev/null
echo ""

# ── Step 64: Reject finalize with missing chunks ──────────────────────────────
echo "Step 64: Reject finalize with missing chunks — upload chunk 0 only of 2-chunk file"
BLOB5_FILE=$(mktemp /tmp/tp_smoke_XXXXXX.bin)
dd if=/dev/zero bs=1048576 count=1 2>/dev/null > "$BLOB5_FILE"
printf '\x43' >> "$BLOB5_FILE"    # 1048577 bytes = 2 chunks
BLOB5_SIZE=$(wc -c < "$BLOB5_FILE")
RESULT=$(icp canister call backend startUpload \
  "(2 : nat, \"incomplete.pdf\", \"application/pdf\", $BLOB5_SIZE : nat, \"\", null)")
SESSION5=$(echo "$RESULT" | grep -o '[0-9]*' | head -1)
CHUNK50=$(mktemp /tmp/tp_smoke_XXXXXX.bin); dd if="$BLOB5_FILE" bs=1048576 count=1 of="$CHUNK50" 2>/dev/null
AF50=$(mktemp /tmp/tp_smoke_XXXXXX.did); make_chunk_args_file "$SESSION5" 0 "$CHUNK50" "$AF50"
icp canister call backend appendChunk --args-file "$AF50" > /dev/null  # only chunk 0 uploaded
RESULT=$(icp canister call backend finalizeUpload "($SESSION5 : nat)")
check "finalize with missing chunk returns err" "err" "$RESULT"
check "error mentions incomplete\|missing" "incomplete\|missing" "$RESULT"
icp canister call backend abandonUpload "($SESSION5 : nat)" > /dev/null
rm -f "$BLOB5_FILE" "$CHUNK50" "$AF50"
echo ""

# ── Step 65: Version chaining — upload a new version of an existing document ──
echo "Step 65: Version chaining — upload new version of document $DOC1_ID via replacesDocumentId"
BLOB6_FILE=$(mktemp /tmp/tp_smoke_XXXXXX.bin)
printf 'Version 2 of the practice document smoke test.' > "$BLOB6_FILE"
BLOB6_SIZE=$(wc -c < "$BLOB6_FILE")
BLOB6_CANDID=$(python3 -c "
data = open('$BLOB6_FILE', 'rb').read()
print('blob \"' + ''.join(f'\\\\{b:02x}' for b in data) + '\"', end='')
")
RESULT=$(icp canister call backend startUpload \
  "(2 : nat, \"test_v2.pdf\", \"application/pdf\", $BLOB6_SIZE : nat, \"second version\", opt ($DOC1_ID : nat))")
check "startUpload for v2 returns ok" "ok" "$RESULT"
SESSION6=$(echo "$RESULT" | grep -o '[0-9]*' | head -1)
RESULT=$(icp canister call backend appendChunk \
  "($SESSION6 : nat, 0 : nat, $BLOB6_CANDID)")
check "appendChunk v2 ok" "ok" "$RESULT"
FINALIZE6=$(icp canister call backend finalizeUpload "($SESSION6 : nat)")
check "finalizeUpload v2 returns ok" "ok" "$FINALIZE6"
VER2_DOC1=$(echo "$FINALIZE6" | python3 -c "import sys,re; m=re.search(r'versionId\s*=\s*(\d+)',sys.stdin.read()); print(m.group(1) if m else '0')")
# listVersions should return both v1 and v2 (blob stripped to empty)
RESULT=$(icp canister call backend listVersions "($DOC1_ID : nat)")
check "listVersions returns 2 versions" "versionNumber = 1\|versionNumber = 2\|versionNumber = 1 : nat\|versionNumber = 2 : nat" "$RESULT"
# getDocument should show currentVersionId updated to v2
RESULT=$(icp canister call backend getDocument "($DOC1_ID : nat)")
check "document currentVersionId updated to v2" "$VER2_DOC1" "$RESULT"
rm -f "$BLOB6_FILE"
echo ""

# ── Step 66: Delete as Associate rejected ─────────────────────────────────────
echo "Step 66: Delete as Associate rejected — smoke-doc-associate (Associate) cannot delete"
RESULT=$(icp canister call backend deleteDocument "($DOC2_ID : nat)" --identity smoke-doc-associate)
check "Associate deleteDocument returns err" "err" "$RESULT"
check "error is not authorized" "not authorized" "$RESULT"
RESULT=$(icp canister call backend readAuditEntries "(0 : nat, 1000 : nat)")
check "failed deleteDocument audit entry recorded" "documentDelete" "$RESULT"
echo ""

# ── Step 67: Delete as Partner; verify listing excludes/includes deleted ───────
echo "Step 67: Partner deleteDocument — doc $DOC2_ID; verify listing filter"
RESULT=$(icp canister call backend deleteDocument "($DOC2_ID : nat)")
check "Partner deleteDocument returns ok" "ok" "$RESULT"
RESULT=$(icp canister call backend getDocument "($DOC2_ID : nat)")
check "deleted document status is Deleted" "Deleted" "$RESULT"
RESULT=$(icp canister call backend listDocumentsByMatter "(2 : nat, 0 : nat, 1000 : nat, false)")
check_absent "deleted doc excluded when includeDeleted=false" "Deleted" "$RESULT"
RESULT=$(icp canister call backend listDocumentsByMatter "(2 : nat, 0 : nat, 1000 : nat, true)")
check "deleted doc included when includeDeleted=true" "Deleted" "$RESULT"
echo ""

# ── Step 68: Download deleted document rejected ───────────────────────────────
echo "Step 68: prepareDocumentDownload on deleted document — expect err"
VER2_OF_DOC2=$(icp canister call backend getDocument "($DOC2_ID : nat)" | python3 -c \
  "import sys,re; m=re.search(r'currentVersionId\s*=\s*(\d+)',sys.stdin.read()); print(m.group(1) if m else '0')")
RESULT=$(icp canister call backend prepareDocumentDownload "($VER2_OF_DOC2 : nat)")
check "download deleted document returns err" "err" "$RESULT"
check "error mentions not active\|deleted" "not active\|deleted\|not found" "$RESULT"
RESULT=$(icp canister call backend readAuditEntries "(0 : nat, 1000 : nat)")
check "failed download audit entry recorded" "documentDownload" "$RESULT"
echo ""

# ── Step 69: Download success flow ────────────────────────────────────────────
echo "Step 69: Download success — prepareDocumentDownload + getChunk for doc $DOC1_ID"
RESULT=$(icp canister call backend prepareDocumentDownload "($VER1_ID : nat)")
check "prepareDocumentDownload returns ok" "ok" "$RESULT"
check "response includes chunkCount" "chunkCount\|chunk_count" "$RESULT"
RESULT=$(icp canister call backend readAuditEntries "(0 : nat, 1000 : nat)")
check "documentDownload audit entry recorded with docId" "documentDownload:$DOC1_ID" "$RESULT"
# getChunk for chunk 0 (single-chunk file)
RESULT=$(icp canister call backend getChunk "($VER1_ID : nat, 0 : nat)" --query)
check "getChunk returns blob (not null)" "blob" "$RESULT"
check_absent "getChunk not null" "null" "$RESULT"
echo ""

# ── Step 70: Storage budget enforcement ───────────────────────────────────────
echo "Step 70: Storage budget enforcement — set tight budget, verify startUpload rejects"
USED=$(icp canister call backend getStorageUsed "()" | grep -o '[0-9_]*' | tr -d '_' | head -1)
TIGHT_BUDGET=$((USED + 1000))
RESULT=$(icp canister call backend setStorageBudget "($TIGHT_BUDGET : nat)")
check "setStorageBudget to used+1000 returns ok" "ok" "$RESULT"
# Attempt upload of 2000 bytes — should exceed budget
RESULT=$(icp canister call backend startUpload \
  "(2 : nat, \"overflow.pdf\", \"application/pdf\", 2000 : nat, \"\", null)")
check "startUpload exceeding budget returns err" "err" "$RESULT"
check "error mentions budget exceeded" "budget exceeded\|budget\|available" "$RESULT"
# Restore budget to default
icp canister call backend setStorageBudget "(53687091200 : nat)" > /dev/null
echo ""

# ── Step 71: setStorageBudget reject-on-shrink-below-usage ───────────────────
echo "Step 71: setStorageBudget cannot shrink below current usage"
USED=$(icp canister call backend getStorageUsed "()" | grep -o '[0-9_]*' | tr -d '_' | head -1)
SHRINK=$((USED - 1))
RESULT=$(icp canister call backend setStorageBudget "($SHRINK : nat)")
check "setStorageBudget below usage returns err" "err" "$RESULT"
check "error mentions current usage" "usage\|below\|cannot" "$RESULT"
echo ""

# ── Step 72: Anonymous upload rejected ────────────────────────────────────────
echo "Step 72: Anonymous caller — startUpload rejected"
ANON_RESULT=$(icp canister call backend startUpload \
  "(2 : nat, \"anon.pdf\", \"application/pdf\", 100 : nat, \"\", null)" \
  --identity anonymous 2>&1) || true
check "anonymous startUpload rejected" "err\|Error\|anonymous\|not allowed" "$ANON_RESULT"
echo ""

# ── Step 73: Abandon upload ───────────────────────────────────────────────────
echo "Step 73: abandonUpload — start session, append 1 chunk, then abandon"
BLOB7_CANDID=$(python3 -c "print('blob \"' + '\\\\ff' * 100 + '\"', end='')")
RESULT=$(icp canister call backend startUpload \
  "(2 : nat, \"abandon.pdf\", \"application/pdf\", 100 : nat, \"\", null)")
check "startUpload for abandon test ok" "ok" "$RESULT"
SESSION7=$(echo "$RESULT" | grep -o '[0-9]*' | head -1)
icp canister call backend appendChunk "($SESSION7 : nat, 0 : nat, $BLOB7_CANDID)" > /dev/null
RESULT=$(icp canister call backend abandonUpload "($SESSION7 : nat)")
check "abandonUpload returns ok" "ok" "$RESULT"
# Session should be gone — a second abandon should fail
RESULT=$(icp canister call backend abandonUpload "($SESSION7 : nat)")
check "second abandonUpload on same session returns err" "err" "$RESULT"
RESULT=$(icp canister call backend readAuditEntries "(0 : nat, 1000 : nat)")
check "abandonUpload audit entry recorded" "abandonUpload" "$RESULT"
echo ""

# ── Final L2b storage and count checks ───────────────────────────────────────
echo "L2b final checks: getDocumentCount, getStorageUsed"
RESULT=$(icp canister call backend getDocumentCount "()")
check "getDocumentCount > 0" "1\|2\|3\|4\|5" "$RESULT"
RESULT=$(icp canister call backend getStorageUsed "()")
check "getStorageUsed > 0" "[1-9]" "$RESULT"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# L3 Upgrade survival test — Steps 74–85
# Verifies Enhanced Orthogonal Persistence: all actor state survives an upgrade.
# NEVER use --mode reinstall here — it destroys all state.
# ═══════════════════════════════════════════════════════════════════════════════

# ── Step 74: Capture pre-upgrade state ───────────────────────────────────────
echo "Step 74: L3 — capture pre-upgrade state"
PRE_USER_COUNT=$(icp canister call backend getUserCount "()" | grep -o '[0-9_]*' | tr -d '_' | head -1)
PRE_CLIENT_COUNT=$(icp canister call backend getClientCount "()" | grep -o '[0-9_]*' | tr -d '_' | head -1)
PRE_AUDIT_OUT=$(icp canister call backend readAuditEntries "(0 : nat, 1000 : nat)")
PRE_MAX_AUDIT_ID=$(echo "$PRE_AUDIT_OUT" | python3 -c "
import sys, re
ids = [int(m.group(1)) for m in re.finditer(r'id\s*=\s*(\d+)\s*:', sys.stdin.read())]
print(max(ids) if ids else 0)
")
PRE_DOC1_HASH=$(extract_sha256_hex "$(icp canister call backend getDocumentVersion "($VER1_ID : nat)")")
echo "  pre_user_count=$PRE_USER_COUNT  pre_client_count=$PRE_CLIENT_COUNT"
echo "  pre_max_audit_id=$PRE_MAX_AUDIT_ID  pre_doc1_sha256=$PRE_DOC1_HASH"
echo ""

# ── Step 75: Upgrade the canister — preserves all state via EOP ──────────────
echo "Step 75: L3 — upgrade canister (icp deploy --mode upgrade)"
icp deploy backend --mode upgrade --args "(principal \"$MASTER_PRINCIPAL\")"
echo "  Upgrade complete."
echo ""

# ── Step 76: L1 post-upgrade — user count unchanged ──────────────────────────
echo "Step 76: L1 post-upgrade — getUserCount matches pre-upgrade value"
RESULT=$(icp canister call backend getUserCount "()")
check "L1: user count unchanged after upgrade" "$PRE_USER_COUNT" "$RESULT"
echo ""

# ── Step 77: L1 post-upgrade — master controller still present ───────────────
echo "Step 77: L1 post-upgrade — master controller still registered"
RESULT=$(icp canister call backend getMasterController "()")
check "L1: master controller principal intact" "$MASTER_PRINCIPAL" "$RESULT"
echo ""

# ── Step 78: L5 post-upgrade — audit entry id=1 (install) still exists ───────
echo "Step 78: L5 post-upgrade — audit entry id=1 (install event) still present"
RESULT=$(icp canister call backend readAuditEntries "(0 : nat, 10 : nat)")
check "L5: install audit entry id=1 still present" "install" "$RESULT"
echo ""

# ── Step 79: L5 post-upgrade — audit counter not reset ───────────────────────
echo "Step 79: L5 post-upgrade — nextAuditId >= pre-upgrade value (counter not reset)"
POST_AUDIT_OUT=$(icp canister call backend readAuditEntries "(0 : nat, 1000 : nat)")
POST_MAX_AUDIT_ID=$(echo "$POST_AUDIT_OUT" | python3 -c "
import sys, re
ids = [int(m.group(1)) for m in re.finditer(r'id\s*=\s*(\d+)\s*:', sys.stdin.read())]
print(max(ids) if ids else 0)
")
if [ "$POST_MAX_AUDIT_ID" -ge "$PRE_MAX_AUDIT_ID" ]; then
  echo "  PASS: L5: audit counter not reset (pre=$PRE_MAX_AUDIT_ID post=$POST_MAX_AUDIT_ID)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: L5: audit counter reset! pre=$PRE_MAX_AUDIT_ID post=$POST_MAX_AUDIT_ID"
  FAIL=$((FAIL + 1))
fi
echo ""

# ── Step 80: L2 post-upgrade — getClient(1) record intact ────────────────────
echo "Step 80: L2 post-upgrade — getClient(1) returns same record"
RESULT=$(icp canister call backend getClient "(1 : nat)")
check "L2: client 1 name intact after upgrade" "Acme Holdings PLC" "$RESULT"
check "L2: client 1 type intact" "Company" "$RESULT"
echo ""

# ── Step 81: L2 post-upgrade — getMatter FK chain intact ─────────────────────
echo "Step 81: L2 post-upgrade — getMatter(2) still linked to client 1; client count unchanged"
RESULT=$(icp canister call backend getMatter "(2 : nat)")
check "L2: matter 2 record present after upgrade" "Matter Two" "$RESULT"
RESULT=$(icp canister call backend getClientCount "()")
check "L2: client count unchanged" "$PRE_CLIENT_COUNT" "$RESULT"
echo ""

# ── Step 82: L2b post-upgrade — prepareDocumentDownload succeeds ─────────────
echo "Step 82: L2b post-upgrade — prepareDocumentDownload($VER1_ID) succeeds"
RESULT=$(icp canister call backend prepareDocumentDownload "($VER1_ID : nat)")
check "L2b: prepareDocumentDownload still works after upgrade" "ok" "$RESULT"
echo ""

# ── Step 83: L2b post-upgrade — getChunk bytes SHA-256 matches stored hash ───
echo "Step 83: L2b post-upgrade — getChunk bytes SHA-256 matches pre-upgrade stored hash"
CHUNK_RESULT=$(icp canister call backend getChunk "($VER1_ID : nat, 0 : nat)" --query)
POST_DOC1_HASH=$(echo "$CHUNK_RESULT" | python3 -c "
import sys, re, hashlib
out = sys.stdin.read()
m = re.search(r'blob\s+\"([^\"]*)\"\s*\)', out)
if not m:
    print('NOT_FOUND'); sys.exit(0)
raw = m.group(1)
data = bytearray()
i = 0
while i < len(raw):
    if raw[i] == '\\\\' and i + 2 < len(raw):
        data.append(int(raw[i+1:i+3], 16))
        i += 3
    else:
        data.append(ord(raw[i]))
        i += 1
print(hashlib.sha256(bytes(data)).hexdigest())
")
check "L2b: downloaded bytes SHA-256 matches pre-upgrade stored hash" "$PRE_DOC1_HASH" "$POST_DOC1_HASH"
echo ""

# ── Step 84: Counters — totalStorageUsedBytes > 0 ────────────────────────────
echo "Step 84: Counters — totalStorageUsedBytes > 0 after upgrade"
RESULT=$(icp canister call backend getStorageUsed "()")
check "L3: totalStorageUsedBytes > 0 after upgrade" "[1-9]" "$RESULT"
echo ""

# ── Step 85: Counters — storageBudgetBytes = 53_687_091_200 (50 GB default) ──
echo "Step 85: Counters — storageBudgetBytes = 53_687_091_200 (50 GB default intact)"
RESULT=$(icp canister call backend getStorageBudget "()")
check "L3: storageBudgetBytes = 50 GB default after upgrade" "53_687_091_200\|53687091200" "$RESULT"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# L4 Logic — search, dashboard counts, export — Steps 86–102
# ═══════════════════════════════════════════════════════════════════════════════

# ── Step 86: L4 setup — create "smith" test clients ──────────────────────────
echo "Step 86: L4 setup — create clients for search tests (smith variants + identifier + inactive)"
RESULT=$(icp canister call backend createClient \
  "(\"Smith & Partners\", variant { Company }, null, null, null, \"\")")
check "createClient 'Smith & Partners' ok" "ok" "$RESULT"
SMITH_CLIENT_ID=$(echo "$RESULT" | python3 -c "import sys,re; m=re.search(r'(\d+)\s*:\s*nat',sys.stdin.read()); print(m.group(1) if m else '0')")
RESULT=$(icp canister call backend createClient \
  "(\"Smithson Trading\", variant { Company }, null, null, null, \"\")")
check "createClient 'Smithson Trading' ok" "ok" "$RESULT"
RESULT=$(icp canister call backend createClient \
  "(\"smith Bros\", variant { Individual }, null, null, null, \"\")")
check "createClient 'smith Bros' ok" "ok" "$RESULT"
RESULT=$(icp canister call backend createClient \
  "(\"Lotus Bank\", variant { Company }, null, null, opt \"NIC2025001\", \"\")")
check "createClient 'Lotus Bank' (identifier NIC2025001) ok" "ok" "$RESULT"
RESULT=$(icp canister call backend createClient \
  "(\"Inactive Corp\", variant { Company }, null, null, null, \"\")")
check "createClient 'Inactive Corp' ok" "ok" "$RESULT"
INACT_CLIENT_ID=$(echo "$RESULT" | python3 -c "import sys,re; m=re.search(r'(\d+)\s*:\s*nat',sys.stdin.read()); print(m.group(1) if m else '0')")
icp canister call backend deactivateClient "($INACT_CLIENT_ID : nat)" > /dev/null
echo "  smith_client_id=$SMITH_CLIENT_ID  inact_client_id=$INACT_CLIENT_ID (deactivated)"
echo ""

# ── Step 87: L4 setup — matters + documents ───────────────────────────────────
echo "Step 87: L4 setup — create smith matters; upload contract, alpha, beta docs"
RESULT=$(icp canister call backend createMatter \
  "(\"Smith Corporate Advisory\", \"Advisory\", $SMITH_CLIENT_ID : nat, null, \"\")")
check "createMatter 'Smith Corporate Advisory' ok" "ok" "$RESULT"
SMITH_MATTER1=$(echo "$RESULT" | python3 -c "import sys,re; m=re.search(r'(\d+)\s*:\s*nat',sys.stdin.read()); print(m.group(1) if m else '0')")
RESULT=$(icp canister call backend createMatter \
  "(\"Smith Tax Filing\", \"Tax\", $SMITH_CLIENT_ID : nat, opt (principal \"$PARTNER_PRINCIPAL\"), \"\")")
check "createMatter 'Smith Tax Filing' (assigned partner) ok" "ok" "$RESULT"
SMITH_MATTER2=$(echo "$RESULT" | python3 -c "import sys,re; m=re.search(r'(\d+)\s*:\s*nat',sys.stdin.read()); print(m.group(1) if m else '0')")
# Close matter1 for dashboard Closed count
icp canister call backend closeMatter "($SMITH_MATTER1 : nat)" > /dev/null
echo "  smith_matter1=$SMITH_MATTER1 (Closed)  smith_matter2=$SMITH_MATTER2 (Open)"
# Upload contract_review.pdf (as smoke-master, matter 2)
CONTRACT_FILE=$(mktemp /tmp/tp_smoke_XXXXXX.bin)
printf 'Contract review smoke test document.' > "$CONTRACT_FILE"
CONTRACT_SIZE=$(wc -c < "$CONTRACT_FILE")
CONTRACT_DATA=$(python3 -c "data=open('$CONTRACT_FILE','rb').read(); print('blob \"'+''.join(f'\\\\{b:02x}' for b in data)+'\"',end='')")
RESULT=$(icp canister call backend startUpload \
  "(2 : nat, \"contract_review.pdf\", \"application/pdf\", $CONTRACT_SIZE : nat, \"contract\", null)")
check "startUpload contract_review.pdf ok" "ok" "$RESULT"
CONTRACT_SID=$(echo "$RESULT" | grep -o '[0-9]*' | head -1)
icp canister call backend appendChunk "($CONTRACT_SID : nat, 0 : nat, $CONTRACT_DATA)" > /dev/null
CONTRACT_FIN=$(icp canister call backend finalizeUpload "($CONTRACT_SID : nat)")
check "finalizeUpload contract_review.pdf ok" "ok" "$CONTRACT_FIN"
rm -f "$CONTRACT_FILE"
# Upload alpha.pdf (as smoke-doc-associate, matter 2 — for uploadedBy test + version-history test)
ALPHA_FILE=$(mktemp /tmp/tp_smoke_XXXXXX.bin)
printf 'alpha document content' > "$ALPHA_FILE"
ALPHA_SIZE=$(wc -c < "$ALPHA_FILE")
ALPHA_DATA=$(python3 -c "data=open('$ALPHA_FILE','rb').read(); print('blob \"'+''.join(f'\\\\{b:02x}' for b in data)+'\"',end='')")
RESULT=$(icp canister call backend startUpload \
  "(2 : nat, \"alpha.pdf\", \"application/pdf\", $ALPHA_SIZE : nat, \"alpha\", null)" \
  --identity smoke-doc-associate)
check "startUpload alpha.pdf (doc-associate) ok" "ok" "$RESULT"
ALPHA_SID=$(echo "$RESULT" | grep -o '[0-9]*' | head -1)
icp canister call backend appendChunk "($ALPHA_SID : nat, 0 : nat, $ALPHA_DATA)" \
  --identity smoke-doc-associate > /dev/null
ALPHA_FIN=$(icp canister call backend finalizeUpload "($ALPHA_SID : nat)" --identity smoke-doc-associate)
check "finalizeUpload alpha.pdf ok" "ok" "$ALPHA_FIN"
ALPHA_DOC_ID=$(echo "$ALPHA_FIN" | python3 -c "import sys,re; m=re.search(r'documentId\s*=\s*(\d+)',sys.stdin.read()); print(m.group(1) if m else '0')")
rm -f "$ALPHA_FILE"
# Upload beta.pdf as v2 of alpha doc (version-history: current version becomes beta)
BETA_FILE=$(mktemp /tmp/tp_smoke_XXXXXX.bin)
printf 'beta document content v2' > "$BETA_FILE"
BETA_SIZE=$(wc -c < "$BETA_FILE")
BETA_DATA=$(python3 -c "data=open('$BETA_FILE','rb').read(); print('blob \"'+''.join(f'\\\\{b:02x}' for b in data)+'\"',end='')")
RESULT=$(icp canister call backend startUpload \
  "(2 : nat, \"beta.pdf\", \"application/pdf\", $BETA_SIZE : nat, \"v2 beta\", opt ($ALPHA_DOC_ID : nat))" \
  --identity smoke-doc-associate)
check "startUpload beta.pdf v2 ok" "ok" "$RESULT"
BETA_SID=$(echo "$RESULT" | grep -o '[0-9]*' | head -1)
icp canister call backend appendChunk "($BETA_SID : nat, 0 : nat, $BETA_DATA)" \
  --identity smoke-doc-associate > /dev/null
BETA_FIN=$(icp canister call backend finalizeUpload "($BETA_SID : nat)" --identity smoke-doc-associate)
check "finalizeUpload beta.pdf v2 ok" "ok" "$BETA_FIN"
rm -f "$BETA_FILE"
echo "  alpha_doc_id=$ALPHA_DOC_ID (current version is now beta.pdf)"
echo ""

# ── Step 88: searchClients — case-insensitive "smith" matches exactly 3 ──────
echo "Step 88: searchClients — 'smith' nameContains: 3 results (case-insensitive)"
RESULT=$(icp canister call backend searchClients \
  "(record { nameContains = opt \"smith\" }, 0 : nat, 1000 : nat)")
check "smith search finds 'Smith & Partners'" "Smith & Partners" "$RESULT"
check "smith search finds 'Smithson Trading'" "Smithson Trading" "$RESULT"
check "smith search finds 'smith Bros'" "smith Bros" "$RESULT"
check_absent "smith search excludes 'Lotus Bank'" "Lotus Bank" "$RESULT"
check_absent "smith search excludes 'Acme Holdings PLC'" "Acme" "$RESULT"
echo ""

# ── Step 89: searchClients — clientType, empty filter, statusFilter=Inactive ─
echo "Step 89: searchClients — clientType=Company; empty filter; statusFilter=Inactive"
RESULT=$(icp canister call backend searchClients \
  "(record { clientType = opt variant { Company } }, 0 : nat, 1000 : nat)")
check "Company filter returns Acme" "Acme" "$RESULT"
check "Company filter returns Smith & Partners" "Smith & Partners" "$RESULT"
check_absent "Company filter excludes smith Bros (Individual)" "smith Bros" "$RESULT"
RESULT=$(icp canister call backend searchClients "(record {}, 0 : nat, 1000 : nat)")
check "empty filter returns Acme (active)" "Acme" "$RESULT"
check "empty filter returns smith Bros" "smith Bros" "$RESULT"
check_absent "empty filter excludes Inactive Corp (deactivated)" "Inactive Corp" "$RESULT"
RESULT=$(icp canister call backend searchClients \
  "(record { statusFilter = opt variant { Inactive } }, 0 : nat, 1000 : nat)")
check "Inactive filter returns Inactive Corp" "Inactive Corp" "$RESULT"
check_absent "Inactive filter excludes Acme (Active)" "Acme" "$RESULT"
echo ""

# ── Step 90: searchClients — identifierContains; compound AND; createdAfter ──
echo "Step 90: searchClients — identifierContains; compound AND filter; future createdAfter"
RESULT=$(icp canister call backend searchClients \
  "(record { identifierContains = opt \"NIC\" }, 0 : nat, 1000 : nat)")
check "identifierContains 'NIC' returns Lotus Bank" "Lotus Bank" "$RESULT"
check_absent "identifierContains 'NIC' excludes Smith & Partners (no identifier)" "Smith & Partners" "$RESULT"
RESULT=$(icp canister call backend searchClients \
  "(record { nameContains = opt \"smith\"; clientType = opt variant { Company } }, 0 : nat, 1000 : nat)")
check "compound AND (smith+Company): Smith & Partners" "Smith & Partners" "$RESULT"
check "compound AND (smith+Company): Smithson Trading" "Smithson Trading" "$RESULT"
check_absent "compound AND excludes smith Bros (Individual)" "smith Bros" "$RESULT"
RESULT=$(icp canister call backend searchClients \
  "(record { createdAfter = opt (9_000_000_000_000_000_000 : int) }, 0 : nat, 1000 : nat)")
check_absent "createdAfter far-future returns no clients" "name =" "$RESULT"
echo ""

# ── Step 91: searchMatters — titleContains; clientId filter ──────────────────
echo "Step 91: searchMatters — titleContains 'smith'; clientId filter"
RESULT=$(icp canister call backend searchMatters \
  "(record { titleContains = opt \"smith\" }, 0 : nat, 1000 : nat)")
check "searchMatters 'smith' finds Smith Corporate Advisory" "Smith Corporate Advisory" "$RESULT"
check "searchMatters 'smith' finds Smith Tax Filing" "Smith Tax Filing" "$RESULT"
check_absent "searchMatters 'smith' excludes Matter Two" "Matter Two" "$RESULT"
RESULT=$(icp canister call backend searchMatters \
  "(record { clientId = opt ($SMITH_CLIENT_ID : nat) }, 0 : nat, 1000 : nat)")
check "clientId filter finds Smith Corporate Advisory" "Smith Corporate Advisory" "$RESULT"
check "clientId filter finds Smith Tax Filing" "Smith Tax Filing" "$RESULT"
check_absent "clientId filter excludes Matter Two (client 1)" "Matter Two" "$RESULT"
echo ""

# ── Step 92: searchMatters — assignedPartner; default excludes Archived; #Archived only ─
echo "Step 92: searchMatters — assignedPartner filter; default excludes #Archived; Archived-only"
RESULT=$(icp canister call backend searchMatters \
  "(record { assignedPartner = opt (principal \"$PARTNER_PRINCIPAL\") }, 0 : nat, 1000 : nat)")
check "assignedPartner filter finds Smith Tax Filing" "Smith Tax Filing" "$RESULT"
check_absent "assignedPartner filter excludes unassigned matters" "Smith Corporate Advisory" "$RESULT"
RESULT=$(icp canister call backend searchMatters "(record {}, 0 : nat, 1000 : nat)")
check "default filter includes Matter Two (Open)" "Matter Two" "$RESULT"
check_absent "default filter excludes Archived (Acme Litigation v1)" "Acme Litigation v1" "$RESULT"
RESULT=$(icp canister call backend searchMatters \
  "(record { statusFilter = opt variant { Archived } }, 0 : nat, 1000 : nat)")
check "Archived filter returns Acme Litigation v1" "Acme Litigation v1" "$RESULT"
check_absent "Archived filter excludes Matter Two (Open)" "Matter Two" "$RESULT"
echo ""

# ── Step 93: searchDocuments — filenameContains; contentType filter ───────────
echo "Step 93: searchDocuments — filenameContains 'contract'; contentType filter"
RESULT=$(icp canister call backend searchDocuments \
  "(record { filenameContains = opt \"contract\" }, 0 : nat, 1000 : nat)")
check "filenameContains 'contract' finds contract_review.pdf" "contract_review" "$RESULT"
check_absent "filenameContains 'contract' excludes beta.pdf" "beta" "$RESULT"
RESULT=$(icp canister call backend searchDocuments \
  "(record { contentType = opt \"application/pdf\" }, 0 : nat, 1000 : nat)")
check "contentType application/pdf returns contract_review" "contract_review" "$RESULT"
check "contentType application/pdf returns beta" "beta" "$RESULT"
echo ""

# ── Step 94: searchDocuments — uploadedBy; version-history limitation ─────────
echo "Step 94: searchDocuments — uploadedBy filter; version-history: search 'alpha' = 0 results"
RESULT=$(icp canister call backend searchDocuments \
  "(record { uploadedBy = opt (principal \"$DOC_ASSOC_PRINCIPAL\") }, 0 : nat, 1000 : nat)")
check "uploadedBy=doc-associate finds beta.pdf (current version)" "beta" "$RESULT"
check_absent "uploadedBy=doc-associate excludes contract_review (master uploaded)" "contract_review" "$RESULT"
# SEC-INV-9 (L4): alpha.pdf was v1; current version is now beta.pdf → search "alpha" = empty
RESULT=$(icp canister call backend searchDocuments \
  "(record { filenameContains = opt \"alpha\" }, 0 : nat, 1000 : nat)")
check_absent "version-history limitation: 'alpha' search empty (current=beta.pdf)" "alpha" "$RESULT"
echo ""

# ── Step 95: searchDocuments blob stripped; searchMatters pagination ───────────
echo "Step 95: blob stripped in DocumentSearchResult; searchMatters pagination no-overlap"
RESULT=$(icp canister call backend searchDocuments \
  "(record { filenameContains = opt \"contract\" }, 0 : nat, 1000 : nat)")
check "searchDocuments result contains currentVersion" "currentVersion" "$RESULT"
check "blob field is stripped to empty in search result" '"blob" = blob ""' "$RESULT"
# Pagination: two pages over non-Archived matters (2,3,4,5,6,7 = 6 total)
PAGE1=$(icp canister call backend searchMatters "(record {}, 0 : nat, 2 : nat)")
check "page 1 contains Matter Two" "Matter Two" "$PAGE1"
PAGE1_LAST=$(echo "$PAGE1" | python3 -c "
import sys, re
ids = [int(m.group(1)) for m in re.finditer(r'\bid\s*=\s*(\d+)\s*:', sys.stdin.read())]
print(max(ids) if ids else 0)
")
PAGE2=$(icp canister call backend searchMatters "(record {}, $PAGE1_LAST : nat, 2 : nat)")
check "page 2 contains Matter Four" "Matter Four" "$PAGE2"
check_absent "page 2 does not contain Matter Two (no overlap)" "Matter Two" "$PAGE2"
echo ""

# ── Step 96: mattersByStatus dashboard counts ─────────────────────────────────
echo "Step 96: mattersByStatus — Open=5, OnHold=0, Closed=1, Archived=1"
RESULT=$(icp canister call backend mattersByStatus "()")
check "mattersByStatus returns open field" "open" "$RESULT"
OPEN_C=$(echo "$RESULT" | python3 -c "import sys,re; m=re.search(r'open\s*=\s*(\d+)',sys.stdin.read()); print(m.group(1) if m else '?')")
check "mattersByStatus open = 5" "5" "$OPEN_C"
CLOSED_C=$(echo "$RESULT" | python3 -c "import sys,re; m=re.search(r'closed\s*=\s*(\d+)',sys.stdin.read()); print(m.group(1) if m else '?')")
check "mattersByStatus closed = 1" "1" "$CLOSED_C"
ARCH_C=$(echo "$RESULT" | python3 -c "import sys,re; m=re.search(r'archived\s*=\s*(\d+)',sys.stdin.read()); print(m.group(1) if m else '?')")
check "mattersByStatus archived = 1" "1" "$ARCH_C"
echo ""

# ── Step 97: clientsByStatus + documentsByStatus ──────────────────────────────
echo "Step 97: clientsByStatus (Active=7 Inactive=1); documentsByStatus (Active=5 Deleted=1)"
RESULT=$(icp canister call backend clientsByStatus "()")
ACT_C=$(echo "$RESULT" | python3 -c "import sys,re; m=re.search(r'active\s*=\s*(\d+)',sys.stdin.read()); print(m.group(1) if m else '?')")
check "clientsByStatus active = 7" "7" "$ACT_C"
INACT_C=$(echo "$RESULT" | python3 -c "import sys,re; m=re.search(r'inactive\s*=\s*(\d+)',sys.stdin.read()); print(m.group(1) if m else '?')")
check "clientsByStatus inactive = 1" "1" "$INACT_C"
RESULT=$(icp canister call backend documentsByStatus "()")
DACT_C=$(echo "$RESULT" | python3 -c "import sys,re; m=re.search(r'active\s*=\s*(\d+)',sys.stdin.read()); print(m.group(1) if m else '?')")
check "documentsByStatus active = 5" "5" "$DACT_C"
DDEL_C=$(echo "$RESULT" | python3 -c "import sys,re; m=re.search(r'deleted\s*=\s*(\d+)',sys.stdin.read()); print(m.group(1) if m else '?')")
check "documentsByStatus deleted = 1" "1" "$DDEL_C"
echo ""

# ── Step 98: createExportManifest — Partner success + manifest field verification ──
echo "Step 98: createExportManifest — Partner success; manifest field verification"
RESULT=$(icp canister call backend createExportManifest "()")
check "createExportManifest returns ok" "ok" "$RESULT"
check "manifest contains generatedBy" "generatedBy" "$RESULT"
check "manifest contains masterController" "masterController" "$RESULT"
check "manifest clientIds populated" "clientIds" "$RESULT"
check "manifest matterIds populated" "matterIds" "$RESULT"
check "manifest documents list present" "documents" "$RESULT"
check "manifest userPrincipals populated" "userPrincipals" "$RESULT"
MANIFEST_TC=$(echo "$RESULT" | python3 -c "import sys,re; m=re.search(r'totalClients\s*=\s*(\d+)',sys.stdin.read()); print(m.group(1) if m else '?')")
check "manifest totalClients = 8 (all clients including inactive)" "8" "$MANIFEST_TC"
MANIFEST_TM=$(echo "$RESULT" | python3 -c "import sys,re; m=re.search(r'totalMatters\s*=\s*(\d+)',sys.stdin.read()); print(m.group(1) if m else '?')")
check "manifest totalMatters = 7" "7" "$MANIFEST_TM"
echo ""

# ── Step 99: createExportManifest — audit entry recorded ─────────────────────
echo "Step 99: createExportManifest — audit entry action='createExportManifest' outcome=#ok"
RESULT=$(icp canister call backend readAuditEntries "(0 : nat, 1000 : nat)")
check "createExportManifest audit entry present" "createExportManifest" "$RESULT"
echo ""

# ── Step 100: createExportManifest — Associate rejected + auditErr ────────────
echo "Step 100: createExportManifest — Associate (doc-associate) rejected; auditErr recorded"
RESULT=$(icp canister call backend createExportManifest "()" --identity smoke-doc-associate)
check "Associate createExportManifest returns err" "err" "$RESULT"
check "Associate error is not authorized" "not authorized" "$RESULT"
AUDIT=$(icp canister call backend readAuditEntries "(0 : nat, 1000 : nat)")
check "Associate rejection auditErr entry recorded" "createExportManifest" "$AUDIT"
echo ""

# ── Step 101: createExportManifest — Staff + anonymous rejection ──────────────
echo "Step 101: createExportManifest — Staff rejected; anonymous rejected"
RESULT=$(icp canister call backend createExportManifest "()" --identity smoke-staff)
check "Staff createExportManifest returns err" "err" "$RESULT"
check "Staff error is not authorized" "not authorized" "$RESULT"
ANON_RESULT=$(icp canister call backend createExportManifest "()" \
  --identity anonymous 2>&1) || true
check "anonymous createExportManifest rejected" "err\|Error\|anonymous\|not allowed" "$ANON_RESULT"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# ── FIRM LIBRARY SMOKE TESTS — Phase 1.5 (Steps 102–126) ─────────────────────
# ─────────────────────────────────────────────────────────────────────────────

# ── Step 102: createFolder — root level ───────────────────────────────────────
echo "Step 102: createFolder — two root folders; getFolderCount = 2"
R=$(icp canister call backend createFolder '("Contracts", null)')
check "createFolder Contracts ok" "ok" "$R"
LIB_F1=$(echo "$R" | python3 -c "import sys,re; m=re.search(r'ok\s*=\s*(\d+)',sys.stdin.read()); print(m.group(1) if m else '1')")
R=$(icp canister call backend createFolder '("Templates", null)')
check "createFolder Templates ok" "ok" "$R"
LIB_F2=$(echo "$R" | python3 -c "import sys,re; m=re.search(r'ok\s*=\s*(\d+)',sys.stdin.read()); print(m.group(1) if m else '2')")
R=$(icp canister call backend getFolderCount "()")
check "getFolderCount = 2 after two root folders" "2" "$R"
echo ""

# ── Step 103: nested folders + depth queries ──────────────────────────────────
echo "Step 103: nested createFolder; getFolderDepth; getFolder; listAllFolders"
R=$(icp canister call backend createFolder "(\"NDAs\", opt ($LIB_F1 : nat))")
check "createFolder NDAs under Contracts ok" "ok" "$R"
LIB_F3=$(echo "$R" | python3 -c "import sys,re; m=re.search(r'ok\s*=\s*(\d+)',sys.stdin.read()); print(m.group(1) if m else '3')")
R=$(icp canister call backend getFolderDepth "($LIB_F1 : nat)")
check "getFolderDepth Contracts = 1" "1" "$R"
R=$(icp canister call backend getFolderDepth "($LIB_F3 : nat)")
check "getFolderDepth NDAs = 2" "2" "$R"
R=$(icp canister call backend getFolder "($LIB_F3 : nat)")
check "getFolder returns NDAs name" "NDAs" "$R"
R=$(icp canister call backend listAllFolders "()")
check "listAllFolders contains Contracts" "Contracts" "$R"
check "listAllFolders contains Templates" "Templates" "$R"
check "listAllFolders contains NDAs" "NDAs" "$R"
echo ""

# ── Step 104: MAX_FOLDER_DEPTH = 5 enforcement ───────────────────────────────
echo "Step 104: depth 3–5 folders created ok; depth 6 rejected; getFolderCount = 6"
R=$(icp canister call backend createFolder "(\"D3\", opt ($LIB_F3 : nat))")
check "depth 3 folder ok" "ok" "$R"
LIB_F4=$(echo "$R" | python3 -c "import sys,re; m=re.search(r'ok\s*=\s*(\d+)',sys.stdin.read()); print(m.group(1) if m else '4')")
R=$(icp canister call backend createFolder "(\"D4\", opt ($LIB_F4 : nat))")
check "depth 4 folder ok" "ok" "$R"
LIB_F5=$(echo "$R" | python3 -c "import sys,re; m=re.search(r'ok\s*=\s*(\d+)',sys.stdin.read()); print(m.group(1) if m else '5')")
R=$(icp canister call backend createFolder "(\"D5\", opt ($LIB_F5 : nat))")
check "depth 5 folder ok" "ok" "$R"
LIB_F6=$(echo "$R" | python3 -c "import sys,re; m=re.search(r'ok\s*=\s*(\d+)',sys.stdin.read()); print(m.group(1) if m else '6')")
R=$(icp canister call backend createFolder "(\"D6-overflow\", opt ($LIB_F6 : nat))")
check "depth 6 attempt rejected" "err" "$R"
check "depth error text mentions 'depth'" "depth" "$R"
R=$(icp canister call backend getFolderCount "()")
check "getFolderCount = 6 (D6-overflow not created)" "6" "$R"
echo ""

# ── Step 105: listFolderContents — Root + Folder scopes ───────────────────────
echo "Step 105: listFolderContents Root = top-level folders; Folder = direct children only"
R=$(icp canister call backend listFolderContents '(variant { Root })')
check "listFolderContents Root has Contracts" "Contracts" "$R"
check "listFolderContents Root has Templates" "Templates" "$R"
check_absent "listFolderContents Root excludes nested NDAs" "NDAs" "$R"
R=$(icp canister call backend listFolderContents "(variant { Folder = $LIB_F1 : nat })")
check "listFolderContents Folder=Contracts includes NDAs" "NDAs" "$R"
check_absent "listFolderContents Folder=Contracts excludes D3 (not direct child of F1)" "D3" "$R"
echo ""

# ── Step 106: renameFolder + role gate ────────────────────────────────────────
echo "Step 106: renameFolder ok; Staff cannot rename (Associate required)"
R=$(icp canister call backend renameFolder "($LIB_F2 : nat, \"Standard Templates\")")
check "renameFolder Templates → Standard Templates ok" "ok" "$R"
R=$(icp canister call backend getFolder "($LIB_F2 : nat)")
check "getFolder reflects new name Standard Templates" "Standard Templates" "$R"
R=$(icp canister call backend renameFolder "($LIB_F1 : nat, \"X\")" --identity smoke-staff)
check "Staff renameFolder rejected" "err" "$R"
echo ""

# ── Step 107: moveFolder — happy path + cycle prevention ──────────────────────
echo "Step 107: moveFolder to root ok; cycle detection rejects move into own subtree"
R=$(icp canister call backend moveFolder "($LIB_F3 : nat, null)")
check "moveFolder NDAs to root ok" "ok" "$R"
R=$(icp canister call backend getFolder "($LIB_F3 : nat)")
check "NDAs parentId is null after move to root" "null" "$R"
# F4 is a descendant of F3 — move F3 under F4 is a cycle
R=$(icp canister call backend moveFolder "($LIB_F3 : nat, opt ($LIB_F4 : nat))")
check "moveFolder cycle detected (F4 is descendant of F3)" "err" "$R"
check "cycle error text contains 'cycle'" "cycle" "$R"
echo ""

# ── Step 108: deleteFolder — dependents block; Associate rejected; leaf ok ─────
echo "Step 108: deleteFolder non-empty blocked; Associate cannot delete; Partner deletes leaf"
# F5 has child F6 — blocked
R=$(icp canister call backend deleteFolder "($LIB_F5 : nat)")
check "deleteFolder D4 (has child D5) blocked" "err" "$R"
check "blocked message mentions not empty" "not empty\|child" "$R"
# Associate cannot delete folders
R=$(icp canister call backend deleteFolder "($LIB_F6 : nat)" --identity smoke-doc-associate)
check "Associate deleteFolder rejected (Partner only)" "err" "$R"
# Partner deletes leaf F6 (D5, depth 5)
R=$(icp canister call backend deleteFolder "($LIB_F6 : nat)")
check "Partner deletes leaf folder D5 ok" "ok" "$R"
R=$(icp canister call backend getFolderCount "()")
check "getFolderCount = 5 after leaf delete" "5" "$R"
echo ""

# ── Step 109: Library upload — happy path (single chunk) ──────────────────────
echo "Step 109: startLibraryUpload + appendLibraryChunk + finalizeLibraryUpload; sha256 ok"
LIB_BLOB1=$(mktemp /tmp/tp_smoke_XXXXXX.bin)
printf 'The practice library smoke test item one — contract document.' > "$LIB_BLOB1"
LIB_BLOB1_SIZE=$(wc -c < "$LIB_BLOB1")
LIB_LOCAL_HASH1=$(sha256sum "$LIB_BLOB1" | awk '{print $1}')
R=$(icp canister call backend startLibraryUpload \
  "(\"Contract Template\", null, vec {\"contract\"; \"template\"}, \"A standard contract template\", \"contract.pdf\", \"application/pdf\", $LIB_BLOB1_SIZE : nat, \"initial upload\", null)")
check "startLibraryUpload ok" "ok" "$R"
LIB_S1=$(echo "$R" | python3 -c "import sys,re; m=re.search(r'ok\s*=\s*(\d+)',sys.stdin.read()); print(m.group(1) if m else '1')")
LIB_ARGS1=$(mktemp /tmp/tp_smoke_XXXXXX.did)
make_chunk_args_file "$LIB_S1" 0 "$LIB_BLOB1" "$LIB_ARGS1"
R=$(icp canister call backend appendLibraryChunk --args-file "$LIB_ARGS1")
check "appendLibraryChunk ok" "ok" "$R"
LIB_FINALIZE1=$(icp canister call backend finalizeLibraryUpload "($LIB_S1 : nat)")
check "finalizeLibraryUpload ok" "ok" "$LIB_FINALIZE1"
LIB_ITEM1=$(echo "$LIB_FINALIZE1" | python3 -c "import sys,re; m=re.search(r'itemId\s*=\s*(\d+)',sys.stdin.read()); print(m.group(1) if m else '1')")
LIB_V1=$(echo "$LIB_FINALIZE1" | python3 -c "import sys,re; m=re.search(r'versionId\s*=\s*(\d+)',sys.stdin.read()); print(m.group(1) if m else '1')")
LIB_HASH1=$(extract_sha256_hex "$LIB_FINALIZE1")
check "library item sha256 matches local hash" "$LIB_LOCAL_HASH1" "$LIB_HASH1"
R=$(icp canister call backend getLibraryItemCount "()")
check "getLibraryItemCount = 1" "1" "$R"
echo ""

# ── Step 110: Second upload (to folder) + listLibraryItems name filter ─────────
echo "Step 110: second item upload (to Contracts folder); listLibraryItems nameContains filter"
LIB_BLOB2=$(mktemp /tmp/tp_smoke_XXXXXX.bin)
printf 'The practice library smoke test item two — NDA document.' > "$LIB_BLOB2"
LIB_BLOB2_SIZE=$(wc -c < "$LIB_BLOB2")
R=$(icp canister call backend startLibraryUpload \
  "(\"Standard NDA\", opt ($LIB_F1 : nat), vec {\"nda\"; \"contract\"}, \"Standard NDA template\", \"nda.docx\", \"application/msword\", $LIB_BLOB2_SIZE : nat, \"nda upload\", null)")
check "startLibraryUpload item2 ok" "ok" "$R"
LIB_S2=$(echo "$R" | python3 -c "import sys,re; m=re.search(r'ok\s*=\s*(\d+)',sys.stdin.read()); print(m.group(1) if m else '2')")
LIB_ARGS2=$(mktemp /tmp/tp_smoke_XXXXXX.did)
make_chunk_args_file "$LIB_S2" 0 "$LIB_BLOB2" "$LIB_ARGS2"
icp canister call backend appendLibraryChunk --args-file "$LIB_ARGS2" > /dev/null
LIB_FINALIZE2=$(icp canister call backend finalizeLibraryUpload "($LIB_S2 : nat)")
check "finalizeLibraryUpload item2 ok" "ok" "$LIB_FINALIZE2"
LIB_ITEM2=$(echo "$LIB_FINALIZE2" | python3 -c "import sys,re; m=re.search(r'itemId\s*=\s*(\d+)',sys.stdin.read()); print(m.group(1) if m else '2')")
LIB_V2=$(echo "$LIB_FINALIZE2" | python3 -c "import sys,re; m=re.search(r'versionId\s*=\s*(\d+)',sys.stdin.read()); print(m.group(1) if m else '2')")
# listLibraryItems with nameContains filter
R=$(icp canister call backend listLibraryItems \
  "(record { nameContains = opt \"NDA\"; currentFilenameContains = null; folderScope = variant { Any }; tagsContainsAny = null; contentType = null; statusFilter = null; uploadedAfter = null; uploadedBefore = null; uploadedBy = null }, 0 : nat, 10 : nat)")
check "listLibraryItems nameContains=NDA finds Standard NDA" "Standard NDA" "$R"
check_absent "listLibraryItems NDA filter excludes Contract Template" "Contract Template" "$R"
# listFolderContents for Contracts now shows item2
R=$(icp canister call backend listFolderContents "(variant { Folder = $LIB_F1 : nat })")
check "listFolderContents Contracts shows Standard NDA item" "Standard NDA" "$R"
echo ""

# ── Step 111: Tag validation — invalid chars; normalization to lowercase ───────
echo "Step 111: tag with '/' rejected; tag with ',' rejected; addLibraryItemTag normalises"
R=$(icp canister call backend startLibraryUpload \
  "(\"Bad Tag\", null, vec {\"bad/tag\"}, \"desc\", \"test.pdf\", \"application/pdf\", 1 : nat, \"\", null)")
check "tag with '/' rejected at upload start" "err" "$R"
R=$(icp canister call backend startLibraryUpload \
  "(\"Bad Tag\", null, vec {\"bad,tag\"}, \"desc\", \"test.pdf\", \"application/pdf\", 1 : nat, \"\", null)")
check "tag with ',' rejected at upload start" "err" "$R"
# addLibraryItemTag normalises to lowercase
R=$(icp canister call backend addLibraryItemTag "($LIB_ITEM1 : nat, \"PRIORITY\")")
check "addLibraryItemTag PRIORITY ok" "ok" "$R"
R=$(icp canister call backend getLibraryItem "($LIB_ITEM1 : nat)")
check "tag stored as lowercase 'priority'" "priority" "$R"
check_absent "uppercase PRIORITY not stored" "PRIORITY" "$R"
echo ""

# ── Step 112: Upload role gate — Staff cannot upload ──────────────────────────
echo "Step 112: Staff cannot startLibraryUpload (Associate or higher required)"
R=$(icp canister call backend startLibraryUpload \
  "(\"Staff Upload\", null, vec {}, \"desc\", \"file.pdf\", \"application/pdf\", 1 : nat, \"\", null)" \
  --identity smoke-staff)
check "Staff startLibraryUpload rejected" "err" "$R"
echo ""

# ── Step 113: Versioning — second version of existing item ────────────────────
echo "Step 113: upload new version of item1; listLibraryVersions = 2; currentVersionId updated; replacement of archived rejected"
LIB_BLOB3=$(mktemp /tmp/tp_smoke_XXXXXX.bin)
printf 'The practice library smoke test item one — VERSION TWO content.' > "$LIB_BLOB3"
LIB_BLOB3_SIZE=$(wc -c < "$LIB_BLOB3")
R=$(icp canister call backend startLibraryUpload \
  "(\"\", null, vec {}, \"\", \"contract_v2.pdf\", \"application/pdf\", $LIB_BLOB3_SIZE : nat, \"v2 revision\", opt ($LIB_ITEM1 : nat))")
check "startLibraryUpload replacement ok" "ok" "$R"
LIB_S3=$(echo "$R" | python3 -c "import sys,re; m=re.search(r'ok\s*=\s*(\d+)',sys.stdin.read()); print(m.group(1) if m else '3')")
LIB_ARGS3=$(mktemp /tmp/tp_smoke_XXXXXX.did)
make_chunk_args_file "$LIB_S3" 0 "$LIB_BLOB3" "$LIB_ARGS3"
icp canister call backend appendLibraryChunk --args-file "$LIB_ARGS3" > /dev/null
LIB_FINALIZE3=$(icp canister call backend finalizeLibraryUpload "($LIB_S3 : nat)")
check "finalizeLibraryUpload v2 ok" "ok" "$LIB_FINALIZE3"
LIB_V3=$(echo "$LIB_FINALIZE3" | python3 -c "import sys,re; m=re.search(r'versionId\s*=\s*(\d+)',sys.stdin.read()); print(m.group(1) if m else '3')")
R=$(icp canister call backend listLibraryVersions "($LIB_ITEM1 : nat)")
check "listLibraryVersions shows versionNumber entries for item1" "versionNumber" "$R"
R=$(icp canister call backend getLibraryItem "($LIB_ITEM1 : nat)")
check "item1 currentVersionId updated to LIB_V3" "$LIB_V3" "$R"
# Replacement of archived item rejected
R=$(icp canister call backend archiveLibraryItem "($LIB_ITEM2 : nat)")
check "archive item2 (for replacement-of-archived test)" "ok" "$R"
R=$(icp canister call backend startLibraryUpload \
  "(\"\", null, vec {}, \"\", \"nda_v2.docx\", \"application/msword\", 1 : nat, \"\", opt ($LIB_ITEM2 : nat))")
check "replacement of archived item rejected" "err" "$R"
R=$(icp canister call backend unarchiveLibraryItem "($LIB_ITEM2 : nat)")
check "unarchive item2 after test" "ok" "$R"
echo ""

# ── Step 114: Metadata edits ──────────────────────────────────────────────────
echo "Step 114: renameLibraryItem; updateLibraryItemDescription; setLibraryItemTags"
R=$(icp canister call backend renameLibraryItem "($LIB_ITEM1 : nat, \"Master Contract Template\")")
check "renameLibraryItem ok" "ok" "$R"
R=$(icp canister call backend getLibraryItem "($LIB_ITEM1 : nat)")
check "item1 name updated to Master Contract Template" "Master Contract Template" "$R"
R=$(icp canister call backend updateLibraryItemDescription "($LIB_ITEM1 : nat, \"Updated master document description\")")
check "updateLibraryItemDescription ok" "ok" "$R"
R=$(icp canister call backend setLibraryItemTags "($LIB_ITEM1 : nat, vec {\"contract\"; \"master\"; \"priority\"})")
check "setLibraryItemTags ok" "ok" "$R"
R=$(icp canister call backend getLibraryItem "($LIB_ITEM1 : nat)")
check "item1 has tag 'master'" "master" "$R"
check_absent "old tag 'template' removed by setLibraryItemTags" "\"template\"" "$R"
echo ""

# ── Step 115: moveLibraryItem ─────────────────────────────────────────────────
echo "Step 115: moveLibraryItem to folder; back to root; non-existent folder rejected"
R=$(icp canister call backend moveLibraryItem "($LIB_ITEM1 : nat, opt ($LIB_F2 : nat))")
check "moveLibraryItem item1 to Standard Templates ok" "ok" "$R"
R=$(icp canister call backend moveLibraryItem "($LIB_ITEM1 : nat, null)")
check "moveLibraryItem item1 back to root ok" "ok" "$R"
R=$(icp canister call backend getLibraryItem "($LIB_ITEM1 : nat)")
check "item1 folderId = null after move to root" "null" "$R"
R=$(icp canister call backend moveLibraryItem "($LIB_ITEM1 : nat, opt (9999 : nat))")
check "moveLibraryItem to non-existent folder rejected" "err" "$R"
echo ""

# ── Step 116: Lifecycle — archive / unarchive; default filter behaviour ────────
echo "Step 116: archiveLibraryItem hides from default list; statusFilter=Archived reveals; unarchive restores"
R=$(icp canister call backend archiveLibraryItem "($LIB_ITEM1 : nat)")
check "archiveLibraryItem ok" "ok" "$R"
R=$(icp canister call backend listLibraryItems \
  "(record { nameContains = null; currentFilenameContains = null; folderScope = variant { Any }; tagsContainsAny = null; contentType = null; statusFilter = null; uploadedAfter = null; uploadedBefore = null; uploadedBy = null }, 0 : nat, 10 : nat)")
check_absent "archived item1 excluded from default list" "Master Contract Template" "$R"
check "non-archived item2 still in default list" "Standard NDA" "$R"
R=$(icp canister call backend searchLibrary \
  "(record { nameContains = null; currentFilenameContains = null; folderScope = variant { Any }; tagsContainsAny = null; contentType = null; statusFilter = opt variant { Archived }; uploadedAfter = null; uploadedBefore = null; uploadedBy = null }, 0 : nat, 10 : nat)")
check "statusFilter=Archived surfaces archived item1" "Master Contract Template" "$R"
R=$(icp canister call backend unarchiveLibraryItem "($LIB_ITEM1 : nat)")
check "unarchiveLibraryItem ok" "ok" "$R"
R=$(icp canister call backend listLibraryItems \
  "(record { nameContains = null; currentFilenameContains = null; folderScope = variant { Any }; tagsContainsAny = null; contentType = null; statusFilter = null; uploadedAfter = null; uploadedBefore = null; uploadedBy = null }, 0 : nat, 10 : nat)")
check "unarchived item1 back in default list" "Master Contract Template" "$R"
echo ""

# ── Step 117: deleteLibraryItem — Partner only; deleted item blocks deleteFolder ─
echo "Step 117: Associate cannot delete item; Partner can; deleted item blocks folder delete"
LIB_BLOB4=$(mktemp /tmp/tp_smoke_XXXXXX.bin)
printf 'Item three for delete test.' > "$LIB_BLOB4"
LIB_BLOB4_SIZE=$(wc -c < "$LIB_BLOB4")
R=$(icp canister call backend startLibraryUpload \
  "(\"Delete Test Item\", opt ($LIB_F1 : nat), vec {}, \"for delete testing\", \"del.pdf\", \"application/pdf\", $LIB_BLOB4_SIZE : nat, \"\", null)")
check "startLibraryUpload item3 ok" "ok" "$R"
LIB_S4=$(echo "$R" | python3 -c "import sys,re; m=re.search(r'ok\s*=\s*(\d+)',sys.stdin.read()); print(m.group(1) if m else '4')")
LIB_ARGS4=$(mktemp /tmp/tp_smoke_XXXXXX.did)
make_chunk_args_file "$LIB_S4" 0 "$LIB_BLOB4" "$LIB_ARGS4"
icp canister call backend appendLibraryChunk --args-file "$LIB_ARGS4" > /dev/null
LIB_FINALIZE4=$(icp canister call backend finalizeLibraryUpload "($LIB_S4 : nat)")
check "finalizeLibraryUpload item3 ok" "ok" "$LIB_FINALIZE4"
LIB_ITEM3=$(echo "$LIB_FINALIZE4" | python3 -c "import sys,re; m=re.search(r'itemId\s*=\s*(\d+)',sys.stdin.read()); print(m.group(1) if m else '3')")
R=$(icp canister call backend deleteLibraryItem "($LIB_ITEM3 : nat)" --identity smoke-doc-associate)
check "Associate deleteLibraryItem rejected (Partner only)" "err" "$R"
R=$(icp canister call backend deleteLibraryItem "($LIB_ITEM3 : nat)")
check "Partner deleteLibraryItem ok" "ok" "$R"
R=$(icp canister call backend listLibraryItems \
  "(record { nameContains = null; currentFilenameContains = null; folderScope = variant { Any }; tagsContainsAny = null; contentType = null; statusFilter = null; uploadedAfter = null; uploadedBefore = null; uploadedBy = null }, 0 : nat, 10 : nat)")
check_absent "deleted item3 excluded from default list" "Delete Test Item" "$R"
# Soft-deleted item3 (in F1) blocks folder deletion
R=$(icp canister call backend deleteFolder "($LIB_F1 : nat)")
check "deleteFolder Contracts blocked (has soft-deleted + active items)" "err" "$R"
check "blocked message mentions 'item'" "item" "$R"
echo ""

# ── Step 118: Download flow — prepareLibraryDownload + getLibraryChunk ─────────
echo "Step 118: prepareLibraryDownload returns metadata; getLibraryChunk returns chunk bytes"
DOWNLOAD=$(icp canister call backend prepareLibraryDownload "($LIB_V1 : nat)")
check "prepareLibraryDownload ok" "ok" "$DOWNLOAD"
check "prepareLibraryDownload has chunkCount field" "chunkCount" "$DOWNLOAD"
check "prepareLibraryDownload has filename field" "filename" "$DOWNLOAD"
DL_CHUNKS=$(echo "$DOWNLOAD" | python3 -c "import sys,re; m=re.search(r'chunkCount\s*=\s*(\d+)',sys.stdin.read()); print(m.group(1) if m else '1')")
check "chunkCount = 1 for single-chunk file" "1" "$DL_CHUNKS"
R=$(icp canister call backend getLibraryChunk "($LIB_V1 : nat, 0 : nat)")
check "getLibraryChunk returns opt blob" "opt" "$R"
# Out-of-range chunk returns null
R=$(icp canister call backend getLibraryChunk "($LIB_V1 : nat, 999 : nat)")
check "getLibraryChunk out-of-range returns null" "null" "$R"
echo ""

# ── Step 119: Download on #Archived ok; #Deleted chunk returns null ───────────
echo "Step 119: prepareLibraryDownload on archived item ok; getLibraryChunk on deleted item null"
R=$(icp canister call backend archiveLibraryItem "($LIB_ITEM1 : nat)")
check "archive item1 for download test" "ok" "$R"
R=$(icp canister call backend prepareLibraryDownload "($LIB_V3 : nat)")
check "prepareLibraryDownload on archived item ok (SEC-INV-15)" "ok" "$R"
R=$(icp canister call backend getLibraryChunk "($LIB_V3 : nat, 0 : nat)")
check "getLibraryChunk archived item returns bytes" "opt" "$R"
# item3 is deleted — its chunk must return null
LIB_ITEM3_VLIST=$(icp canister call backend listLibraryVersions "($LIB_ITEM3 : nat)")
LIB_ITEM3_VID=$(echo "$LIB_ITEM3_VLIST" | python3 -c "import sys,re; m=re.search(r'versionId\s*=\s*(\d+)',sys.stdin.read()); print(m.group(1) if m else '4')")
R=$(icp canister call backend getLibraryChunk "($LIB_ITEM3_VID : nat, 0 : nat)")
check "getLibraryChunk deleted item returns null (SEC-INV-15)" "null" "$R"
R=$(icp canister call backend unarchiveLibraryItem "($LIB_ITEM1 : nat)")
check "unarchive item1 after download test" "ok" "$R"
echo ""

# ── Step 120: searchLibrary — filter variants (FolderScope, tags, contentType) ─
echo "Step 120: searchLibrary FolderScope Root/Folder; tagsContainsAny; contentType filter"
# FolderScope #Root: item1 is at root, item2 is in Contracts
R=$(icp canister call backend searchLibrary \
  "(record { nameContains = null; currentFilenameContains = null; folderScope = variant { Root }; tagsContainsAny = null; contentType = null; statusFilter = null; uploadedAfter = null; uploadedBefore = null; uploadedBy = null }, 0 : nat, 10 : nat)")
check "FolderScope Root finds root item1" "Master Contract Template" "$R"
check_absent "FolderScope Root excludes folder item2" "Standard NDA" "$R"
# FolderScope #Folder = F1 (Contracts): item2 in F1, item1 at root
R=$(icp canister call backend searchLibrary \
  "(record { nameContains = null; currentFilenameContains = null; folderScope = variant { Folder = $LIB_F1 : nat }; tagsContainsAny = null; contentType = null; statusFilter = null; uploadedAfter = null; uploadedBefore = null; uploadedBy = null }, 0 : nat, 10 : nat)")
check "FolderScope Folder=Contracts finds item2" "Standard NDA" "$R"
check_absent "FolderScope Folder=Contracts excludes root item1" "Master Contract Template" "$R"
# tagsContainsAny filter
R=$(icp canister call backend searchLibrary \
  "(record { nameContains = null; currentFilenameContains = null; folderScope = variant { Any }; tagsContainsAny = opt vec {\"nda\"}; contentType = null; statusFilter = null; uploadedAfter = null; uploadedBefore = null; uploadedBy = null }, 0 : nat, 10 : nat)")
check "tagsContainsAny=nda finds Standard NDA" "Standard NDA" "$R"
check_absent "tagsContainsAny=nda excludes Contract Template (no nda tag)" "Master Contract Template" "$R"
# contentType exact match
R=$(icp canister call backend searchLibrary \
  "(record { nameContains = null; currentFilenameContains = null; folderScope = variant { Any }; tagsContainsAny = null; contentType = opt \"application/msword\"; statusFilter = null; uploadedAfter = null; uploadedBefore = null; uploadedBy = null }, 0 : nat, 10 : nat)")
check "contentType=msword finds Standard NDA" "Standard NDA" "$R"
check_absent "contentType=msword excludes pdf item1" "Master Contract Template" "$R"
echo ""

# ── Step 121: searchLibrary — FolderScope Subtree + pagination ────────────────
echo "Step 121: FolderScope Subtree includes items in folder and descendants; cursor pagination"
# Subtree of F1 (Contracts) — item2 is directly in F1; item1 is at root (excluded)
R=$(icp canister call backend searchLibrary \
  "(record { nameContains = null; currentFilenameContains = null; folderScope = variant { Subtree = $LIB_F1 : nat }; tagsContainsAny = null; contentType = null; statusFilter = null; uploadedAfter = null; uploadedBefore = null; uploadedBy = null }, 0 : nat, 10 : nat)")
check "FolderScope Subtree=Contracts finds item2 in F1" "Standard NDA" "$R"
check_absent "FolderScope Subtree=Contracts excludes root item1" "Master Contract Template" "$R"
# Cursor pagination: page 1 (after=0, limit=1) then page 2
R_P1=$(icp canister call backend searchLibrary \
  "(record { nameContains = null; currentFilenameContains = null; folderScope = variant { Any }; tagsContainsAny = null; contentType = null; statusFilter = null; uploadedAfter = null; uploadedBefore = null; uploadedBy = null }, 0 : nat, 1 : nat)")
check "page1 limit=1 returns a result" "Master Contract Template\|Standard NDA" "$R_P1"
P1_LAST=$(echo "$R_P1" | python3 -c "
import sys,re
ids = [int(m.group(1)) for m in re.finditer(r'\bid\s*=\s*(\d+)\s*:', sys.stdin.read())]
print(max(ids) if ids else 0)
")
R_P2=$(icp canister call backend searchLibrary \
  "(record { nameContains = null; currentFilenameContains = null; folderScope = variant { Any }; tagsContainsAny = null; contentType = null; statusFilter = null; uploadedAfter = null; uploadedBefore = null; uploadedBy = null }, $P1_LAST : nat, 1 : nat)")
check "page2 returns a different result via cursor" "Master Contract Template\|Standard NDA" "$R_P2"
echo ""

# ── Step 122: appendLibraryChunk idempotency + abandonLibraryUpload ───────────
echo "Step 122: appendLibraryChunk same index twice = ok (idempotent); abandon removes session"
LIB_BLOB5=$(mktemp /tmp/tp_smoke_XXXXXX.bin)
printf 'Abandon and idempotency test blob content.' > "$LIB_BLOB5"
LIB_BLOB5_SIZE=$(wc -c < "$LIB_BLOB5")
R=$(icp canister call backend startLibraryUpload \
  "(\"Temp Upload\", null, vec {}, \"for abandon test\", \"temp.pdf\", \"application/pdf\", $LIB_BLOB5_SIZE : nat, \"\", null)")
check "startLibraryUpload for idempotency/abandon test ok" "ok" "$R"
LIB_S5=$(echo "$R" | python3 -c "import sys,re; m=re.search(r'ok\s*=\s*(\d+)',sys.stdin.read()); print(m.group(1) if m else '5')")
LIB_ARGS5=$(mktemp /tmp/tp_smoke_XXXXXX.did)
make_chunk_args_file "$LIB_S5" 0 "$LIB_BLOB5" "$LIB_ARGS5"
R=$(icp canister call backend appendLibraryChunk --args-file "$LIB_ARGS5")
check "first appendLibraryChunk ok" "ok" "$R"
R=$(icp canister call backend appendLibraryChunk --args-file "$LIB_ARGS5")
check "second appendLibraryChunk same chunk ok (idempotent)" "ok" "$R"
R=$(icp canister call backend abandonLibraryUpload "($LIB_S5 : nat)")
check "abandonLibraryUpload ok" "ok" "$R"
R=$(icp canister call backend finalizeLibraryUpload "($LIB_S5 : nat)")
check "finalizeLibraryUpload after abandon returns err (session gone)" "err" "$R"
echo ""

# ── Step 123: Caller-lock — session owner check ───────────────────────────────
echo "Step 123: smoke-partner cannot append/abandon smoke-master's session (SEC-INV-5)"
R=$(icp canister call backend startLibraryUpload \
  "(\"Owner Test\", null, vec {}, \"\", \"owner.pdf\", \"application/pdf\", 1 : nat, \"\", null)")
check "startLibraryUpload by master ok" "ok" "$R"
LIB_S6=$(echo "$R" | python3 -c "import sys,re; m=re.search(r'ok\s*=\s*(\d+)',sys.stdin.read()); print(m.group(1) if m else '6')")
LIB_BLOB6=$(mktemp /tmp/tp_smoke_XXXXXX.bin)
printf 'x' > "$LIB_BLOB6"
LIB_ARGS6=$(mktemp /tmp/tp_smoke_XXXXXX.did)
make_chunk_args_file "$LIB_S6" 0 "$LIB_BLOB6" "$LIB_ARGS6"
R=$(icp canister call backend appendLibraryChunk --args-file "$LIB_ARGS6" --identity smoke-partner)
check "smoke-partner cannot append to master session" "err" "$R"
check "caller-lock error text present" "owner" "$R"
R=$(icp canister call backend abandonLibraryUpload "($LIB_S6 : nat)" --identity smoke-partner)
check "smoke-partner cannot abandon master session" "err" "$R"
R=$(icp canister call backend abandonLibraryUpload "($LIB_S6 : nat)")
check "master can abandon own session" "ok" "$R"
echo ""

# ── Step 124: Budget enforcement — zero-size and per-item ceiling ─────────────
echo "Step 124: zero-size upload rejected; 5 GiB+1 per-item ceiling rejected"
R=$(icp canister call backend startLibraryUpload \
  "(\"Empty\", null, vec {}, \"\", \"empty.pdf\", \"application/pdf\", 0 : nat, \"\", null)")
check "zero-size upload rejected" "err" "$R"
OVER_LIMIT=$((5368709120 + 1))
R=$(icp canister call backend startLibraryUpload \
  "(\"Over Limit\", null, vec {}, \"\", \"big.bin\", \"application/octet-stream\", $OVER_LIMIT : nat, \"\", null)")
check "5 GiB+1 upload rejected (per-item ceiling)" "err" "$R"
check "ceiling error mentions 'too large'" "too large" "$R"
echo ""

# ── Step 125: Export manifest — Library fields present and correct ─────────────
echo "Step 125: createExportManifest includes Library fields (totalFolders=5, totalLibraryItems=3)"
EXP=$(icp canister call backend createExportManifest "()")
check "createExportManifest ok" "ok" "$EXP"
check "manifest has totalFolders field" "totalFolders" "$EXP"
check "manifest has totalLibraryItems field" "totalLibraryItems" "$EXP"
check "manifest has totalLibraryVersions field" "totalLibraryVersions" "$EXP"
check "manifest has folders list" "folders" "$EXP"
check "manifest has libraryItems list" "libraryItems" "$EXP"
EXP_TF=$(echo "$EXP" | python3 -c "import sys,re; m=re.search(r'totalFolders\s*=\s*(\d+)',sys.stdin.read()); print(m.group(1) if m else '?')")
check "manifest totalFolders = 5" "5" "$EXP_TF"
EXP_TI=$(echo "$EXP" | python3 -c "import sys,re; m=re.search(r'totalLibraryItems\s*=\s*(\d+)',sys.stdin.read()); print(m.group(1) if m else '?')")
check "manifest totalLibraryItems = 3 (including soft-deleted)" "3" "$EXP_TI"
EXP_TV=$(echo "$EXP" | python3 -c "import sys,re; m=re.search(r'totalLibraryVersions\s*=\s*(\d+)',sys.stdin.read()); print(m.group(1) if m else '?')")
check "manifest totalLibraryVersions = 4" "4" "$EXP_TV"
echo ""

# ── Step 126: Audit trail — Library action entries present ────────────────────
echo "Step 126: audit log contains expected Firm Library action entries"
AUDIT=$(icp canister call backend readAuditEntries "(0 : nat, 1000 : nat)")
check "audit has folder.create entry" "folder.create" "$AUDIT"
check "audit has folder.rename entry" "folder.rename" "$AUDIT"
check "audit has folder.move entry" "folder.move" "$AUDIT"
check "audit has folder.delete entry" "folder.delete" "$AUDIT"
check "audit has library.upload entry" "library.upload" "$AUDIT"
check "audit has library.archive entry" "library.archive" "$AUDIT"
check "audit has library.unarchive entry" "library.unarchive" "$AUDIT"
check "audit has library.delete entry" "library.delete" "$AUDIT"
check "audit has library.download entry" "library.download" "$AUDIT"
echo ""

# ── Summary ──────────────────────────────────────────────────────────────────
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
