#!/usr/bin/env bash
set -euo pipefail

# Regenerate backend.did from Motoko source before deploying.
# The @dfinity/motoko recipe compiles to WASM but does NOT auto-update backend.did
# when canister.yaml specifies a candid path. The CLI reads backend.did to expose
# the correct interface in the Candid UI and for canister call type-checking.
echo "Regenerating backend/backend.did from Motoko source"
(cd backend && $(mops toolchain bin moc) --idl $(mops sources) -o backend.did src/main.mo)

DEPLOYER=$(icp identity principal)
echo "Installing the_practice with master controller = $DEPLOYER"
icp deploy backend --args "(principal \"$DEPLOYER\")"
