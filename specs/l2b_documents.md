# L2b Documents — Specification

> Spec date: 2026-05-18
> Designed in: Cowork (Opus 4.7)
> Implements: binary document storage layer, deferred from L2 (see `the_practice_specs_L2_data.md` Q1)
> Source of truth for Claude Code. Any ambiguity not resolved here → ask Abdul in Cowork before coding.

> **Scope:** Chunked binary blob storage with versioning, content-type validation, storage budget enforcement, and a fast-read download path. Documents belong to Matters (FK enforced). Builds on L1 (role gates), L5 (audit), L2 (FK to Matter via `clientId → Client`, `documentId → Matter`).

---

## 1. Purpose

L2b owns **document storage** — the firm's PDFs, DOCX files, images, etc. Per F-03: ≤100 MB per file, versioned, 50 GB initial budget. Per F-04: retrievable by matter (cross-entity search is L4 work).

L2b introduces three things not yet present in the canister:

1. **Binary blob storage** via `Blob` fields on the `persistent actor`. Leverages Enhanced Orthogonal Persistence (EOP) for >4 GB allocations.
2. **Session-based chunked upload pattern.** IC ingress messages cap at ~2 MB; files ≤100 MB require chunking. Sessions track in-progress uploads.
3. **Split read path.** Download intent is captured via an update call (audited); chunk bytes flow via query calls (fast, not per-chunk-audited). Q7 trade-off accepted — one audit entry per download intent, not per chunk read.

L2b is the foundation for F-03 (storage) and F-04 (retrieval by matter). L4 will build search/filter (by client, date, type, filename) on top of L2b's primitives. F-07 (bulk export) is also an L4 problem that consumes L2b.

---

## 2. Locked decisions

### Locked by prior architectural choices (stated, not asked)

| # | Decision | Source |
|---|---|---|
| — | **Storage backend:** `Blob` field inside `Map.Map<Nat, Blob>` on the `persistent actor`. EOP handles >4 GB allocations transparently. No separate asset canister, no off-chain storage. | Project decision: "Full on-canister storage." |
| — | **Per-file size limit:** ≤100 MB. Reject in `startUpload`. | F-03 spec. |
| — | **Soft-delete only.** No hard-delete API. `deleteDocument` sets `status = #Deleted`; bytes remain in storage and count against budget. | L2 pattern carryover. |
| — | **Audit emission:** every mutator calls `auditOk` / `auditErr` from L5. | L5 pattern. |
| — | **ID strategy:** monotonic `Nat` per entity. `nextDocumentId`, `nextVersionId`, `nextSessionId`. Independent counters. | L1/L5/L2 pattern. |
| — | **Storage:** mutable `mo:core/Map`, declared with `let` not `var`. | L5 pattern (`l5_patterns.md`). |

### L2b design decisions (Cowork 2026-05-18)

| # | Decision |
|---|---|
| Q1 | **Upload pattern: session-based** — `startUpload → appendChunk* → finalizeUpload`. Server tracks the session. |
| Q2 | **Chunk size: 1 MB (1,048,576 bytes) fixed.** Conservative under ~2 MB ingress cap; predictable cycles cost. |
| Q3 | **Versioning model: Document + DocumentVersion entities.** A Document points to its `currentVersionId`; all versions retained. |
| Q4 | **Content type validation: strict whitelist.** Allowed: `application/pdf`, `application/msword`, `application/vnd.openxmlformats-officedocument.wordprocessingml.document`, `image/png`, `image/jpeg`, `image/gif`, `image/webp`. Anything else rejected. No magic-byte verification (deferred). |
| Q5 | **Storage budget: enforced at API.** `startUpload` rejects if `currentTotalStorageUsed + totalSizeBytes > storageBudgetBytes`. Default budget = 50 GB (53,687,091,200 bytes). Mutable via `setStorageBudget(newBytes)`, callable by master controller or operations principal. |
| Q6 | **Hash: SHA-256 of the assembled blob, computed once at `finalizeUpload`.** Returned to caller for verification; stored on `DocumentVersion`. |
| Q7 | **Download access: prepare-update + chunk-query split.** `prepareDocumentDownload(versionId)` is an update call (audited, ~2s, returns metadata + sha256). `getChunk(versionId, chunkIndex)` is a query call (~200ms, role-gated, not per-chunk-audited). **Trade-off accepted Phase 1:** an insider bypassing the official UI can call `getChunk` without first calling `prepareDocumentDownload`, getting bytes without leaving an audit entry. Mitigations: (a) all callers still authenticated and role ≥ Staff; (b) Era 2+ can tighten via token-based access (option C from design) or all-chunks-via-update (option A). |
| Q8 | **Write access tier (diverges from L2's Partner-only-writes):** Associates and Partners can `startUpload`, `appendChunk`, `finalizeUpload`, `abandonUpload`. **Only Partners can `deleteDocument`.** Staff are read-only. |
| Q9 | **Upload session cleanup: none for Phase 1.** Abandoned sessions persist until explicit `abandonUpload(sessionId)` is called. No TTL, no heartbeat GC. Manual ops cleanup if needed. Documented known accumulation point. |
| Q10 | **Listing API: per-matter only.** `listDocumentsByMatter(matterId, after, limit, includeDeleted)` for documents. `listVersions(documentId)` for version history (no pagination needed; few versions per document). Admin queries: `getDocumentCount()`, `getStorageUsed()`, `getStorageBudget()`. No global document list (deferred to L4 search). |

### Derived decisions worth flagging in implementation

| Topic | Decision |
|---|---|
| **Audit `target` field for document-targeting actions** | L5's `AuditEntry.target : ?Principal` was designed for principal targets. For L2b actions (`documentUpload`, `documentDownload`, `documentDelete`), there is no Principal target — the target is a Document ID (a `Nat`). For Phase 1: emit with `target = null` and encode entity reference in the `action` string as `"documentDownload:42"` (where 42 is the documentId). This is a known limitation. L4 / Era 2 may refactor `AuditEntry` to add a generalized `targetEntityType : Text` + `targetEntityId : Nat` field; not L2b's job. |
| **Chunk replacement (idempotency)** | `appendChunk(sessionId, chunkIndex, chunkBytes)` allows resubmission of the same chunkIndex — last write wins. This makes the client resilient to transient network failures (retry the chunk). Server-side check: same session, same caller. |
| **Empty files** | Reject `totalSizeBytes == 0` in `startUpload`. Empty documents are not meaningful and complicate the chunking math. |
| **Last chunk size** | Chunk 0..N-2 must be exactly 1 MB. The last chunk (index N-1) may be smaller (the remainder). Validated at `appendChunk`. |
| **Caller-locked sessions** | Only the user who called `startUpload` can call `appendChunk`, `finalizeUpload`, or `abandonUpload` on that session. Other authenticated users cannot interfere with another's upload. |

---

## 3. Data model

### 3.1 Document

```motoko
public type DocumentStatus = {
  #Active;
  #Deleted;   // soft-deleted; bytes remain but not surfaced in default listings
};

public type Document = {
  id : Nat;
  matterId : Nat;            // FK → Matter.id (must exist and not be #Archived)
  currentVersionId : Nat;    // FK → DocumentVersion.versionId
  status : DocumentStatus;
  createdAt : Time.Time;     // = uploadedAt of v1
  createdBy : Principal;
};
```

### 3.2 DocumentVersion

```motoko
public type DocumentVersion = {
  versionId : Nat;           // global monotonic
  documentId : Nat;          // FK → Document.id
  versionNumber : Nat;       // per-document: 1, 2, 3, ...
  filename : Text;           // can change across versions
  contentType : Text;        // validated against whitelist at upload
  sizeBytes : Nat;
  blob : Blob;               // the actual bytes
  sha256 : Blob;             // 32 bytes
  uploadedAt : Time.Time;
  uploadedBy : Principal;
  uploadNotes : Text;        // free-form, e.g. "post-redline draft"; empty allowed
};
```

### 3.3 UploadSession (transient — deleted on finalize/abandon)

```motoko
public type UploadSession = {
  sessionId : Nat;
  matterId : Nat;
  filename : Text;
  contentType : Text;
  totalSizeBytes : Nat;
  expectedChunkCount : Nat;       // = ceil(totalSizeBytes / CHUNK_SIZE)
  uploadNotes : Text;
  replacesDocumentId : ?Nat;      // null = new doc; ?id = new version of existing
  chunks : Map.Map<Nat, Blob>;    // keyed by chunkIndex 0..N-1
  startedAt : Time.Time;
  startedBy : Principal;          // session is caller-locked
};
```

### 3.4 State (added to the `persistent actor`)

In addition to existing L1 + L5 + L2 state:

- `documents : Map.Map<Nat, Document>` — keyed by `Document.id`
- `documentVersions : Map.Map<Nat, DocumentVersion>` — keyed by `DocumentVersion.versionId`
- `versionsByDocument : Map.Map<Nat, [Nat]>` — for each `documentId`, the list of versionIds in order. Maintained on finalize. Used by `listVersions`.
- `uploadSessions : Map.Map<Nat, UploadSession>` — active sessions
- `nextDocumentId : Nat` — starts at 1
- `nextVersionId : Nat` — starts at 1
- `nextSessionId : Nat` — starts at 1
- `totalStorageUsedBytes : Nat` — running counter, incremented on `finalizeUpload`, never decremented in Phase 1 (soft-delete doesn't free)
- `storageBudgetBytes : Nat` — starts at `53_687_091_200` (50 GB). Mutable via `setStorageBudget`.

### 3.5 Constants

```motoko
let CHUNK_SIZE : Nat = 1_048_576;         // 1 MB
let MAX_FILE_SIZE : Nat = 100_000_000;    // 100 MB
let DEFAULT_STORAGE_BUDGET : Nat = 53_687_091_200;  // 50 GB

let ALLOWED_CONTENT_TYPES : [Text] = [
  "application/pdf",
  "application/msword",
  "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  "image/png",
  "image/jpeg",
  "image/gif",
  "image/webp",
];
```

---

## 4. Public interface

Every update method MUST:

1. Reject anonymous principal (`requireAuthenticated`)
2. Perform role check via `requireRole(caller, #Associate)` for uploads, `requireRole(caller, #Partner)` for deletes, `requireRole(caller, #Staff)` for downloads (returns `Result.Result<(), Text>`)
3. Validate inputs (FK checks, content type, size limits, session ownership)
4. Emit `auditOk(caller, "<action>:<entityId>", null)` on success OR `auditErr(...)` on failure
5. Return `Result.Result<T, Text>` (never trap on the mutator path)

Every query method uses `requireAuthenticated` (trap on anonymous — queries can't audit).

### 4.1 Queries (read-only, NOT audited)

| Method | Caller | Returns | Behavior |
|---|---|---|---|
| `getDocument(id : Nat)` | any authenticated | `?Document` | Returns the document (any status) or null. |
| `listDocumentsByMatter(matterId, after, limit, includeDeleted)` | any authenticated | `[Document]` | Cursor pagination on `Document.id`. Filter by `matterId`. Default `includeDeleted = false` excludes `#Deleted`. Limit ≤ 1000. |
| `getDocumentVersion(versionId : Nat)` | any authenticated | `?DocumentVersion` | Returns version metadata + blob. **NOT for download.** Used for inspection / version-info display. For downloads use `prepareDocumentDownload` + `getChunk`. |
| `listVersions(documentId : Nat)` | any authenticated | `[DocumentVersion]` | Returns all versions for a document (metadata only; blob fields stripped to empty for cost). No pagination — version count per doc is small. |
| `getDocumentCount()` | any authenticated | `Nat` | Total documents in store (any status). |
| `getStorageUsed()` | any authenticated | `Nat` | `totalStorageUsedBytes`. |
| `getStorageBudget()` | any authenticated | `Nat` | `storageBudgetBytes`. |
| `getChunk(versionId : Nat, chunkIndex : Nat)` | any authenticated (role ≥ Staff) | `?Blob` | Returns the chunk bytes for that version + index. Null if version not found, document not `#Active`, or chunkIndex out of range. Computed on-demand by slicing the stored blob: `[chunkIndex * CHUNK_SIZE, min((chunkIndex+1) * CHUNK_SIZE, sizeBytes))`. **NOT audited per chunk — that's the Q7 trade-off.** |

**Note on `listVersions` blob stripping:** to keep the query cheap, populate each returned `DocumentVersion` with an empty `Blob` for the `blob` field. The actual bytes are retrieved via `getChunk`. Document this in the method's signature comment.

### 4.2 Upload updates (session-based)

| Method | Caller | Args | Returns | Behavior |
|---|---|---|---|---|
| `startUpload` | Associate or higher | `{ matterId : Nat; filename : Text; contentType : Text; totalSizeBytes : Nat; uploadNotes : Text; replacesDocumentId : ?Nat }` | `Result.Result<Nat, Text>` | Validates everything (see §4.6 helper checks). Creates session with `sessionId = nextSessionId`. Returns `#ok(sessionId)`. |
| `appendChunk` | Associate or higher | `(sessionId : Nat, chunkIndex : Nat, chunkBytes : Blob)` | `Result.Result<(), Text>` | Validates session exists, `caller == session.startedBy`, `chunkIndex < expectedChunkCount`, and `chunkBytes.size()` is either `CHUNK_SIZE` (any non-last chunk) or `≤ CHUNK_SIZE` and equals `totalSizeBytes - chunkIndex * CHUNK_SIZE` (the last chunk). Stores chunk in `session.chunks` (replacing if already present — idempotent). |
| `finalizeUpload` | Associate or higher | `(sessionId : Nat)` | `Result.Result<{ documentId : Nat; versionId : Nat; sha256 : Blob }, Text>` | Validates session, caller-lock, completeness (`Map.size(session.chunks) == expectedChunkCount`, all indices 0..N-1 present). Assembles blob by concatenating chunks in order. Validates assembled size equals `totalSizeBytes`. Computes sha256. If `session.replacesDocumentId` is null: creates new `Document` + v1 `DocumentVersion`. If it's `?docId`: validates docId still exists/active/in this matter, then creates new `DocumentVersion` for it, increments `versionNumber`, updates parent `Document.currentVersionId`, appends to `versionsByDocument[docId]`. Increments `totalStorageUsedBytes` by `totalSizeBytes`. Deletes session. Emits audit. |
| `abandonUpload` | Associate or higher | `(sessionId : Nat)` | `Result.Result<(), Text>` | Validates session, caller-lock. Deletes session. Emits audit. |

### 4.3 Document lifecycle updates

| Method | Caller | Args | Returns | Behavior |
|---|---|---|---|---|
| `deleteDocument` | **Partner only** | `(documentId : Nat)` | `Result.Result<(), Text>` | Validates doc exists, status is `#Active`. Sets `status = #Deleted`. Does NOT free storage. Emits audit. |

### 4.4 Download flow

| Method | Caller | Args | Returns | Behavior |
|---|---|---|---|---|
| `prepareDocumentDownload` | any authenticated (role ≥ Staff) | `(versionId : Nat)` | `Result.Result<{ documentId : Nat; sizeBytes : Nat; chunkCount : Nat; sha256 : Blob; contentType : Text; filename : Text }, Text>` | Validates version exists, parent document is `#Active`, parent matter exists (FK chain — Matter could be `#Archived`; that's still readable). Emits `auditOk(caller, "documentDownload:<documentId>", null)`. Returns metadata + sha256 + chunkCount so client knows how many `getChunk` calls to make. |

The actual chunk reads then go through `getChunk` (query — see §4.1).

### 4.5 Admin updates

| Method | Caller | Args | Returns | Behavior |
|---|---|---|---|---|
| `setStorageBudget` | Master controller OR operations principal | `(newBudgetBytes : Nat)` | `Result.Result<(), Text>` | Validates `newBudgetBytes ≥ totalStorageUsedBytes` (cannot shrink below current usage). Sets `storageBudgetBytes`. Emits audit. |

### 4.6 Internal helpers

Stateless (in `Document.mo` or a new `DocumentHelpers.mo`):

| Helper | Behavior |
|---|---|
| `isAllowedContentType(ct : Text) : Bool` | Returns true if `ct` matches one of `ALLOWED_CONTENT_TYPES`. |
| `expectedChunkCount(totalSizeBytes : Nat) : Nat` | Returns `ceil(totalSizeBytes / CHUNK_SIZE)`. |
| `chunkRange(chunkIndex : Nat, totalSize : Nat) : (Nat, Nat)` | Returns `(startByte, endByte)` for a chunk in a blob of `totalSize`. End is `min((idx+1) * CHUNK_SIZE, totalSize)`. |

Stateful (on actor class):

| Helper | Behavior |
|---|---|
| `lookupMatterActive(matterId : Nat) : Result.Result<Matter, Text>` | Returns the matter if it exists AND is not `#Archived`. Used by `startUpload` and `prepareDocumentDownload` for FK checks. (Already exists from L2 — verify and reuse.) |
| `lookupDocumentActive(docId : Nat) : Result.Result<Document, Text>` | Returns the document if it exists AND status is `#Active`. |
| `computeSha256(blob : Blob) : Blob` | Returns the 32-byte SHA-256 of the blob. Uses `mo:core` SHA primitive (verify availability when fetching the motoko skill — fall back to a `mops` SHA library if not). |
| `appendVersionToDocument(docId : Nat, versionId : Nat) : ()` | Appends `versionId` to `versionsByDocument[docId]`, initializing the list if absent. |

---

## 5. Storage budget mechanics

- Default budget: 50 GB = `53_687_091_200` bytes.
- `totalStorageUsedBytes` is incremented on every successful `finalizeUpload` by `totalSizeBytes`.
- It is **not decremented** when a document is soft-deleted (Phase 1 — bytes remain on canister).
- `setStorageBudget(newBytes)` validates `newBytes ≥ totalStorageUsedBytes` (no shrinking below usage). Otherwise rejects.
- `startUpload` rejects if `totalStorageUsedBytes + totalSizeBytes > storageBudgetBytes`. Error message: `"storage budget exceeded: would need X bytes, only Y available"`.

Era 2 may add hard-delete to reclaim space — explicitly out of scope.

---

## 6. Initialization & upgrade handling

At install (extends prior L1+L5+L2 init):

1. `documents := Map.empty<Nat, Document>()`
2. `documentVersions := Map.empty<Nat, DocumentVersion>()`
3. `versionsByDocument := Map.empty<Nat, [Nat]>()`
4. `uploadSessions := Map.empty<Nat, UploadSession>()`
5. `nextDocumentId := 1`
6. `nextVersionId := 1`
7. `nextSessionId := 1`
8. `totalStorageUsedBytes := 0`
9. `storageBudgetBytes := DEFAULT_STORAGE_BUDGET`
10. **No install audit event for L2b** — covered by L5's install event.

Upgrade: no manual hooks. `persistent actor` declaration carries all L2b state across upgrades.

**Important verify-with-skill:** confirm that storing large `Blob` fields inside a `Map.Map` under `persistent actor` upgrades cleanly — that EOP handles the >4 GB heap allocation that 50 GB of stored blobs implies. Pre-upgrade should NOT trap on serialization. If the motoko or stable-memory skill flags a concern, surface it to Abdul before implementing.

---

## 7. Security invariants

1. **Anonymous principal cannot upload, download, or delete.** Rejected at every entry point.
2. **Role-tier writes enforced:**
   - Uploads (`startUpload`, `appendChunk`, `finalizeUpload`, `abandonUpload`) require role ≥ Associate.
   - Deletes (`deleteDocument`) require role = Partner.
   - Downloads (`prepareDocumentDownload`, `getChunk`) require role ≥ Staff.
3. **Sessions are caller-locked.** Only the user who called `startUpload` can interact with that session. Other authenticated users cannot mutate someone else's in-progress upload.
4. **No public method hard-deletes a Document or DocumentVersion.** Soft-delete only via `deleteDocument`. No `delete*` endpoints for versions or blobs.
5. **FK integrity:**
   - `startUpload` rejects if `matterId` doesn't exist or is `#Archived`.
   - `startUpload` with `replacesDocumentId` rejects if doc doesn't exist, isn't in this matter, or is `#Deleted`.
   - `finalizeUpload` re-validates the FK chain on the replace path (matter could have been archived mid-upload).
6. **Content type whitelist enforced at `startUpload`.** No deferred validation.
7. **File size limit enforced** (≤100 MB) at `startUpload`.
8. **Storage budget enforced** at `startUpload`. Cannot exceed.
9. **Monotonic IDs** for documents, versions, sessions.
10. **Timestamps** from `Time.now()` only.
11. **Every mutator emits exactly one audit entry.** Auth failures, validation failures, and successes all produce one entry.
12. **`#Deleted` documents are not retrievable via `prepareDocumentDownload`.** `getChunk` validates parent document status before returning bytes.
13. **No method uses `canister_inspect_message` as a security boundary.**

---

## 8. Acceptance criteria — what "L2b done" means

Smoke test extends `scripts/smoke.sh` starting at Step 54 (L2 ends at Step 53).

1. `icp build` succeeds.
2. `mops test` runs.
3. `icp deploy` (via `scripts/deploy-local.sh`) succeeds.
4. Candid UI shows all new methods.
5. `scripts/smoke.sh` runs and passes. New L2b assertions must include:
   - **Small file upload (single chunk).** Generate a ~500 KB PDF. Partner calls `startUpload` → receives sessionId. Calls `appendChunk(sessionId, 0, blob)`. Calls `finalizeUpload`. Confirms `#ok` with documentId, versionId, sha256.
   - **Hash verification.** Compute the sha256 of the test blob client-side (via `sha256sum`). Confirm it matches the value returned by `finalizeUpload`.
   - **Multi-chunk upload.** Generate a 3.5 MB blob (3 full chunks + 1 partial). Upload via 4 `appendChunk` calls. Finalize. Confirm success and correct `sizeBytes` on the version.
   - **Out-of-order chunks.** Upload chunks in order 2, 0, 3, 1. Finalize should still succeed.
   - **Idempotent chunk replacement.** Upload chunk 1, then upload chunk 1 again with the same bytes. Both calls succeed; the chunk is stored once.
   - **Reject too-large file.** `startUpload` with `totalSizeBytes = 100_000_001`. Confirm `#err` mentioning size limit. Audit entry recorded.
   - **Reject invalid content type.** `startUpload` with `contentType = "text/csv"`. Confirm `#err`. Audit entry.
   - **Reject nonexistent matter.** `startUpload` with `matterId = 999`. Confirm `#err`. Audit entry.
   - **Reject archived matter.** Archive a matter (using L2's `archiveMatter`), then attempt upload to it. Confirm `#err`. Audit entry.
   - **Caller-lock enforcement.** User A starts upload. User B tries `appendChunk` on that session. Confirm `#err("not the session owner")`. Audit entry.
   - **Reject finalize with missing chunks.** Upload only chunks 0 and 2 (skip 1). Attempt finalize. Confirm `#err`. Audit entry.
   - **Reject finalize with wrong total size.** Upload chunks summing to 1 MB but `totalSizeBytes` declared at 2 MB. Confirm `#err`. (Will fail on missing chunk index 1 in practice, but cover the path.)
   - **Version chaining.** Upload a new version of the existing document via `replacesDocumentId`. Confirm new version has `versionNumber = 2`, parent document's `currentVersionId` updated, `listVersions(docId)` returns both versions.
   - **Delete as Associate rejected.** Switch to `smoke-associate`. Call `deleteDocument`. Confirm `#err("not authorized")`. Audit entry.
   - **Delete as Partner.** Partner calls `deleteDocument`. Confirm `#ok`. Status now `#Deleted`. `listDocumentsByMatter(..., includeDeleted = false)` excludes it. `listDocumentsByMatter(..., includeDeleted = true)` includes it.
   - **Download deleted document rejected.** Try `prepareDocumentDownload` on the deleted document. Confirm `#err`. Audit entry.
   - **Download success flow.** Upload a fresh document. `prepareDocumentDownload(versionId)` → returns metadata. Audit entry recorded with `action = "documentDownload:<docId>"`. Loop `getChunk(versionId, 0..N-1)` (query calls). Assemble. Compute local sha256. Confirm matches the returned hash.
   - **Storage budget enforcement.** `setStorageBudget(currentlyUsed + 1000)`. Attempt `startUpload` with `totalSizeBytes = 2000`. Confirm `#err("storage budget exceeded...")`. Audit entry.
   - **`setStorageBudget` reject-on-shrink-below-usage.** Try `setStorageBudget(currentlyUsed - 1)`. Confirm `#err`. Audit entry.
   - **Anonymous upload rejected.** Switch to anonymous identity. `startUpload`. Confirm rejection. Audit entry.
   - **Abandon upload.** Start an upload, append 1 chunk, then `abandonUpload`. Confirm session is gone. Audit entry.

6. Step counter continues from L2's actual ending step (53 per `l2_patterns.md`). L2b additions should land around 18-22 steps, ending roughly at Step 71-75.

---

## 9. Files to create or modify

| File | Action |
|---|---|
| `backend/src/Document.mo` | **Create.** Defines `DocumentStatus`, `Document`, `DocumentVersion`, `UploadSession` types. Plus stateless helpers: `isAllowedContentType`, `expectedChunkCount`, `chunkRange`. The constants (`CHUNK_SIZE`, `MAX_FILE_SIZE`, `DEFAULT_STORAGE_BUDGET`, `ALLOWED_CONTENT_TYPES`) live here as `public` values. |
| `backend/src/main.mo` | **Extend.** Add L2b state fields (§3.4). Add stateful helpers (`lookupDocumentActive`, `computeSha256`, `appendVersionToDocument`). Add all queries from §4.1. Add all updates from §4.2, §4.3, §4.4, §4.5. |
| `backend/mops.toml` | If `mo:core 2.3.1` doesn't include a SHA-256 primitive, add an appropriate SHA dependency (verify via motoko + mops-cli skills). Otherwise no change. |
| `backend/backend.did` | Regenerated by `scripts/deploy-local.sh`. |
| `scripts/smoke.sh` | Extend in-place with L2b assertions per §8. Starts at Step 54. |
| `frontend/app/src/backend/api/...` | Auto-regenerated TypeScript bindings will appear in this commit (per `l2_patterns.md` — auto-bindings are committed). Do NOT hand-edit. |
| `frontend/` (other than the bindings folder above) | Do NOT modify. |
| `AGENTS.md`, `CLAUDE.md` | Do NOT modify. Cowork updates after diff review. |

Estimated total LOC: **~700-900** (Document.mo ~80, main.mo additions ~500-650 spread across ~12 update methods + ~7 queries + helpers, smoke.sh additions ~120-150). L2b is bigger than L2 because of the upload session machinery, the chunk-handling logic, and SHA computation.

---

## 10. Skills the implementer MUST fetch before writing code

In this order:

1. `https://skills.internetcomputer.org/skills/motoko/SKILL.md` — re-fetch. Verify: (a) `Blob` field handling in `persistent actor`, (b) SHA-256 primitive availability (`mo:core/Sha256` or similar; if not, identify a mops library), (c) `Blob.toArray` / slicing patterns for chunk extraction in `getChunk`, (d) sparse-update pattern reminder.
2. `https://skills.internetcomputer.org/skills/stable-memory/SKILL.md` — re-fetch. **Critical:** confirm that storing 50 GB worth of `Blob` data in a `Map.Map<Nat, Blob>` under `persistent actor` declaration upgrades cleanly. If there's a soft limit or warning, surface it to Abdul before coding. (EOP should handle this but verify.)
3. `https://skills.internetcomputer.org/skills/canister-security/SKILL.md` — already in project memory. Re-confirm: caller-locked sessions; rejecting anonymous; reentrancy not applicable here (no inter-canister calls in L2b).
4. `https://skills.internetcomputer.org/skills/mops-cli/SKILL.md` — re-fetch only if SHA-256 requires adding a dependency.
5. `https://skills.internetcomputer.org/skills/asset-canister/SKILL.md` — **fetch this even though we're NOT using a separate asset canister.** It documents the canonical IC chunked-upload pattern (`store(key, content_type, chunk_ids)`, `create_batch`, `create_chunk`, `commit_batch`). Borrow the protocol shape; ignore the multi-canister parts. Our equivalents: `startUpload` ≈ `create_batch`; `appendChunk` ≈ `create_chunk`; `finalizeUpload` ≈ `commit_batch`.

**Skip:** `certified-variables`, `internet-identity`, `migrating-motoko`, `https-outcalls`, `cycles-management`, `vetkd` — not relevant to L2b.

If any skill reveals a contradiction with this spec, STOP and report it back to Abdul.

---

## 11. Out of scope for L2b

- **Cross-entity search** ("find documents by date / filename / content-type across matters") — F-04, L4 work.
- **Bulk export** — F-07, L4 work; will consume `prepareDocumentDownload` + `getChunk` repeatedly.
- **Hard delete** (free storage by removing soft-deleted bytes) — Era 2.
- **Magic-byte content type verification** — Era 2 if a threat model emerges.
- **Download token / one-time-use session authorization** — Era 2 if Q7 trade-off becomes unacceptable.
- **Upload session TTL / auto-cleanup** — defer; manual `abandonUpload` only in Phase 1.
- **In-place blob updates** — versioning replaces this. Old version remains; new version is added.
- **Frontend upload/download UI** — frontend phase, post-L4.
- **HTTP streaming via asset canister** — explicitly not using asset canister architecture.
- **Per-document ACL** — defer indefinitely; role-tier access only.
- **Document tagging / metadata extensions** — defer; the `uploadNotes` text field is the only metadata extension for Phase 1.
- **Audit `target` field refactor to support entity IDs** — known limitation; defer to L4 or Era 2.

---

## 12. When you (Claude Code) think you're done

Before reporting "L2b complete," run this checklist:

1. [ ] Single commit on top of `main` (no prep refactor needed — L5 already did trap→Result; L2b is purely additive).
2. [ ] All 13 security invariants in §7 are enforceable from code (add a comment naming each one where it's enforced).
3. [ ] All acceptance criteria in §8 pass via `scripts/smoke.sh`. Total smoke step count should now be ~71-75 (L2 ended at 53; L2b adds ~18-22).
4. [ ] No files in `frontend/` modified other than the auto-regenerated `backend/api/` bindings.
5. [ ] `AGENTS.md` and `CLAUDE.md` untouched.
6. [ ] Skills fetched BEFORE coding — especially `stable-memory` for the 50 GB blob storage upgrade-safety question.
7. [ ] Total diff is reasonable (~700-900 LOC). If significantly larger, you've over-engineered something — pause and ask.
8. [ ] Pushed to `origin/main` after Abdul's explicit approval.

Then report back to Cowork: files changed, line counts, smoke test output summary, **any decisions made that weren't in this spec** (especially anything around the SHA library choice, chunk-slicing approach, or storage upgrade behavior we'll review in Cowork before moving to L3 / L4).

---

*This spec is locked. If you find a real ambiguity, stop and ask Abdul. Don't improvise.*
