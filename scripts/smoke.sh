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

# ── Summary ──────────────────────────────────────────────────────────────────
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
