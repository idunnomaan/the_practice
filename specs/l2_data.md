# L2 Data — Specification (Client + Matter)

> Spec date: 2026-05-18
> Designed in: Cowork (Opus 4.7)
> Implements: the third layer of the five-layer architecture (see AGENTS.md §4)
> Source of truth for Claude Code. Any ambiguity not resolved here → ask Abdul in Cowork before coding.

> **Scope note:** This spec covers L2 Data for **Clients and Matters only.** Document storage (chunked upload, versioning, content-type handling) is split off into a subsequent spec — call it **L2b Documents** — which will be designed after L2 ships. The split is intentional: data records and binary-blob storage are different design problems and deserve focused passes.

---

## 1. Purpose

L2 owns the **business data records** of the canister:

- **Clients** — the firm's customers (individuals, companies, or other)
- **Matters** — units of legal work, each belonging to one Client

L2 defines:
- The data types for Client and Matter
- The on-actor state holding them
- The full CRUD-and-lifecycle API surface
- Foreign-key integrity rules between Matters and Clients
- Soft-delete semantics (no hard delete)

L2 builds on L1 (role-gated access) and L5 (audit emission). Every L2 mutator uses L1's `requireRole`-on-the-Result-path pattern, and emits via L5's `auditOk` / `auditErr` helpers. No new infrastructure is added — L2 is the first "business layer" that consumes the foundations.

L2 does NOT include:
- Document storage (deferred to L2b)
- Cross-entity search ("find matters with title containing X") — deferred to L4
- Per-matter ACL — deferred indefinitely; Phase 1 uses role-tier access only
- Reporting, analytics, exports — L4 (F-07)

---

## 2. Locked decisions

| # | Decision | Source |
|---|---|---|
| Q1 | **L2 scope = Client + Matter only.** Documents become L2b in a separate later spec. | Cowork 2026-05-18 |
| Q2 | **Client shape: standard** — `name`, `clientType`, `primaryEmail`, `primaryPhone`, `identifier`, `notes`, `status`, audit-lineage fields. | Cowork 2026-05-18 |
| Q3 | **Matter shape: standard** — `title`, `matterType`, `clientId`, `assignedPartner`, `description`, `status`, dates, audit-lineage fields. | Cowork 2026-05-18 |
| Q4 | **`matterType` is free-text** (UI normalizes via dropdown of recommended values). | Cowork 2026-05-18 |
| Q5 | **Status fields are variants** — `ClientStatus { #Active, #Inactive }`, `MatterStatus { #Open, #OnHold, #Closed, #Archived }`. Lifecycle enforcement at type level. | Cowork 2026-05-18 |
| Q6 | **ID strategy: monotonic `Nat` per entity** — `nextClientId`, `nextMatterId`. Independent counters. | Cowork 2026-05-18 |
| Q7 | **Storage: mutable `mo:core/Map`** (default going forward). L1's `pure/Map` stays as-is — no refactor. | Cowork 2026-05-18 |
| Q8 | **Soft delete only, no cascade.** No `deleteClient` / `deleteMatter` in API. Soft-delete via status change. Reject `deactivateClient` if the client has any matters in `#Open` or `#OnHold`. | Cowork 2026-05-18 |
| Q9 | **Read = any authenticated user. Write = Partner only.** Associates and Staff are read-only on Clients and Matters in Phase 1. | Cowork 2026-05-18 |
| Q10 | **FK enforcement: strict.** `createMatter` rejects if `clientId` doesn't exist OR if the client is `#Inactive`. Same check on `updateMatter` if `clientId` changes. | Cowork 2026-05-18 |
| Q11 | **Cursor pagination** following L5's pattern. Limit ≤ 1000. Listings filter by status (default = active/open only); explicit flags to include inactive/closed/archived. | Cowork 2026-05-18 |
| — | **Matter status transitions are governed by API design** — separate methods per allowed transition (`closeMatter`, `archiveMatter`, etc.) rather than a single `setMatterStatus(newStatus)`. Cleaner UI mapping, individually-audited actions. | Derived from Q5 |
| — | **Archived is terminal.** Once a matter is `#Archived`, no further state changes are allowed. (To revive: create a new matter, reference the old one in description.) | Derived from Q5 |
| — | **No reactivation of inactive clients is part of L2 surface?** Yes — include `reactivateClient`. Real-world need: "we soft-deleted the wrong client; undo." Audited like any other state change. | Cowork 2026-05-18 |

---

## 3. Data model

### 3.1 Client

```motoko
public type ClientType = {
  #Individual;
  #Company;
  #Other;
};

public type ClientStatus = {
  #Active;
  #Inactive;   // soft-deleted; not surfaced in default listings
};

public type Client = {
  id : Nat;
  name : Text;
  clientType : ClientType;
  primaryEmail : ?Text;
  primaryPhone : ?Text;
  identifier : ?Text;            // NIC for individuals, BR-no for companies — free-form, no validation in L2
  notes : Text;                  // free-form; empty string allowed
  status : ClientStatus;
  createdAt : Time.Time;
  createdBy : Principal;
  lastModifiedAt : Time.Time;
  lastModifiedBy : Principal;
};
```

### 3.2 Matter

```motoko
public type MatterStatus = {
  #Open;
  #OnHold;
  #Closed;
  #Archived;   // terminal — no further transitions allowed
};

public type Matter = {
  id : Nat;
  title : Text;
  matterType : Text;             // free-form per Q4
  clientId : Nat;                // FK → Client.id; enforced on create/update
  assignedPartner : ?Principal;  // null = unassigned; Partner role enforced when set
  description : Text;            // free-form; empty string allowed
  status : MatterStatus;
  openedAt : Time.Time;          // set at create time = Time.now()
  closedAt : ?Time.Time;         // set when status becomes #Closed; null otherwise
  createdAt : Time.Time;
  createdBy : Principal;
  lastModifiedAt : Time.Time;
  lastModifiedBy : Principal;
};
```

### 3.3 State (added to the persistent actor)

In addition to existing L1 + L5 state:

- `clients : Map.Map<Nat, Client>` — keyed by `Client.id`
- `matters : Map.Map<Nat, Matter>` — keyed by `Matter.id`
- `nextClientId : Nat` — starts at 1, increments on each `createClient`
- `nextMatterId : Nat` — starts at 1, increments on each `createMatter`

Both Maps use `Nat.compare` as the ordering function. Declared with `let` (per `l5_patterns.md` — mutable Map mutates in-place; binding never reassigned).

### 3.4 Allowed Matter status transitions

```
#Open      → #OnHold, #Closed
#OnHold    → #Open, #Closed
#Closed    → #Open (reopen), #Archived
#Archived  → (terminal — no transitions)
```

Any transition not in this set rejects with `#err("invalid status transition: X → Y")` and emits `auditErr`.

---

## 4. Public interface

All update methods MUST:

1. Reject anonymous principal via existing `requireAuthenticated` pattern
2. Perform role check via `requireRole(caller, #Partner)` (returns `Result.Result<(), Text>`)
3. Validate inputs (FK existence, status transition allowed, etc.)
4. Emit `auditOk(caller, "<methodName>", ?target)` on success OR `auditErr(caller, "<methodName>", ?target, reason)` on any failure
5. Return `Result.Result<T, Text>` (never trap on the mutator path)

### 4.1 Queries (read-only, NOT audited per Q11)

| Method | Caller required | Returns | Behavior |
|---|---|---|---|
| `getClient(id : Nat)` | any authenticated | `?Client` | Returns the client or null. Includes inactive clients. |
| `listClients(after : Nat, limit : Nat, includeInactive : Bool)` | any authenticated | `[Client]` | Cursor pagination by `id > after`, up to `min(limit, 1000)`. If `includeInactive = false`, filters out `#Inactive`. |
| `getMatter(id : Nat)` | any authenticated | `?Matter` | Returns the matter or null. Includes all statuses. |
| `listMatters(after : Nat, limit : Nat, statusFilter : ?MatterStatus)` | any authenticated | `[Matter]` | Cursor pagination. `statusFilter = null` returns all statuses; `?#Open` filters to `#Open` only. |
| `listMattersByClient(clientId : Nat, after : Nat, limit : Nat, statusFilter : ?MatterStatus)` | any authenticated | `[Matter]` | Same as `listMatters` but pre-filtered to one client. |
| `getClientCount()` | any authenticated | `Nat` | Total clients in store (active + inactive). Cheap. |
| `getMatterCount()` | any authenticated | `Nat` | Total matters in store (all statuses). Cheap. |

Queries use `requireAuthenticated` (trap on anonymous — queries can't audit, so trap is fine here per `l5_patterns.md`).

### 4.2 Updates — Client lifecycle

| Method | Caller | Args | Behavior |
|---|---|---|---|
| `createClient` | Partner | `{ name : Text; clientType : ClientType; primaryEmail : ?Text; primaryPhone : ?Text; identifier : ?Text; notes : Text }` | Generates `id = nextClientId`, increments counter, sets `status = #Active`, fills audit-lineage fields. Returns `Result.Result<Nat, Text>` with the new id on success. Reject if `name` is empty after `Text.trim`. |
| `updateClient` | Partner | `(id : Nat, fields : { name : ?Text; clientType : ?ClientType; primaryEmail : ?Text; primaryPhone : ?Text; identifier : ?Text; notes : ?Text })` | Sparse update — only provided fields change. Updates `lastModifiedAt` / `lastModifiedBy`. Rejects if client doesn't exist or is `#Inactive`. Status changes go through `deactivateClient` / `reactivateClient` only. |
| `deactivateClient` | Partner | `(id : Nat)` | Sets `status = #Inactive`. Rejects if any of this client's matters are `#Open` or `#OnHold` (with message naming the count). Rejects if already inactive. |
| `reactivateClient` | Partner | `(id : Nat)` | Sets `status = #Active`. Rejects if client doesn't exist or is already active. |

### 4.3 Updates — Matter lifecycle

| Method | Caller | Args | Behavior |
|---|---|---|---|
| `createMatter` | Partner | `{ title : Text; matterType : Text; clientId : Nat; assignedPartner : ?Principal; description : Text }` | Generates `id = nextMatterId`, increments counter, sets `status = #Open`, `openedAt = Time.now()`, `closedAt = null`. **FK check:** rejects if client doesn't exist or is `#Inactive`. If `assignedPartner` is provided, verify it's a registered user with `#Partner` role (use L1's `getMyRole`-equivalent helper internally). Returns the new id. Reject if `title` is empty after trim. |
| `updateMatter` | Partner | `(id : Nat, fields : { title : ?Text; matterType : ?Text; clientId : ?Nat; assignedPartner : ?(?Principal); description : ?Text })` | Sparse update. **If `clientId` is provided:** re-runs FK check against new client. **If `assignedPartner` is `?(?Principal)`:** outer `?` means "is this field being updated?", inner `?Principal` means "the new value (null = unassign)". Updates `lastModifiedAt` / `lastModifiedBy`. Status changes go through dedicated methods only. Rejects if matter doesn't exist or is `#Archived`. |
| `closeMatter` | Partner | `(id : Nat)` | Sets `status = #Closed`, `closedAt = Time.now()`. Rejects unless current status is `#Open` or `#OnHold`. |
| `reopenMatter` | Partner | `(id : Nat)` | Sets `status = #Open`, `closedAt = null`. Rejects unless current status is `#Closed`. **Cannot reopen `#Archived`.** |
| `putMatterOnHold` | Partner | `(id : Nat)` | Sets `status = #OnHold`. Rejects unless current status is `#Open`. |
| `resumeMatter` | Partner | `(id : Nat)` | Sets `status = #Open`. Rejects unless current status is `#OnHold`. |
| `archiveMatter` | Partner | `(id : Nat)` | Sets `status = #Archived`. Rejects unless current status is `#Closed`. **Terminal: no transitions out of `#Archived`.** |
| `assignPartnerToMatter` | Partner | `(id : Nat, partner : ?Principal)` | Sets `assignedPartner`. `null` clears assignment. Verifies `partner` (if non-null) is a registered Partner. Rejects if matter doesn't exist or is `#Archived`. |

### 4.4 Internal helpers

Stateless (live in `Client.mo` / `Matter.mo` modules):

| Helper | Behavior |
|---|---|
| `isValidMatterTransition(from : MatterStatus, to : MatterStatus) : Bool` | Pure function encoding §3.4 transition table. |

Stateful (live on actor class):

| Helper | Behavior |
|---|---|
| `lookupClientActive(id : Nat) : Result.Result<Client, Text>` | Returns the client if it exists AND is `#Active`. Used by `createMatter` and `updateMatter` for FK enforcement. |
| `countMattersByClientAndStatus(clientId : Nat, statuses : [MatterStatus]) : Nat` | Used by `deactivateClient` to count open/onhold matters before allowing soft-delete. |

---

## 5. Initialization & upgrade handling

At install (extends prior L1+L5 init):

1. `clients := Map.empty<Nat, Client>()`
2. `matters := Map.empty<Nat, Matter>()`
3. `nextClientId := 1`
4. `nextMatterId := 1`
5. **No install audit event for L2** — these are empty stores; the existing L5 install event covers the canister-install record. (L5 emits one entry at id=1 from `auditOk(installer.caller, "install", ?masterControllerArg)`.)

Upgrade: no manual hooks. `persistent actor` carries `clients`, `matters`, `nextClientId`, `nextMatterId` across upgrades automatically.

---

## 6. Security invariants

The implementation must guarantee these. Add comments naming each one in code.

1. **Anonymous principal cannot create, modify, or delete any entity.** Rejected via `requireAuthenticated` at every entry point.
2. **Only `#Partner` role can mutate.** All writes call `requireRole(caller, #Partner)`. Associates and Staff are read-only.
3. **No public method hard-deletes a Client or Matter.** Soft-delete only (`deactivateClient` / `archiveMatter`). No `delete*` endpoints exist.
4. **Foreign key integrity is enforced on every mutation.** A Matter's `clientId` must point to an existing, `#Active` Client at creation and at every `updateMatter` that changes `clientId`.
5. **Client cannot be deactivated while it has open or on-hold matters.** `deactivateClient` checks `countMattersByClientAndStatus(id, [#Open, #OnHold]) == 0` and rejects with `#err` naming the count.
6. **Matter status transitions follow §3.4 strictly.** Every transition method validates `from` status; invalid transitions return `#err` and emit `auditErr` (the audit captures attempted invalid state changes).
7. **`#Archived` matters are immutable.** `updateMatter`, `assignPartnerToMatter`, and all status-transition methods reject when current status is `#Archived`.
8. **Monotonic IDs.** `nextClientId` and `nextMatterId` strictly increase by 1 per successful create. Gaps would indicate code bugs (not tampering — IDs are not security-sensitive).
9. **Timestamps come from `Time.now()` only.** No caller-provided timestamps.
10. **Every mutator emits exactly one audit entry**, success or failure. Auth failures, FK failures, transition failures, and successful operations all produce one entry. (Same atomicity discipline as L1+L5.)
11. **No method uses `canister_inspect_message` as a security boundary.** Carryover from L1+L5.

---

## 7. Acceptance criteria — what "L2 done" means

Smoke test extends `scripts/smoke.sh` starting at Step 35 (L5 ends at Step 34).

The implementer must verify all of these locally before reporting done.

1. `icp build` succeeds with no errors or warnings.
2. `mops test` runs (zero tests OK — confirms toolchain).
3. `icp deploy` (via `scripts/deploy-local.sh`) succeeds.
4. Candid UI shows all new query and update methods with correct signatures.
5. `scripts/smoke.sh` runs and passes. New L2 assertions must include:
   - **Client create + read.** Partner calls `createClient` with name "Acme Holdings PLC", `#Company`. Confirm returns `#ok(1)`. Confirm `getClient(1)` returns the record. Confirm audit entry recorded with `action = "createClient"`.
   - **Client list pagination.** Create 3 clients. Call `listClients(0, 2, false)`. Confirm 2 returned. Call `listClients(2, 2, false)`. Confirm 1 returned (the third). No overlap, no gaps.
   - **Client update.** Partner calls `updateClient` to change `primaryEmail`. Confirm field updated. Confirm `lastModifiedAt` advanced. Audit entry recorded.
   - **Matter create + FK enforcement.** Try `createMatter` with `clientId = 999` (nonexistent). Confirm `#err("client 999 not found")` AND audit entry with `outcome = #err`. Then `createMatter` with `clientId = 1`. Confirm success, returns `#ok(1)`. Audit entry recorded.
   - **Matter FK enforcement on inactive client.** `deactivateClient(2)` (a client with no open matters — should succeed). Try `createMatter` with `clientId = 2`. Confirm rejection (`#err("client 2 is inactive")`).
   - **`deactivateClient` reject-on-open-matters.** With matter id=1 still `#Open`, try `deactivateClient(1)`. Confirm rejection (`#err("client 1 has 1 open matter(s); close or archive them first")`) AND audit entry.
   - **Matter status lifecycle.** Sequence: `putMatterOnHold(1)` → `resumeMatter(1)` → `closeMatter(1)` → confirm `closedAt` set. Then `reopenMatter(1)` → confirm `closedAt` cleared. Then `closeMatter(1)` again → `archiveMatter(1)`. Confirm `#Archived`. Try `updateMatter(1, ...)`. Confirm rejection (`#err("matter 1 is archived")`).
   - **Invalid status transition.** Try `archiveMatter` on an `#Open` matter. Confirm rejection (`#err("invalid status transition: Open → Archived")`).
   - **Reopen-archived rejected.** Try `reopenMatter` on an `#Archived` matter. Confirm rejection.
   - **Non-Partner write rejected.** Switch identity to `smoke-staff`. Try `createClient`. Confirm `#err("not authorized")` AND audit entry with that user and `outcome = #err`.
   - **Non-Partner reads allowed.** As `smoke-staff`, call `listClients`. Confirm success.
   - **`listMattersByClient`.** Create 3 matters for client 1, plus 1 for a different client. Call `listMattersByClient(1, 0, 1000, null)`. Confirm exactly 3 returned, all with `clientId = 1`.
   - **`reactivateClient`.** Reactivate a deactivated client. Confirm `status = #Active`. Audit entry.
   - **Anonymous rejected on writes.** Switch to anonymous identity. Try `createClient`. Confirm rejection AND audit entry.

6. The new assertions extend `scripts/smoke.sh` in-place (per `l5_patterns.md`). Do NOT create per-layer smoke files.

---

## 8. Files to create or modify

| File | Action |
|---|---|
| `backend/src/Client.mo` | **Create.** Defines `ClientType`, `ClientStatus`, `Client` types. Stateless module — types only. |
| `backend/src/Matter.mo` | **Create.** Defines `MatterStatus`, `Matter` types. Plus the pure helper `isValidMatterTransition(from, to)`. Stateless module. |
| `backend/src/main.mo` | **Extend.** Add `clients`, `matters`, `nextClientId`, `nextMatterId` state. Add all queries from §4.1. Add all updates from §4.2 and §4.3. Add stateful helpers `lookupClientActive`, `countMattersByClientAndStatus`. |
| `backend/backend.did` | Regenerated by `scripts/deploy-local.sh`. |
| `scripts/smoke.sh` | Extend in-place with L2 assertions per §7. Starts at Step 35. |
| `frontend/` | Do NOT modify. Frontend integration is post-L4. |
| `AGENTS.md`, `CLAUDE.md` | Do NOT modify. Cowork updates these after diff review. |

Estimated total LOC: ~400-500 (Client.mo ~40, Matter.mo ~50, main.mo additions ~250-300, smoke.sh additions ~80-100).

---

## 9. Skills the implementer MUST fetch before writing code

In this order:

1. `https://skills.internetcomputer.org/skills/motoko/SKILL.md` — re-fetch. Confirm: (a) `mo:core/Map` mutable variant API for inserts/lookups/range iteration in version `2.3.1`, (b) `Result.Result` patterns, (c) sparse-update pattern in Motoko (likely matching on `?T` field-by-field).
2. `https://skills.internetcomputer.org/skills/stable-memory/SKILL.md` — re-fetch. Confirm adding new `Map.Map` fields to the existing `persistent actor` upgrades cleanly. (Adding new fields is a different upgrade scenario than the empty-canister-install case L5 verified.)
3. `https://skills.internetcomputer.org/skills/canister-security/SKILL.md` — already in our project memory. Verify role-based access control patterns are unchanged since L5.
4. `https://skills.internetcomputer.org/skills/mops-cli/SKILL.md` — re-fetch only if you need to add a dependency. L2 should not need anything outside `mo:core`.

**Skip:** `certified-variables`, `internet-identity`, `migrating-motoko` — not relevant to L2.

If any skill reveals a contradiction with this spec, STOP and report it back to Abdul before coding around it.

---

## 10. Out of scope for L2

- Document storage (deferred to L2b — separate spec, will follow L2)
- Cross-entity search ("matters with title containing X", "all matters created after date Y") — L4 work, F-04
- Per-matter ACL (per-matter user lists) — deferred indefinitely; Phase 1 uses role-tier access
- Reporting / analytics endpoints — L4
- Bulk export — L4 (F-07)
- Soft-delete recovery UI — frontend phase
- Client merge / matter merge — defer until a firm asks for it
- Matter-to-matter relationships (parent/child, related-to) — defer
- Activity timelines per matter — derive from audit log at L4
- Hard delete of any entity — explicitly excluded; not exposed in API

---

## 11. When you (Claude Code) think you're done

Before reporting "L2 complete," run this checklist:

1. [ ] Single commit on top of `main` (no prep refactor needed — L5 already did the trap→Result refactor; L2 is purely additive).
2. [ ] All 11 security invariants in §6 are enforceable from code (add a comment naming each one where it's enforced).
3. [ ] All acceptance criteria in §7 pass via `scripts/smoke.sh`. Total smoke step count should now be roughly 50+ (L1+L5 was 34; L2 adds ~15-20).
4. [ ] No files in `frontend/` were modified.
5. [ ] `AGENTS.md` and `CLAUDE.md` untouched.
6. [ ] Skills fetched BEFORE coding.
7. [ ] Total diff is reasonable (~400-500 LOC). If significantly larger, you probably over-engineered something — pause and ask.
8. [ ] Pushed to `origin/main` after Abdul's explicit approval.

Then report back to Cowork: files changed, line counts, smoke test output summary, any decisions made that weren't in this spec (we'll review them in Cowork before moving to L2b — Documents).

---

*This spec is locked. If you find a real ambiguity, stop and ask Abdul. Don't improvise.*
