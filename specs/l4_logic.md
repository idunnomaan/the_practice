# L4 Logic — Specification

> Spec date: 2026-05-19
> Designed in: Cowork (Opus 4.7)
> Implements: the fifth and final layer of Phase 1 (see AGENTS.md §4)
> Source of truth for Claude Code. Any ambiguity not resolved here → ask Abdul in Cowork before coding.

> **Scope:** Cross-entity search (F-04), bulk export pathway (F-07), and dashboard-support count queries. L4 is purely additive — no new state, no new entity types, no new persisted data structures. All L4 methods compose existing L1-L2b primitives.

---

## 1. Purpose

L4 completes the Phase 1 feature surface. With L4 shipped, the canister implements F-01 through F-08 end-to-end. Specifically L4 delivers:

- **F-04 cross-entity search** — `searchClients`, `searchMatters`, `searchDocuments`, each accepting a structured filter record. Per-matter listing already exists from L2b; L4 fills in the cross-matter / cross-entity case.
- **F-07 bulk export** — `createExportManifest`, the single labeled audit event for "the firm initiated a full export." Client orchestrates the actual downloads via existing `prepareDocumentDownload` + `getChunk`.
- **Dashboard counts** — `mattersByStatus`, `clientsByStatus`, `documentsByStatus`. Three small queries to support at-a-glance partner dashboards without forcing the frontend to do paginated full-listings just to count.

L4 introduces no new entity types or persistent state. The implementation is method additions over the Maps already populated by L1-L2b. After L4 ships, the only thing left before Studio Stage 4 (handover) is frontend wiring.

---

## 2. Locked decisions

### Locked by prior architectural choices (stated, not asked)

| # | Decision | Source |
|---|---|---|
| — | **No new persistent state.** All L4 methods compose existing L1-L2b primitives. | L4 scope decision. |
| — | **Searches are queries (not update calls), not audited.** Consistent with the L5 "significant read" principle — metadata listings don't move bytes off the canister. The audit signal remains tied to where bytes actually move (downloads, exports). | L5 pattern. |
| — | **No `pre_upgrade` / `post_upgrade` hooks.** All L4 changes obey the L3 persistence contract. | L3 pattern. |
| — | **Audit emission via existing `auditOk` / `auditErr` from L5.** Only `createExportManifest` emits — searches don't. | L5 pattern. |

### L4 design decisions (Cowork 2026-05-19)

| # | Decision |
|---|---|
| Q1 | **Search interface: per-entity methods.** `searchClients(filter, after, limit)`, `searchMatters(filter, after, limit)`, `searchDocuments(filter, after, limit)`. Each returns its own typed entity (no polymorphic return). |
| Q2 | **Filter shapes per entity** as defined in §3.1. All filter fields are optional. Provided fields AND together. |
| Q3 | **Text matching: substring, case-insensitive.** Both haystack and needle lowercased before comparison. |
| Q4 | **Search execution: in-memory iteration over the relevant Map.** Filter as we go, paginate by entity ID. No pre-built indexes. Acceptable for Phase 1 firm scale (low thousands of matters). |
| Q5 | **Searches not audited.** Consistent with existing `listClients` / `listMatters` / `listDocumentsByMatter`. |
| Q6 | **Export: dedicated `createExportManifest` update method** returning a structured manifest record. Client orchestrates file downloads via existing primitives using the manifest as a checklist. No server-side zip generation. |
| Q7 | **Export manifest scope: everything.** Includes soft-deleted clients, archived matters, deleted documents, full version chain per document, full audit log size, user roster, storage metadata, canister metadata (master controller, operations principal). |
| Q8 | **Export access: Partner role required.** Operations principal (with no user role per L1) cannot export. Multiple Partners in the firm may initiate exports. |
| Q9 | **Dashboard support: three count-by-status queries.** `mattersByStatus()`, `clientsByStatus()`, `documentsByStatus()`. Single-pass O(n) counts, no caching. |
| Q10 | **No server-side joins.** Frontend chains queries when joining is needed (e.g., search matters by partner → then list documents per matched matter). |

### Derived decisions

| Topic | Decision |
|---|---|
| **Document search matching semantics** | `searchDocuments` matches against the document's **current version only** (its `currentVersionId → DocumentVersion`). Filename, content type, uploaded-by, upload date filters all apply to `currentVersion`. A document whose current version doesn't match the filter is excluded even if an older version would have matched. Full version-history search is out of scope. |
| **Search result shape for documents** | Returns `[DocumentSearchResult]` — a bundled type containing the `Document` AND its `currentVersion` (with `blob` field stripped to empty Blob, per L2b's `listVersions` cost pattern). Saves frontend a round-trip. |
| **Default `statusFilter` semantics** | When `statusFilter` is `null` (not provided): `searchClients` returns only `#Active`; `searchMatters` returns all non-`#Archived` (Open, OnHold, Closed); `searchDocuments` returns only `#Active`. Pass an explicit `statusFilter` to widen. |
| **Empty filter behavior** | A filter record with all fields `null` is valid — it returns all entities (with default status filter applied). Effectively a "find any" query. Useful for frontend "show all" behavior with cursor pagination. |
| **Filter conjunction** | All non-null filter fields AND together. No OR support. To OR, frontend issues multiple queries and merges client-side. |
| **`createExportManifest` arity** | Zero arguments. The manifest always returns the complete current canister state (per Q7). No "scope" parameter for partial exports — that would multiply audit ambiguity ("did they export everything or just clients?"). One method, one shape, one audit event. |

---

## 3. Data model

### 3.1 Filter records

```motoko
public type ClientFilter = {
  nameContains : ?Text;
  clientType : ?ClientType;
  statusFilter : ?ClientStatus;       // null → #Active only
  identifierContains : ?Text;
  createdAfter : ?Time.Time;
  createdBefore : ?Time.Time;
};

public type MatterFilter = {
  titleContains : ?Text;
  matterTypeContains : ?Text;
  clientId : ?Nat;                    // restrict to one client
  assignedPartner : ?Principal;
  statusFilter : ?MatterStatus;       // null → all except #Archived
  openedAfter : ?Time.Time;
  openedBefore : ?Time.Time;
  closedAfter : ?Time.Time;
  closedBefore : ?Time.Time;
};

public type DocumentFilter = {
  filenameContains : ?Text;
  contentType : ?Text;                // exact match (whitelist value)
  matterId : ?Nat;
  statusFilter : ?DocumentStatus;     // null → #Active only
  uploadedAfter : ?Time.Time;
  uploadedBefore : ?Time.Time;
  uploadedBy : ?Principal;
};
```

### 3.2 Search result types

```motoko
public type DocumentSearchResult = {
  document : Document;
  currentVersion : DocumentVersion;   // blob stripped to empty Blob for cost
};
```

`searchClients` returns `[Client]`. `searchMatters` returns `[Matter]`. `searchDocuments` returns `[DocumentSearchResult]`.

### 3.3 Status count records

```motoko
public type MatterStatusCounts = {
  open : Nat;
  onHold : Nat;
  closed : Nat;
  archived : Nat;
};

public type ClientStatusCounts = {
  active : Nat;
  inactive : Nat;
};

public type DocumentStatusCounts = {
  active : Nat;
  deleted : Nat;
};
```

### 3.4 Export manifest

```motoko
public type ExportManifest = {
  generatedAt : Time.Time;
  generatedBy : Principal;
  totalClients : Nat;
  totalMatters : Nat;
  totalDocuments : Nat;
  totalVersions : Nat;
  totalAuditEntries : Nat;
  storageUsedBytes : Nat;
  storageBudgetBytes : Nat;
  masterController : Principal;
  operationsPrincipal : ?Principal;
  clientIds : [Nat];              // all client IDs (active + inactive)
  matterIds : [Nat];              // all matter IDs (all statuses)
  documents : [{ documentId : Nat; versionIds : [Nat] }];  // version chain per doc
  userPrincipals : [Principal];   // all registered users from L1
};
```

The manifest is the **index** for export. The actual entity records (`Client`, `Matter`, `DocumentVersion` blobs, `AuditEntry` data) are retrieved via existing primitives using the IDs in the manifest. This keeps the manifest call cheap (a list of IDs, not a payload of full records and bytes).

### 3.5 State

**No new persistent state.** L4 adds methods only.

---

## 4. Public interface

Every L4 query uses `requireAuthenticated` (trap on anonymous — queries can't audit). Every L4 update emits exactly one audit entry.

### 4.1 Queries — search (not audited)

| Method | Caller | Args | Returns | Behavior |
|---|---|---|---|---|
| `searchClients` | any authenticated | `(filter : ClientFilter, after : Nat, limit : Nat)` | `[Client]` | Iterates `clients` Map. For each client where `id > after`, applies the filter (all non-null fields AND together; default `statusFilter` excludes `#Inactive`). Returns up to `min(limit, 1000)` matches in ascending ID order. |
| `searchMatters` | any authenticated | `(filter : MatterFilter, after : Nat, limit : Nat)` | `[Matter]` | Iterates `matters` Map. Filter logic as above. Default `statusFilter` excludes `#Archived`. |
| `searchDocuments` | any authenticated | `(filter : DocumentFilter, after : Nat, limit : Nat)` | `[DocumentSearchResult]` | Iterates `documents` Map. For each doc: fetch its `currentVersion`; apply filter against `Document` AND `currentVersion` fields; return matches as `DocumentSearchResult` tuples (blob stripped to empty). Default `statusFilter` excludes `#Deleted`. |

### 4.2 Queries — dashboard counts (not audited)

| Method | Caller | Args | Returns | Behavior |
|---|---|---|---|---|
| `mattersByStatus` | any authenticated | `()` | `MatterStatusCounts` | Single pass over `matters` Map, increment the appropriate count for each. |
| `clientsByStatus` | any authenticated | `()` | `ClientStatusCounts` | Single pass over `clients` Map. |
| `documentsByStatus` | any authenticated | `()` | `DocumentStatusCounts` | Single pass over `documents` Map. |

### 4.3 Updates — export (audited)

| Method | Caller | Args | Returns | Behavior |
|---|---|---|---|---|
| `createExportManifest` | **Partner role required** | `()` | `Result.Result<ExportManifest, Text>` | Validates role. Iterates all relevant Maps to compute counts and ID lists. Populates the manifest. Emits `auditOk(caller, "createExportManifest", null)` before returning. On role failure: emits `auditErr` and returns `#err("not authorized")`. |

### 4.4 Internal helpers

**Stateless (in `backend/src/Search.mo` — new module):**

| Helper | Behavior |
|---|---|
| `containsCI(haystack : Text, needle : Text) : Bool` | Lowercases both sides via `Text.toLowercase`, then `Text.contains(haystack, #text needle)`. Used by all `*Contains` filters. |
| `inTimeRange(t : Time.Time, after : ?Time.Time, before : ?Time.Time) : Bool` | Returns true if `t > after.unwrap_or(MIN) AND t < before.unwrap_or(MAX)`. Either bound being null means unbounded on that side. |
| `matchesClientFilter(c : Client, f : ClientFilter) : Bool` | All non-null fields in `f` must match. Default `statusFilter` (null) excludes `#Inactive`. |
| `matchesMatterFilter(m : Matter, f : MatterFilter) : Bool` | All non-null fields must match. Default `statusFilter` excludes `#Archived`. |
| `matchesDocumentFilter(d : Document, v : DocumentVersion, f : DocumentFilter) : Bool` | All non-null fields must match — across both `Document` (matterId, status) and `DocumentVersion` (filename, contentType, dates, uploader). Default `statusFilter` excludes `#Deleted`. |

**Stateful (on actor class):**

| Helper | Behavior |
|---|---|
| `stripBlobFromVersion(v : DocumentVersion) : DocumentVersion` | Returns the same version with `blob = ""` (empty Blob). Used by `searchDocuments` before returning. |

---

## 5. Initialization & upgrade handling

- **No state to initialize.** L4 adds no fields to the persistent actor.
- **No init changes.**
- **No upgrade hooks** (per L3 persistence contract).
- The existing `Map`s populated by L1, L2, and L2b are all L4 needs to iterate.

---

## 6. Security invariants

1. **Anonymous principal cannot search, count, or export.** All query methods trap via `requireAuthenticated`; update method returns `#err` via the existing `requireAuthenticated` pattern.
2. **Searches do not expose data the caller couldn't reach via existing primitives.** Search is a filter, not a privilege gate — it iterates the same Maps that `listClients`, `listMatters`, etc. already expose to any authenticated user. If a user can't read it via `getClient(id)`, the search won't return it either (because they're the same Map).
3. **`createExportManifest` requires `#Partner` role.** Enforced via `requireRole(caller, #Partner)`. Operations principal has no user role per L1 and therefore cannot export. Anonymous and Staff/Associate also rejected.
4. **`createExportManifest` emits exactly one audit entry** per call — success or failure. Auth failure path emits `auditErr` with reason "not authorized"; success path emits `auditOk(caller, "createExportManifest", null)`.
5. **No method modifies any existing state.** L4 is read-only over L1-L2b state, plus the audit append for `createExportManifest`.
6. **Search pagination limit enforced.** `limit > 1000` is clamped to 1000.
7. **Empty filter is valid and intentional.** A filter with all fields `null` returns all entities matching the default `statusFilter`. This is the "show all with default scope" use case for the frontend.
8. **Filter conjunction is AND, never OR.** Implementation must not accidentally implement OR semantics.
9. **`searchDocuments` matches against the current version only.** Older versions are not searched. Document this explicitly in the method's comment.
10. **No method uses `canister_inspect_message` as a security boundary.**
11. **L4 introduces no new `Runtime.trap` calls in update paths** (only queries trap on anonymous). The `createExportManifest` update returns `Result` for all error cases.

---

## 7. Acceptance criteria — what "L4 done" means

Smoke test extends `scripts/smoke.sh` starting at Step 86 (L3 ends at Step 85).

1. `icp build` succeeds.
2. `mops test` runs.
3. `icp deploy` succeeds.
4. Candid UI shows all new methods.
5. `scripts/smoke.sh` runs and passes. New L4 assertions must include:

   **Search — clients:**
   - Create 5 clients with varying names ("Acme Holdings", "Smith & Partners", "Smithson Trading", "Lotus Bank", "smith Bros"). Confirm `searchClients({ nameContains = ?"smith"; ... null fields }, 0, 1000)` returns 3 clients (case-insensitive match).
   - Confirm filter for `clientType = ?#Company` returns only company-type clients.
   - Confirm filter for `identifierContains = ?"NIC"` on a client with that identifier substring works.
   - Confirm date range filter (`createdAfter`, `createdBefore`) returns expected subset.
   - Confirm compound filter (multiple non-null fields) ANDs correctly.
   - Confirm empty filter returns all active clients.
   - Confirm `statusFilter = ?#Inactive` returns soft-deleted clients only.

   **Search — matters:**
   - Create matters with varying titles and types. Confirm `searchMatters({ titleContains = ?"acme" })` works.
   - Confirm `clientId = ?N` filter returns only that client's matters.
   - Confirm `assignedPartner = ?p` filter works.
   - Confirm default behavior excludes `#Archived` matters.
   - Confirm `statusFilter = ?#Archived` includes archived only.

   **Search — documents:**
   - Upload documents with different filenames and content types. Confirm `searchDocuments({ filenameContains = ?"contract" })` returns docs whose current version's filename contains "contract" (case-insensitive).
   - Confirm `contentType = ?"application/pdf"` filter works.
   - Confirm `uploadedBy = ?p` filter works against current version's uploader.
   - Confirm version-history limitation: upload a doc with filename "alpha.pdf" → upload v2 renamed to "beta.pdf" → search for "alpha" — should NOT return this doc (current version doesn't match).
   - Confirm returned `DocumentSearchResult` has empty `blob` field.

   **Pagination:**
   - `searchMatters({...}, 0, 2)` then `searchMatters({...}, <last id>, 2)` — confirm no overlap, no gaps.

   **Dashboard counts:**
   - After creating mixed-status matters, confirm `mattersByStatus()` returns correct counts per status.
   - After soft-deleting a client, confirm `clientsByStatus()` reflects the change.
   - After deleting a document, confirm `documentsByStatus()` reflects the change.

   **Export:**
   - Partner calls `createExportManifest()`. Confirm `#ok(manifest)`. Confirm `manifest.totalClients`, `totalMatters`, `totalDocuments`, etc. match actual canister state.
   - Confirm `manifest.clientIds`, `matterIds`, etc. are populated with all IDs (active + inactive).
   - Confirm one audit entry with `action = "createExportManifest"`, `outcome = #ok` recorded.
   - Switch to Associate identity. Try `createExportManifest()`. Confirm `#err("not authorized")` AND `auditErr` entry recorded.
   - Switch to Staff identity. Same — confirm rejection + audit.
   - Try as anonymous — confirm rejection.
   - (Operations principal cannot be tested directly in smoke unless the smoke script switches to that identity; since operations principal has no role per L1, any role check fails. Skip unless trivial to add.)

6. Step counter continues from L3's actual end (~85). L4 additions should land around 18-22 steps, ending roughly at Step 103-107.

---

## 8. Files to create or modify

| File | Action |
|---|---|
| `backend/src/Search.mo` | **Create.** Filter types (`ClientFilter`, `MatterFilter`, `DocumentFilter`), the bundled `DocumentSearchResult` type, status-count types (`MatterStatusCounts`, `ClientStatusCounts`, `DocumentStatusCounts`), and stateless match helpers (`containsCI`, `inTimeRange`, `matchesClientFilter`, `matchesMatterFilter`, `matchesDocumentFilter`). |
| `backend/src/Export.mo` | **Create.** Defines `ExportManifest` type. Stateless. Just types. |
| `backend/src/main.mo` | **Extend.** Add 6 query methods (3 search + 3 count) and 1 update method (`createExportManifest`). Add the small stateful helper `stripBlobFromVersion`. Wire the stateless helpers from `Search.mo`. |
| `backend/backend.did` | Regenerated by `scripts/deploy-local.sh`. |
| `scripts/smoke.sh` | Extend in-place with L4 assertions per §7. Starts at Step 86. |
| `frontend/app/src/backend/api/...` | Auto-regenerated TypeScript bindings. Commit as expected. |
| `frontend/` (other than auto-bindings) | Do NOT modify. |
| `AGENTS.md`, `CLAUDE.md` | Do NOT modify. Cowork updates after diff review. |
| `PERSISTENCE.md` | No changes — L4 introduces no new persistent state. |

Estimated total LOC: **~450-550** (Search.mo ~120, Export.mo ~25, main.mo additions ~250-300, smoke.sh additions ~120-150). L4 is smaller than L2b because there's no chunking, hashing, or session machinery — just method additions over existing data.

---

## 9. Skills the implementer MUST fetch before writing code

In this order:

1. `https://skills.internetcomputer.org/skills/motoko/SKILL.md` — re-fetch. Verify: (a) `Text.toLowercase` and `Text.contains` APIs in `mo:core 2.3.1` — these are central to the substring matcher; (b) `Map.Map` iteration patterns (`Map.entries`, `Map.values`, `Map.size`); (c) idiomatic filter combinator patterns.
2. `https://skills.internetcomputer.org/skills/canister-security/SKILL.md` — already in project memory. Verify role-tier patterns unchanged.
3. `https://skills.internetcomputer.org/skills/mops-cli/SKILL.md` — fetch only if `Text.contains` requires a separate dependency. Likely not — string ops are core.

**Skip:** `certified-variables`, `stable-memory` (no new state, no upgrade considerations), `asset-canister`, `internet-identity`, `migrating-motoko`.

If any skill reveals a contradiction with this spec, STOP and report it back to Abdul.

---

## 10. Out of scope for L4

- Server-side cross-entity joins (e.g., "documents in matters assigned to partner X"). Frontend chains existing queries.
- Full-text search inside document content (would require document indexing — heavy compute, defer indefinitely).
- Saved searches / search history.
- Search across document version history (current-version-only is locked).
- OR semantics in filter records (AND only).
- Pre-built indexes for search acceleration.
- Activity feed / timeline views (use existing `readAuditEntries` with cursor pagination).
- Custom report generation.
- Server-side zip / tarball assembly for export (client orchestrates downloads).
- Import / restoration endpoints (export is one-way).
- Dashboard aggregations beyond status counts (e.g., "top partners by matter count" — defer).
- Frontend UI for any of these surfaces.
- Era 2 features (HTTPS outcalls for AI integration, cycles management automation, vetKD).

---

## 11. When you (Claude Code) think you're done

Before reporting "L4 complete," run this checklist:

1. [ ] Single commit on top of `main` (purely additive, no prep refactor).
2. [ ] All 11 security invariants in §6 are enforceable from code (add a comment naming each one where it's enforced).
3. [ ] All acceptance criteria in §7 pass via `scripts/smoke.sh`. Total smoke step count should now be ~103-107 (L3 ended at 85; L4 adds ~18-22).
4. [ ] No new persistent state added (verify by checking diff against `persistent actor` body — only methods/helpers should be new).
5. [ ] No files in `frontend/` modified other than auto-regenerated bindings.
6. [ ] `AGENTS.md`, `CLAUDE.md`, `PERSISTENCE.md` untouched.
7. [ ] Skills fetched BEFORE coding.
8. [ ] Total diff is reasonable (~450-550 LOC).
9. [ ] Pushed to `origin/main` after Abdul's explicit approval.

Then report back to Cowork: files changed, line counts, smoke test output summary, and **any decisions made that weren't in this spec** (especially anything around `Text.contains` / `Text.toLowercase` if those APIs aren't where expected, or any subtle filter semantics that came up during smoke).

**Once L4 ships, the canister is feature-complete for Phase 1.** Cowork will then update PROJECT_CONTEXT.md to mark First Build complete and begin the transition to Studio Stage 4 (founding client conversations, FCA refresh, frontend wiring).

---

*This spec is locked. If you find a real ambiguity, stop and ask Abdul. Don't improvise.*
