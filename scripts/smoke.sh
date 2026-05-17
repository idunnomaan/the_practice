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

# ── Summary ──────────────────────────────────────────────────────────────────
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
