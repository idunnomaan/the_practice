# L5 Audit — Specification

> Spec date: 2026-05-17
> Designed in: Cowork (Opus 4.7)
> Implements: the second layer of the five-layer architecture (see AGENTS.md §4)
> Source of truth for Claude Code. Any ambiguity not resolved here → ask Abdul in Cowork before coding.

---

## 1. Purpose

L5 owns the **append-only audit log**. Every state-changing operation in the canister (and certain significant reads) records an immutable entry. The log is the foundation of:

- **F-06** — Audit trail viewable by Partners, non-modifiable even by controllers
- **PDPA compliance** — data-access traceability required by the 2025 amendment
- **Meta-trust property** — those who watch the audit log are themselves watched (audit-log reads are audited)

L5 is built **before L4** (per the architectural ordering in AGENTS.md §4 — Unix principle: log at the boundary, append-only, before logic). This means every L4 business action will be auditable from the moment it's written, with no retrofit pass.

L5 also defines the **"significant read" boundary** that future L4 endpoints must honor.

---

## 2. The significant read principle (referenced by L4 later)

A read operation is **significant** (and MUST emit an audit entry) when it produces data that leaves the canister boundary in a form usable outside this system:

- **Document downloads** — file bytes returned to the caller (the file now exists on their machine; can be forwarded, leaked, or printed)
- **Bulk exports** — the F-07 export endpoint
- **Audit log reads themselves** — knowing who is reviewing the audit log is itself a security-relevant event

A read is **not significant** (NOT audited) when it returns metadata or UI-scale data that doesn't leave the canister in a portable form:

- Document metadata listings (filename, date, matter, type — no bytes)
- Matter / client search results
- User listings, role lookups
- Dashboard summaries and counts

L5 implements this principle for its own `readAuditEntries` call. L4 will inherit and apply it.

---

## 3. Locked decisions

| # | Decision | Source |
|---|---|---|
| Q1 | **Log writes + auth failures + significant reads** (per §2 above). Skip metadata reads. | Cowork 2026-05-17 |
| Q2 | **Entry shape: standard.** `{ id, timestamp, caller, action, target, outcome }`. No before/after payload diff. | Cowork 2026-05-17 |
| Q3 | **Append-only enforcement: API surface only.** No `delete`, `modify`, or `clear` endpoint exists. Master controller could in principle push a malicious upgrade to add one, but `reinstall` destroys all state (self-evident as malicious). Certified-variables hardening (option B) documented as Era 3 work. | Cowork 2026-05-17 |
| Q4 | **Partner role only** reads the audit log. Master controller without Partner role cannot read directly (must self-assign via `addUser`, which is itself audited). | Cowork 2026-05-17 |
| Q5 | **No certified variables in Phase 1.** Defer to Era 3 when external auditors/regulators need cryptographic proof against a malicious-replica scenario. | Cowork 2026-05-17 |
| Q6 | **Retention: forever.** No rotation. Storage estimate at ~200 bytes/entry × 100K entries/year = ~20 MB/year — decades before 50 GB cap matters. | Cowork 2026-05-17 |
| Q7 | **Cursor-based pagination.** `readAuditEntries(after: Nat, limit: Nat)` — returns entries with `id > after`, capped at `limit ≤ 1000`. | Cowork 2026-05-17 |
| Q8 | **Per-mutator inline emission.** Each L1 (and future L2/L4) mutator explicitly calls `auditOk(...)` or `auditErr(...)`. Plain, traceable, no magic. | Cowork 2026-05-17 |
| Q8a | **L1 trap→Result refactor lands in a SEPARATE prep commit** before L5 commit. L5 commit is then purely additive. | Cowork 2026-05-17 |
| — | `readAuditEntries` is itself an **update call (not a query)**, because queries cannot write state — and Q1=C requires every audit-log read to leave its own entry. ~2s cost per access is acceptable for periodic review workflows. | Derived from Q1+Q4 |
| — | **No certified data, so no `postupgrade` re-certification step is needed.** (Reminder for if/when Era 3 adds Q5=B.) | Derived from Q5 |

---

## 4. Data model

```motoko
public type AuditOutcome = {
  #ok;
  #err : Text;       // human-readable reason on failure
};

public type AuditEntry = {
  id : Nat;          // monotonically increasing, starts at 1
  timestamp : Time.Time;  // nanoseconds since epoch, from Time.now()
  caller : Principal;     // who initiated the action
  action : Text;          // method name, e.g. "grantOperations", "readAuditEntries"
  target : ?Principal;    // principal acted upon, if any
  outcome : AuditOutcome;
};
```

State on the persistent actor (in addition to L1's existing state):

- `auditLog : Map.Map<Nat, AuditEntry>` — keyed by `id`, ordered by `Nat.compare`
- `nextAuditId : Nat` — monotonic counter, starts at `1`, incremented on every append

**Use `mo:core/Map` (mutable variant) NOT `mo:core/pure/Map`.** Audit log is append-heavy; mutable Map gives O(log n) inserts in-place rather than rebuilding the structure each time. Pagination needs `Map.entriesFrom(map, Nat.compare, after)` — verify this API exists in `mo:core 2.3.1` when fetching the motoko skill. If the API name differs, use the equivalent range-iterator from the same module.

**Note on consistency with L1:** L1 uses `mo:core/pure/Map` for `users`. The user map is rarely mutated and benefits from immutable semantics for clarity. The audit log has opposite access patterns. This is a deliberate inconsistency — different data structures for different access patterns is the right call, not a sign of disorder.

---

## 5. Public interface

### 5.1 Queries

**None added by L5.** Audit log reads cannot be queries because queries cannot write state, and we require every audit-log read to itself be audited (Q1=C + meta-trust property). L1's existing queries (`whoAmI`, `getMyRole`, etc.) are unaffected.

### 5.2 Updates (write, ~2s, consensus-verified)

Every update method below MUST:

1. Reject anonymous principal
2. Perform its role check (returning `Result.Result<T, Text>`)
3. Emit an audit entry via `auditOk(...)` or `auditErr(...)` BEFORE returning

| Method | Caller required | Args | Returns | Behavior |
|---|---|---|---|---|
| `readAuditEntries` | Partner | `(after: Nat, limit: Nat)` | `Result.Result<[AuditEntry], Text>` | Returns entries with `id > after`, up to `min(limit, 1000)`. Records `auditOk(caller, "readAuditEntries", null)` before returning. On auth failure: records `auditErr(caller, "readAuditEntries", null, "not authorized")` and returns `#err("not authorized")`. |

### 5.3 Internal helpers (Motoko-only, called by other layers)

These replace L1's stub `audit(...)` function. They are the canonical emission API for all current and future layers.

| Helper | Signature | Behavior |
|---|---|---|
| `auditOk(caller, action, target)` | `Principal × Text × ?Principal → ()` | Appends `{ id = nextAuditId; timestamp = Time.now(); caller; action; target; outcome = #ok }`. Increments `nextAuditId`. |
| `auditErr(caller, action, target, reason)` | `Principal × Text × ?Principal × Text → ()` | Appends `{ ...; outcome = #err(reason) }`. Increments `nextAuditId`. |

These helpers live in `backend/src/Audit.mo`. They are stateful (touch `auditLog` and `nextAuditId`), so they must live inside the actor class — NOT in a module. (Per `l1_patterns.md` memory: stateful helpers belong on the actor; stateless helpers in modules. Compile error `M0235` if you try to pass actor state to a module function.)

The shape: `Audit.mo` defines the **types** (`AuditEntry`, `AuditOutcome`) and any stateless helpers (e.g., a pure pagination utility). The mutating `auditOk` / `auditErr` functions are defined inside the actor class in `main.mo`.

---

## 6. Initialization & upgrade handling

At install (extends L1 init from spec L1 §5):

1. `auditLog := Map.empty<Nat, AuditEntry>()`
2. `nextAuditId := 1`
3. After L1's master-controller-as-Partner registration, emit ONE entry:
   `auditOk(installer.caller, "install", ?masterControllerArg)`
   This makes the install event itself appear as audit entry `id = 1`.

Upgrade: no manual `pre_upgrade` / `post_upgrade` hooks needed. The `persistent actor` declaration persists `auditLog` and `nextAuditId` across upgrades automatically (per the `stable-memory` skill — verify when fetched).

No certified data is set, so no `postupgrade` re-certification step. (If Era 3 adds Q5=B, this is the line item that gets added.)

---

## 7. Security invariants

The implementation must guarantee these. Add comments naming each one next to the relevant code.

1. **No public method mutates the audit log other than via append.** No `delete`, `modify`, or `clear` endpoint exists in the Candid interface. (Q3 enforced at API surface.)
2. **Every L1 mutator emits exactly one audit entry per invocation.** Either `auditOk(...)` on success or `auditErr(...)` on auth/business failure. Emission happens BEFORE the function returns, so it is part of the committed state.
3. **Audit emission is atomic with the mutating action.** Both succeed together (single message commit) or both fail together (trap → both rolled back). No partial states.
4. **Audit log reads are themselves audited.** `readAuditEntries` calls `auditOk` (success) or `auditErr` (auth failure) before returning.
5. **Partner-only read enforcement.** `readAuditEntries` checks `requireRole(caller, #Partner)`. Failed checks return `#err("not authorized")` AND record `auditErr` with reason.
6. **Monotonic ID property.** `nextAuditId` strictly increases by 1 per emission. No gaps under normal operation. Gaps in returned entry IDs would indicate tampering (an Era 3 certified-variables migration would make this externally verifiable).
7. **Timestamps come from `Time.now()` only.** No caller-provided timestamps anywhere.
8. **No method uses `canister_inspect_message` as a security boundary.** (Carryover from L1 — same rationale from `canister-security` skill pitfall #1.)
9. **The `auditLog` map and `nextAuditId` counter are NOT exposed via any query or update method other than `readAuditEntries`** (which paginates). No "dump entire log" endpoint, no length-counter endpoint, no oldest/newest-N endpoint. Pagination is the only read path.

---

## 8. Prerequisite refactor (separate prep commit, lands BEFORE L5)

Per Q8a, the L1 trap→Result refactor lands as its own commit so the L5 commit can be purely additive. Scope:

**Files touched in the prep commit:**

| File | Change |
|---|---|
| `backend/src/Auth.mo` | All `requireXxx` helpers refactored: signature changes from `Principal → ()` (with internal trap) to `Principal → Result.Result<(), Text>`. The body returns `#err("...")` instead of `Runtime.trap("...")`, and `#ok(())` on success. |
| `backend/src/main.mo` | Every L1 mutator that calls `requireXxx` is refactored: `switch (requireXxx(caller)) { case (#err(e)) { return #err(e) }; case (#ok) { ... existing body ... } }`. Return type changes from `async ()` (or whatever it was) to `async Result.Result<(), Text>` or `async Result.Result<T, Text>` for methods that return a value. |
| `backend/src/main.mo` | The existing stub `audit(...)` function is left in place during the prep commit, called as before. It will be replaced in the L5 commit. |
| `backend/backend.did` | Regenerated by `scripts/deploy-local.sh` (Candid signatures change because return types change). |
| `scripts/smoke-l1.sh` | Update assertions to expect `Result` shape responses (`(variant { ok })` instead of `()`). Rename file to `scripts/smoke.sh` since it will cover L1+L5 after the next commit. |

**Prep commit message:** `Refactor L1 auth helpers from trap to Result for L5 audit-on-failure support`

**Verification before merging the prep commit:**

- `icp build` succeeds
- `scripts/smoke.sh` (renamed) passes all existing L1 assertions, now with Result-shaped responses
- No frontend changes
- Diff size: ~50-100 lines

**Why a separate commit:** keeps the L5 commit purely additive (new file `Audit.mo`, new state fields, new methods, new audit emissions). Reviewing two small focused commits is easier than one tangled one. Also enables a clean revert if L5 has a bug — the refactor is independently useful.

---

## 9. Acceptance criteria — what "L5 done" means

The implementer must verify all of these locally before reporting done.

1. `icp build` succeeds with no errors or warnings.
2. `mops test` runs (zero tests acceptable — confirms toolchain).
3. `icp deploy` (via `scripts/deploy-local.sh`) succeeds.
4. Candid UI shows the new `readAuditEntries` method with correct signature, plus all existing L1 methods now returning `Result` shape.
5. `scripts/smoke.sh` runs and passes. It must:
   - Install the canister
   - Confirm `readAuditEntries(0, 10)` returns the install event as entry `id = 1`
   - Call `grantOperations` from the master controller, then confirm a new audit entry appears with `action = "grantOperations"`, `target = ?<grantedPrincipal>`, `outcome = #ok`
   - Call `addUser` to add an Associate; confirm audit entry appears
   - Call `setUserRole` to change that user's role; confirm audit entry
   - Switch to an unauthorized identity (e.g., `smoke-staff`) and call `grantOperations`; confirm it returns `#err(...)` AND that an audit entry with `outcome = #err("not authorized")` is recorded
   - Call `readAuditEntries(0, 1000)` as a Partner; confirm all preceding entries returned, IDs monotonically increasing, last entry's `action = "readAuditEntries"` (proving meta-trust property)
   - Call `readAuditEntries(0, 1000)` as a non-Partner; confirm `#err` returned AND an audit entry with `action = "readAuditEntries"`, `outcome = #err("not authorized")` recorded
   - Cursor pagination: call `readAuditEntries(0, 3)`, note the last `id`, then call `readAuditEntries(<that id>, 3)`, confirm the next 3 entries are returned with no gaps and no overlap
   - Document each step with `echo` lines explaining what's being tested
6. The smoke script renames from `smoke-l1.sh` to `smoke.sh`.

---

## 10. Files to create or modify

**Prep commit (commit 1):**

| File | Action |
|---|---|
| `backend/src/Auth.mo` | Refactor: `requireXxx` helpers return `Result.Result<(), Text>` instead of trapping. |
| `backend/src/main.mo` | Refactor: all L1 mutators handle Result returns; signatures change to `Result.Result<T, Text>`. |
| `backend/backend.did` | Regenerated by deploy-local.sh. |
| `scripts/smoke-l1.sh` → `scripts/smoke.sh` | Rename + update assertions for Result-shaped responses. |

**L5 commit (commit 2, purely additive):**

| File | Action |
|---|---|
| `backend/src/Audit.mo` | Create. Defines `AuditEntry`, `AuditOutcome` types and any stateless pagination helpers. |
| `backend/src/main.mo` | Add `auditLog` and `nextAuditId` state. Add `auditOk` / `auditErr` mutating helpers inside the actor class. Replace stub `audit(...)` calls with real `auditOk` / `auditErr`. Add `readAuditEntries` public update method. Add the install-event emission in the init block. |
| `backend/backend.did` | Regenerated by deploy-local.sh. |
| `scripts/smoke.sh` | Extend with L5 assertions (per §9). |
| `frontend/` | Do NOT modify. |
| `AGENTS.md`, `CLAUDE.md` | Do NOT modify. |

---

## 11. Skills the implementer MUST fetch before writing code

In this order:

1. `https://skills.internetcomputer.org/skills/motoko/SKILL.md` — re-fetch. Critical: verify `mo:core/Map` (mutable) API for inserts and `entriesFrom` range iteration in version `2.3.1`. Verify `Result.Result` patterns.
2. `https://skills.internetcomputer.org/skills/stable-memory/SKILL.md` — re-fetch. Confirm `Map.Map` (mutable) under `persistent actor` declaration upgrades cleanly with no manual hooks.
3. `https://skills.internetcomputer.org/skills/canister-security/SKILL.md` — already in Cowork context. Verify the Result-returning pattern for auth helpers matches current best practice.
4. `https://skills.internetcomputer.org/skills/mops-cli/SKILL.md` — re-fetch only if you need to add a dependency. (Audit.mo should not need anything outside `mo:core`.)

**Skip:** `certified-variables` skill — not needed for Phase 1 (Q5=A). Reference it only if revisiting in Era 3.

If any skill reveals a contradiction with this spec, STOP and report it back to Abdul before coding around it.

---

## 12. Out of scope for L5

- Certified variables / cryptographic tamper-evidence (Era 3)
- Time-range pagination (defer; cursor sufficient for Phase 1)
- Audit log export endpoint (will be part of F-07 in L4)
- Frontend audit log viewer UI (frontend phase, post-L4)
- Document download audit emission (L4 will use `auditOk(...)` — helper is now available)
- Log rotation / retention policies (defer; storage estimate gives decades of headroom)
- Diff-based audit entries (before/after payloads) — Q2 locked at B (standard shape), C (full diff) deferred indefinitely
- Multi-canister log replication (Era 3 if it becomes relevant)

---

## 13. When you (Claude Code) think you're done

Before reporting "L5 complete," run this checklist:

1. [ ] Two commits exist: `(prep)` L1 trap→Result refactor + `(L5)` audit log additions. Both pass `icp build` independently if you check out either.
2. [ ] All 9 security invariants in §7 are enforceable from code (add a comment naming each one where it's enforced).
3. [ ] All acceptance criteria in §9 pass via `scripts/smoke.sh`.
4. [ ] No files in `frontend/` were modified.
5. [ ] `AGENTS.md` and `CLAUDE.md` are untouched (Cowork will update them after review).
6. [ ] You fetched the relevant skills BEFORE writing any code.
7. [ ] Total diff across both commits is reasonable (~300-500 LOC). If larger, you probably over-engineered something — pause and ask.
8. [ ] Both commits pushed to `origin/main` after smoke passes.

Then report back to Cowork: list of files changed per commit, line counts, one-paragraph summary of smoke test output, and any decisions you made that weren't in this spec (we'll review them in Cowork before moving to L2).

---

*This spec is locked. If you find a real ambiguity, stop and ask Abdul. Don't improvise.*
