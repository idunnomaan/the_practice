# Persistence Contract

## How it works

This canister is declared as a `persistent actor`. The Internet Computer's Enhanced
Orthogonal Persistence (EOP) automatically serialises the entire actor heap — including
large `Blob` values stored in document chunks — before each upgrade and restores it
afterward. No application code is involved.

## What persists

Every `let` and `var` declared directly on the actor. This includes identity and control
state, the audit ledger, client and matter records, document versions and chunk data,
in-flight upload sessions, storage accounting counters, and the Firm Library state
added in Phase 1.5 (see table below).

### Firm Library state fields (Phase 1.5)

| Field | Type | Role |
|---|---|---|
| `folders` | `MutMap<Nat, Folder>` | All folders; hard-deleted on `deleteFolder` after empty check |
| `libraryItems` | `MutMap<Nat, LibraryItem>` | All items including soft-deleted (`#Deleted`) |
| `libraryVersions` | `MutMap<Nat, LibraryVersion>` | All versions; each stores the full `Blob` |
| `libraryVersionsByItem` | `MutMap<Nat, [Nat]>` | Ordered version IDs per item (append-only) |
| `libraryUploadSessions` | `MutMap<Nat, LibraryUploadSession>` | In-flight sessions; deleted on finalize or abandon (separate from L2b `uploadSessions`) |
| `nextFolderId` | `Nat` | Monotone counter; never reused |
| `nextLibraryItemId` | `Nat` | Monotone counter; never reused |
| `nextLibraryVersionId` | `Nat` | Monotone counter; never reused |
| `nextLibrarySessionId` | `Nat` | Monotone counter; never reused |

The shared storage budget (`totalStorageUsedBytes`, `storageBudgetBytes`) is declared in
L2b and covers both document uploads and library item uploads (Q8 decision).

## What does NOT persist

`transient var` declarations reset to their initial values on every upgrade. None are
currently used in this actor — all declared state is persistent.

## Hard rules

**Never add `pre_upgrade` or `post_upgrade` hooks.**

If a hook traps (throws any error during upgrade), the upgrade is aborted and the
canister is permanently bricked — unrecoverable without a canister snapshot. EOP
makes hooks unnecessary. This is canister-security pitfall #4.

## Adding a new field

Just declare it. ICP initialises missing fields to their declared default values on the
first post-declaration upgrade. No migration script needed for purely additive changes.

## Changing an existing field type

Consult the `migrating-motoko` skill before touching any existing field type. A type
mismatch at upgrade time causes the upgrade to trap, which bricks the canister.
Never change field types without a migration plan.

## Verification

The upgrade survival test lives in `scripts/smoke.sh` at Steps 74–85. It captures
pre-upgrade state, runs `icp deploy --mode upgrade`, then asserts all values are intact
post-upgrade.
