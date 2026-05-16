#!/usr/bin/env bash
# L1 Identity smoke test — runs against the local replica.
# Usage: ./scripts/smoke-l1.sh  (from project root)
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

echo "=== L1 Identity Smoke Test ==="
echo ""

# ── Identity setup ────────────────────────────────────────────────────────────
# The anonymous principal (2vxsx-fae) cannot be master controller (INV-1).
# Create plaintext test identities — no keyring or password needed.

ORIGINAL_IDENTITY=$(icp identity default)
echo "Setup: creating plaintext test identities"
icp identity new smoke-master    --storage plaintext -q 2>/dev/null 1>/dev/null || true
icp identity new smoke-associate --storage plaintext -q 2>/dev/null 1>/dev/null || true
icp identity new smoke-ops       --storage plaintext -q 2>/dev/null 1>/dev/null || true

# Restore original identity on exit (even on failure)
restore() { icp identity default "$ORIGINAL_IDENTITY" 2>/dev/null || true; }
trap restore EXIT

# Get all principals (without switching identity yet)
MASTER_PRINCIPAL=$(icp identity principal --identity smoke-master)
ASSOCIATE_PRINCIPAL=$(icp identity principal --identity smoke-associate)
OPS_PRINCIPAL=$(icp identity principal --identity smoke-ops)
echo "  Master principal:    $MASTER_PRINCIPAL"
echo "  Associate principal: $ASSOCIATE_PRINCIPAL"
echo "  Ops principal:       $OPS_PRINCIPAL"
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
echo "Step 7: addUser — register smoke-associate as Associate"
icp canister call backend addUser "(principal \"$ASSOCIATE_PRINCIPAL\", variant { Associate })"
echo "  addUser succeeded"
RESULT=$(icp canister call backend getUserCount "()")
check "getUserCount is 2 after addUser" "2" "$RESULT"
echo ""

# ── Step 8: getMyRole for newly-added user ───────────────────────────────────
echo "Step 8: getMyRole as smoke-associate should return Associate"
RESULT=$(icp canister call backend getMyRole "()" --identity smoke-associate)
check "new user has Associate role" "Associate" "$RESULT"
echo ""

# ── Step 9: setUserRole ──────────────────────────────────────────────────────
echo "Step 9: setUserRole — promote smoke-associate to Partner"
icp canister call backend setUserRole "(principal \"$ASSOCIATE_PRINCIPAL\", variant { Partner })"
echo "  setUserRole succeeded"
RESULT=$(icp canister call backend getMyRole "()" --identity smoke-associate)
check "user role updated to Partner" "Partner" "$RESULT"
echo ""

# ── Step 10: suspendUser ─────────────────────────────────────────────────────
echo "Step 10: suspendUser — suspend smoke-associate"
icp canister call backend suspendUser "(principal \"$ASSOCIATE_PRINCIPAL\")"
echo "  suspendUser succeeded"
RESULT=$(icp canister call backend getMyRole "()" --identity smoke-associate)
check "suspended user getMyRole returns null" "null" "$RESULT"
echo ""

# ── Step 11: grantOperations ─────────────────────────────────────────────────
echo "Step 11: grantOperations — grant ops principal"
icp canister call backend grantOperations "(principal \"$OPS_PRINCIPAL\")"
echo "  grantOperations succeeded"
RESULT=$(icp canister call backend getOperationsPrincipal "()")
check "operationsPrincipal is set after grant" "$OPS_PRINCIPAL" "$RESULT"
echo ""

# ── Step 12: revokeOperations ────────────────────────────────────────────────
echo "Step 12: revokeOperations — revoke ops"
icp canister call backend revokeOperations "()"
echo "  revokeOperations succeeded"
RESULT=$(icp canister call backend getOperationsPrincipal "()")
check "operationsPrincipal is null after revoke" "null" "$RESULT"
echo ""

# ── Summary ──────────────────────────────────────────────────────────────────
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
