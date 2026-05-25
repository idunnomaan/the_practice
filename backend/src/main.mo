import Principal "mo:core/Principal";
import Map "mo:core/pure/Map";
import MutMap "mo:core/Map";
import Nat "mo:core/Nat";
import Text "mo:core/Text";
import Time "mo:core/Time";
import Iter "mo:core/Iter";
import Result "mo:core/Result";
import Array "mo:core/Array";
import Blob "mo:core/Blob";
import VarArray "mo:core/VarArray";
import Sha256 "mo:sha2/Sha256";
import Types "./Types";
import Auth "./Auth";
import Audit "./Audit";
import ClientModule "./Client";
import MatterModule "./Matter";
import DocumentModule "./Document";
import Search "./Search";
import Export "./Export";
import Library "./Library";
import Cycles "mo:core/Cycles";
import TopUpRequest "./TopUpRequest";

shared(installer) persistent actor class ThePractice(
  masterControllerArg : Principal
) = this {

  type Role = Types.Role;
  type UserRecord = Types.UserRecord;
  type AuditEntry = Audit.AuditEntry;

  type Client = ClientModule.Client;
  type ClientType = ClientModule.ClientType;
  type ClientStatus = ClientModule.ClientStatus;
  type Matter = MatterModule.Matter;
  type MatterStatus = MatterModule.MatterStatus;
  type Document = DocumentModule.Document;
  type DocumentStatus = DocumentModule.DocumentStatus;
  type DocumentVersion = DocumentModule.DocumentVersion;
  type UploadSession = DocumentModule.UploadSession;

  // L4 types
  type ClientFilter = Search.ClientFilter;
  type MatterFilter = Search.MatterFilter;
  type DocumentFilter = Search.DocumentFilter;
  type DocumentSearchResult = Search.DocumentSearchResult;
  type MatterStatusCounts = Search.MatterStatusCounts;
  type ClientStatusCounts = Search.ClientStatusCounts;
  type DocumentStatusCounts = Search.DocumentStatusCounts;
  type ExportManifest = Export.ExportManifest;

  // Firm Library types (Phase 1.5)
  type LibraryItemStatus = Library.LibraryItemStatus;
  type Folder = Library.Folder;
  type LibraryItem = Library.LibraryItem;
  type LibraryVersion = Library.LibraryVersion;
  type LibraryUploadSession = Library.LibraryUploadSession;
  type FolderScope = Library.FolderScope;
  type LibraryFilter = Library.LibraryFilter;
  type LibraryItemSearchResult = Library.LibraryItemSearchResult;
  type FolderListing = Library.FolderListing;

  // Admin / Cycle Management types (Admin Settings spec)
  type TopUpRequestStatus = TopUpRequest.TopUpRequestStatus;
  type TopUpRequestRecord = TopUpRequest.TopUpRequest;

  // INV-1: anonymous principal cannot hold any identity — trap at install if anonymous
  assert not Principal.isAnonymous(masterControllerArg);

  // PERSISTENCE CONTRACT (L3)
  // Every let/var field on this actor persists across upgrades automatically.
  // Guaranteed by the `persistent actor` declaration + Enhanced Orthogonal
  // Persistence (EOP). EOP serialises the full actor heap including large
  // Blob values. No pre_upgrade/post_upgrade hooks needed or permitted —
  // a trapping hook permanently bricks the canister.
  // See PERSISTENCE.md. Upgrade proof: scripts/smoke.sh Steps 74–85.

  var masterController : Principal = masterControllerArg;
  var operationsPrincipal : ?Principal = null;
  // INV-2: master controller is always a registered Partner while installed
  var users = Map.add(
    Map.empty<Principal, UserRecord>(),
    Principal.compare,
    masterControllerArg,
    {
      role = #Partner;
      addedBy = installer.caller;
      addedAt = Time.now();
      suspended = false;
    }
  );

  // SEC-INV-9: auditLog is not exposed via any method other than readAuditEntries
  let auditLog = MutMap.empty<Nat, AuditEntry>();
  var nextAuditId : Nat = 1;

  // L2 state — mutable Maps; `let` binding never reassigned (Map mutates in-place)
  let clients = MutMap.empty<Nat, Client>();
  let matters = MutMap.empty<Nat, Matter>();
  // SEC-INV-8: monotonic IDs; strictly increment by 1 per successful create
  var nextClientId : Nat = 1;
  var nextMatterId : Nat = 1;

  // L2b state — `let` bindings (MutMap mutates in-place; binding never reassigned)
  let documents = MutMap.empty<Nat, Document>();
  let documentVersions = MutMap.empty<Nat, DocumentVersion>();
  let versionsByDocument = MutMap.empty<Nat, [Nat]>(); // docId → ordered list of versionIds
  let uploadSessions = MutMap.empty<Nat, UploadSession>();
  // SEC-INV-9: monotonic IDs, independent counters
  var nextDocumentId : Nat = 1;
  var nextVersionId : Nat = 1;
  var nextSessionId : Nat = 1;
  var totalStorageUsedBytes : Nat = 0;
  var storageBudgetBytes : Nat = DocumentModule.DEFAULT_STORAGE_BUDGET;

  // Firm Library state (Phase 1.5) — all `let` bindings persist via EOP (same as L2b).
  // Storage counters (totalStorageUsedBytes, storageBudgetBytes) are SHARED with L2b (Q8).
  let folders = MutMap.empty<Nat, Folder>();
  let libraryItems = MutMap.empty<Nat, LibraryItem>();
  let libraryVersions = MutMap.empty<Nat, LibraryVersion>();
  let libraryVersionsByItem = MutMap.empty<Nat, [Nat]>(); // itemId → ordered list of versionIds
  let libraryUploadSessions = MutMap.empty<Nat, LibraryUploadSession>(); // separate from uploadSessions (Q10)
  var nextFolderId : Nat = 1;
  var nextLibraryItemId : Nat = 1;
  var nextLibraryVersionId : Nat = 1;
  var nextLibrarySessionId : Nat = 1;

  // Admin / Cycle Management state — additive, no migration of existing state (EOP handles upgrade).
  let MIN_TOPUP_T_CYCLES : Nat = 1;
  let MAX_TOPUP_T_CYCLES : Nat = 100;
  let MAX_TOPUP_NOTE_LENGTH : Nat = 1024;
  let topUpRequests = MutMap.empty<Nat, TopUpRequestRecord>();
  var nextTopUpRequestId : Nat = 1;

  // ── Audit helpers ─────────────────────────────────────────────────────────
  // SEC-INV-1: auditOk and auditErr are the only write paths into auditLog (append-only).
  //            No delete, modify, or clear function exists.
  // SEC-INV-3: emission is atomic with the caller's state change — both commit in the
  //            same message or both are rolled back by a trap.

  func auditOk(caller : Principal, action : Text, target : ?Principal) {
    MutMap.add(auditLog, Nat.compare, nextAuditId, {
      id = nextAuditId;
      timestamp = Time.now(); // SEC-INV-7: caller-provided timestamps never accepted
      caller;
      action;
      target;
      outcome = #ok;
    });
    nextAuditId += 1; // SEC-INV-6: monotonically increasing — never decremented
  };

  func auditErr(caller : Principal, action : Text, target : ?Principal, reason : Text) {
    MutMap.add(auditLog, Nat.compare, nextAuditId, {
      id = nextAuditId;
      timestamp = Time.now(); // SEC-INV-7
      caller;
      action;
      target;
      outcome = #err(reason);
    });
    nextAuditId += 1; // SEC-INV-6
  };

  // INV-4: suspension blocks role checks for any role, even Partner.
  // Closes over actor-state `users`; not in Auth.mo to avoid exposing Map.Map.
  func requireRole(caller : Principal, minRole : Role) : Result.Result<(), Text> {
    switch (Map.get(users, Principal.compare, caller)) {
      case (?record) {
        if (record.suspended) return #err("not authorized");
        if (Auth.roleRank(record.role) < Auth.roleRank(minRole)) return #err("not authorized");
        #ok(())
      };
      case null { #err("not authorized") };
    };
  };

  // ── L2 private helpers ───────────────────────────────────────────────────

  // SEC-INV-4: FK check — client must exist and be #Active.
  func lookupClientActive(id : Nat) : Result.Result<Client, Text> {
    switch (MutMap.get(clients, Nat.compare, id)) {
      case null { #err("client " # Nat.toText(id) # " not found") };
      case (?c) {
        if (c.status == #Inactive) #err("client " # Nat.toText(id) # " is inactive")
        else #ok(c)
      };
    };
  };

  // SEC-INV-5: used by deactivateClient to count blocking matters.
  func countMattersByClientAndStatus(clientId : Nat, statuses : [MatterStatus]) : Nat {
    var count = 0;
    for ((_, m) in MutMap.entriesFrom(matters, Nat.compare, 0)) {
      if (m.clientId == clientId) {
        for (s in statuses.vals()) {
          if (m.status == s) { count += 1 };
        };
      };
    };
    count
  };

  // Validates that a Principal is a registered, non-suspended Partner.
  // Used by createMatter, updateMatter, assignPartnerToMatter.
  func verifyPartner(p : Principal) : Result.Result<(), Text> {
    switch (Map.get(users, Principal.compare, p)) {
      case null { #err("principal " # Principal.toText(p) # " is not a registered user") };
      case (?record) {
        if (record.suspended) return #err("user " # Principal.toText(p) # " is suspended");
        if (record.role != #Partner) return #err("user " # Principal.toText(p) # " does not have Partner role");
        #ok(())
      };
    };
  };

  // ── L2b private helpers ───────────────────────────────────────────────────

  // For UPLOADS: matter must exist and not be #Archived (SEC-INV-5)
  func lookupMatterActive(matterId : Nat) : Result.Result<Matter, Text> {
    switch (MutMap.get(matters, Nat.compare, matterId)) {
      case null { #err("matter " # Nat.toText(matterId) # " not found") };
      case (?m) {
        if (m.status == #Archived) #err("matter " # Nat.toText(matterId) # " is archived")
        else #ok(m)
      };
    };
  };

  // SEC-INV-12: document must exist and be #Active
  func lookupDocumentActive(docId : Nat) : Result.Result<Document, Text> {
    switch (MutMap.get(documents, Nat.compare, docId)) {
      case null { #err("document " # Nat.toText(docId) # " not found") };
      case (?doc) {
        if (doc.status == #Deleted) #err("document " # Nat.toText(docId) # " is deleted")
        else #ok(doc)
      };
    };
  };

  // SHA-256: sha2@0.1.14 used — mo:core 2.3.1 has no crypto module
  func computeSha256(data : Blob) : Blob {
    Sha256.fromBlob(#sha256, data)
  };

  // Appends versionId to versionsByDocument[docId]; initialises list if absent
  func appendVersionToDocument(docId : Nat, versionId : Nat) : () {
    let existing : [Nat] = switch (MutMap.get(versionsByDocument, Nat.compare, docId)) {
      case null [];
      case (?arr) arr;
    };
    MutMap.add(versionsByDocument, Nat.compare, docId, Array.concat<Nat>(existing, [versionId]));
  };

  // L4 helper — returns version with blob stripped to empty Blob.
  // Mirrors the L2b listVersions pattern; use getChunk for actual bytes.
  func stripBlobFromVersion(v : DocumentVersion) : DocumentVersion {
    { v with blob = "" }
  };

  // setStorageBudget is callable by master controller OR operations principal
  func requireOperationsOrMaster(caller : Principal) : Result.Result<(), Text> {
    if (caller == masterController) return #ok(());
    switch (operationsPrincipal) {
      case (?ops) { if (caller == ops) return #ok(()) };
      case null {};
    };
    #err("not authorized")
  };

  func requireOperationsPrincipal(caller : Principal) : Result.Result<(), Text> {
    switch operationsPrincipal {
      case (?ops) { if (caller == ops) return #ok(()) };
      case null {};
    };
    #err("only operations principal can fulfill")
  };

  // ── Init ─────────────────────────────────────────────────────────────────
  // Runs once at install after L1 state (users map) is populated.
  // SEC-INV-2: install event is itself audited — entry id = 1.
  auditOk(installer.caller, "install", ?masterControllerArg);

  // ── Queries ──────────────────────────────────────────────────────────────
  // SEC-INV-8: no canister_inspect_message boundary — all access checks are
  //            inside method bodies (inspect_message runs without consensus).

  public query ({ caller }) func whoAmI() : async Principal { caller };

  public query ({ caller }) func getMyRole() : async ?Role {
    switch (Map.get(users, Principal.compare, caller)) {
      case (?record) { if (record.suspended) null else ?record.role };
      case null null;
    };
  };

  public query func getMasterController() : async Principal { masterController };

  public query func getOperationsPrincipal() : async ?Principal { operationsPrincipal };

  public query ({ caller }) func getUserCount() : async Nat {
    switch (requireRole(caller, #Partner)) { case (#err(_)) assert false; case (#ok) {} };
    Map.size(users);
  };

  public query ({ caller }) func listUsers() : async [(Principal, UserRecord)] {
    switch (requireRole(caller, #Partner)) { case (#err(_)) assert false; case (#ok) {} };
    Iter.toArray(Map.entries(users));
  };

  // ── L2 Queries ───────────────────────────────────────────────────────────
  // SEC-INV-1: trap on anonymous (queries can't emit audit; trap is correct here).
  // SEC-INV-11: no canister_inspect_message boundary.
  // Read = any authenticated principal per Q9.

  public query ({ caller }) func getClient(id : Nat) : async ?Client {
    switch (Auth.requireAuthenticated(caller)) { case (#err(_)) assert false; case (#ok) {} };
    MutMap.get(clients, Nat.compare, id)
  };

  public query ({ caller }) func listClients(after : Nat, limit : Nat, includeInactive : Bool) : async [Client] {
    switch (Auth.requireAuthenticated(caller)) { case (#err(_)) assert false; case (#ok) {} };
    let cap = if (limit > 1000) 1000 else limit;
    let base = MutMap.entriesFrom(clients, Nat.compare, after + 1);
    let filtered = Iter.filter(base, func((_, c) : (Nat, Client)) : Bool {
      includeInactive or c.status != #Inactive
    });
    let taken = Iter.take(filtered, cap);
    Iter.toArray(Iter.map(taken, func((_, c) : (Nat, Client)) : Client { c }))
  };

  public query ({ caller }) func getMatter(id : Nat) : async ?Matter {
    switch (Auth.requireAuthenticated(caller)) { case (#err(_)) assert false; case (#ok) {} };
    MutMap.get(matters, Nat.compare, id)
  };

  public query ({ caller }) func listMatters(after : Nat, limit : Nat, statusFilter : ?MatterStatus) : async [Matter] {
    switch (Auth.requireAuthenticated(caller)) { case (#err(_)) assert false; case (#ok) {} };
    let cap = if (limit > 1000) 1000 else limit;
    let base = MutMap.entriesFrom(matters, Nat.compare, after + 1);
    let filtered = Iter.filter(base, func((_, m) : (Nat, Matter)) : Bool {
      switch (statusFilter) {
        case null true;
        case (?s) m.status == s;
      }
    });
    let taken = Iter.take(filtered, cap);
    Iter.toArray(Iter.map(taken, func((_, m) : (Nat, Matter)) : Matter { m }))
  };

  public query ({ caller }) func listMattersByClient(clientId : Nat, after : Nat, limit : Nat, statusFilter : ?MatterStatus) : async [Matter] {
    switch (Auth.requireAuthenticated(caller)) { case (#err(_)) assert false; case (#ok) {} };
    let cap = if (limit > 1000) 1000 else limit;
    let base = MutMap.entriesFrom(matters, Nat.compare, after + 1);
    let filtered = Iter.filter(base, func((_, m) : (Nat, Matter)) : Bool {
      if (m.clientId != clientId) return false;
      switch (statusFilter) {
        case null true;
        case (?s) m.status == s;
      }
    });
    let taken = Iter.take(filtered, cap);
    Iter.toArray(Iter.map(taken, func((_, m) : (Nat, Matter)) : Matter { m }))
  };

  public query ({ caller }) func getClientCount() : async Nat {
    switch (Auth.requireAuthenticated(caller)) { case (#err(_)) assert false; case (#ok) {} };
    MutMap.size(clients)
  };

  public query ({ caller }) func getMatterCount() : async Nat {
    switch (Auth.requireAuthenticated(caller)) { case (#err(_)) assert false; case (#ok) {} };
    MutMap.size(matters)
  };

  // ── L2b Queries ───────────────────────────────────────────────────────────
  // SEC-INV-1: trap on anonymous (queries cannot audit; trap is correct).
  // SEC-INV-13: no canister_inspect_message boundary.

  public query ({ caller }) func getDocument(id : Nat) : async ?Document {
    switch (Auth.requireAuthenticated(caller)) { case (#err(_)) assert false; case (#ok) {} };
    MutMap.get(documents, Nat.compare, id)
  };

  public query ({ caller }) func listDocumentsByMatter(
    matterId : Nat,
    after : Nat,
    limit : Nat,
    includeDeleted : Bool
  ) : async [Document] {
    switch (Auth.requireAuthenticated(caller)) { case (#err(_)) assert false; case (#ok) {} };
    let cap = if (limit > 1000) 1000 else limit;
    let base = MutMap.entriesFrom(documents, Nat.compare, after + 1);
    let filtered = Iter.filter(base, func((_, d) : (Nat, Document)) : Bool {
      if (d.matterId != matterId) return false;
      includeDeleted or d.status != #Deleted
    });
    let taken = Iter.take(filtered, cap);
    Iter.toArray(Iter.map(taken, func((_, d) : (Nat, Document)) : Document { d }))
  };

  // Returns full version including blob — for inspection only. Use prepareDocumentDownload + getChunk for downloads.
  public query ({ caller }) func getDocumentVersion(versionId : Nat) : async ?DocumentVersion {
    switch (Auth.requireAuthenticated(caller)) { case (#err(_)) assert false; case (#ok) {} };
    MutMap.get(documentVersions, Nat.compare, versionId)
  };

  // Returns all versions for a document. Blob fields are stripped to empty Blob to keep the query cheap;
  // actual bytes are retrieved via getChunk.
  public query ({ caller }) func listVersions(documentId : Nat) : async [DocumentVersion] {
    switch (Auth.requireAuthenticated(caller)) { case (#err(_)) assert false; case (#ok) {} };
    let vids : [Nat] = switch (MutMap.get(versionsByDocument, Nat.compare, documentId)) {
      case null [];
      case (?arr) arr;
    };
    Array.filterMap<Nat, DocumentVersion>(vids, func(vid) {
      switch (MutMap.get(documentVersions, Nat.compare, vid)) {
        case null null;
        case (?v) ?{ v with blob = "" }; // blob stripped — use getChunk for bytes
      };
    })
  };

  public query ({ caller }) func getDocumentCount() : async Nat {
    switch (Auth.requireAuthenticated(caller)) { case (#err(_)) assert false; case (#ok) {} };
    MutMap.size(documents)
  };

  public query ({ caller }) func getStorageUsed() : async Nat {
    switch (Auth.requireAuthenticated(caller)) { case (#err(_)) assert false; case (#ok) {} };
    totalStorageUsedBytes
  };

  public query ({ caller }) func getStorageBudget() : async Nat {
    switch (Auth.requireAuthenticated(caller)) { case (#err(_)) assert false; case (#ok) {} };
    storageBudgetBytes
  };

  // Q7: chunk reads are not audited per chunk — one audit entry per prepareDocumentDownload intent only.
  // SEC-INV-1: anonymous rejected; SEC-INV-2: role >= Staff required (trap on failure — query, can't audit).
  // SEC-INV-12: #Deleted documents not accessible — returns null.
  // SEC-INV-13: no canister_inspect_message boundary.
  public query ({ caller }) func getChunk(versionId : Nat, chunkIndex : Nat) : async ?Blob {
    switch (Auth.requireAuthenticated(caller)) { case (#err(_)) assert false; case (#ok) {} };
    switch (requireRole(caller, #Staff)) { case (#err(_)) assert false; case (#ok) {} };
    switch (MutMap.get(documentVersions, Nat.compare, versionId)) {
      case null null;
      case (?version) {
        switch (MutMap.get(documents, Nat.compare, version.documentId)) {
          case null null;
          case (?doc) {
            // SEC-INV-12: #Deleted documents not retrievable
            if (doc.status != #Active) return null;
            let count = DocumentModule.expectedChunkCount(version.sizeBytes);
            if (chunkIndex >= count) return null;
            let (startByte, endByte) = DocumentModule.chunkRange(chunkIndex, version.sizeBytes);
            // On-demand slice: iterate blob bytes without materialising full [Nat8] array
            let chunkSize = endByte - startByte;
            let result = VarArray.repeat<Nat8>(0, chunkSize);
            var bytePos : Nat = 0;
            var writePos : Nat = 0;
            label sliceLoop for (b in version.blob.values()) {
              if (bytePos >= endByte) break sliceLoop;
              if (bytePos >= startByte) {
                result[writePos] := b;
                writePos += 1;
              };
              bytePos += 1;
            };
            ?Blob.fromVarArray(result)
          };
        };
      };
    };
  };

  // ── Updates ──────────────────────────────────────────────────────────────
  // Every update: (1) reject anonymous, (2) role/controller check, (3) audit before return.
  // SEC-INV-2: every mutator below emits exactly one entry — auditOk on success,
  //            auditErr on any auth failure — before returning.

  public shared ({ caller }) func grantOperations(p : Principal) : async Result.Result<(), Text> {
    switch (Auth.requireAuthenticated(caller)) { case (#err(e)) { auditErr(caller, "grantOperations", ?p, e); return #err(e) }; case (#ok) {} };
    switch (Auth.requireMasterController(caller, masterController)) { case (#err(e)) { auditErr(caller, "grantOperations", ?p, e); return #err(e) }; case (#ok) {} };
    assert not Principal.isAnonymous(p);            // INV-1
    assert p != masterController;
    assert Map.get(users, Principal.compare, p) == null; // INV-3: ops never in users registry
    assert operationsPrincipal == null;             // must revoke first
    operationsPrincipal := ?p;
    auditOk(caller, "grantOperations", ?p);
    #ok(())
  };

  public shared ({ caller }) func revokeOperations() : async Result.Result<(), Text> {
    switch (Auth.requireAuthenticated(caller)) { case (#err(e)) { auditErr(caller, "revokeOperations", null, e); return #err(e) }; case (#ok) {} };
    switch (Auth.requireMasterController(caller, masterController)) { case (#err(e)) { auditErr(caller, "revokeOperations", null, e); return #err(e) }; case (#ok) {} };
    operationsPrincipal := null; // idempotent
    auditOk(caller, "revokeOperations", null);
    #ok(())
  };

  public shared ({ caller }) func transferMasterController(p : Principal) : async Result.Result<(), Text> {
    switch (Auth.requireAuthenticated(caller)) { case (#err(e)) { auditErr(caller, "transferMasterController", ?p, e); return #err(e) }; case (#ok) {} };
    switch (Auth.requireMasterController(caller, masterController)) { case (#err(e)) { auditErr(caller, "transferMasterController", ?p, e); return #err(e) }; case (#ok) {} };
    assert not Principal.isAnonymous(p);            // INV-1
    switch operationsPrincipal {
      case (?ops) { assert p != ops };
      case null {};
    };
    // p must already be a registered Partner
    switch (Map.get(users, Principal.compare, p)) {
      case (?record) { assert record.role == #Partner };
      case null { assert false };
    };
    masterController := p;
    // INV-2: old master controller stays as Partner — no removal here
    auditOk(caller, "transferMasterController", ?p);
    #ok(())
  };

  public shared ({ caller }) func addUser(p : Principal, role : Role) : async Result.Result<(), Text> {
    switch (Auth.requireAuthenticated(caller)) { case (#err(e)) { auditErr(caller, "addUser", ?p, e); return #err(e) }; case (#ok) {} };
    switch (requireRole(caller, #Partner)) { case (#err(e)) { auditErr(caller, "addUser", ?p, e); return #err(e) }; case (#ok) {} };
    assert not Principal.isAnonymous(p);            // INV-1
    assert Map.get(users, Principal.compare, p) == null; // cannot already be registered
    switch operationsPrincipal {
      case (?ops) { assert p != ops };              // INV-3: ops never in users registry
      case null {};
    };
    users := Map.add(users, Principal.compare, p, {
      role = role;
      addedBy = caller;
      addedAt = Time.now();
      suspended = false;
    });
    auditOk(caller, "addUser", ?p);
    #ok(())
  };

  public shared ({ caller }) func setUserRole(p : Principal, role : Role) : async Result.Result<(), Text> {
    switch (Auth.requireAuthenticated(caller)) { case (#err(e)) { auditErr(caller, "setUserRole", ?p, e); return #err(e) }; case (#ok) {} };
    switch (requireRole(caller, #Partner)) { case (#err(e)) { auditErr(caller, "setUserRole", ?p, e); return #err(e) }; case (#ok) {} };
    assert p != masterController;                   // INV-5: must transferMasterController first
    switch (Map.get(users, Principal.compare, p)) {
      case (?record) {
        users := Map.add(users, Principal.compare, p, {
          role = role;
          addedBy = record.addedBy;
          addedAt = record.addedAt;
          suspended = record.suspended;
        });
      };
      case null { assert false };                   // user not found
    };
    auditOk(caller, "setUserRole", ?p);
    #ok(())
  };

  public shared ({ caller }) func suspendUser(p : Principal) : async Result.Result<(), Text> {
    switch (Auth.requireAuthenticated(caller)) { case (#err(e)) { auditErr(caller, "suspendUser", ?p, e); return #err(e) }; case (#ok) {} };
    switch (requireRole(caller, #Partner)) { case (#err(e)) { auditErr(caller, "suspendUser", ?p, e); return #err(e) }; case (#ok) {} };
    assert p != masterController;                   // cannot suspend the master controller
    switch (Map.get(users, Principal.compare, p)) {
      case (?record) {
        users := Map.add(users, Principal.compare, p, {
          role = record.role;
          addedBy = record.addedBy;
          addedAt = record.addedAt;
          suspended = true;
        });
      };
      case null { assert false };                   // user not found
    };
    auditOk(caller, "suspendUser", ?p);
    #ok(())
  };

  public shared ({ caller }) func unsuspendUser(p : Principal) : async Result.Result<(), Text> {
    switch (Auth.requireAuthenticated(caller)) { case (#err(e)) { auditErr(caller, "unsuspendUser", ?p, e); return #err(e) }; case (#ok) {} };
    switch (requireRole(caller, #Partner)) { case (#err(e)) { auditErr(caller, "unsuspendUser", ?p, e); return #err(e) }; case (#ok) {} };
    switch (Map.get(users, Principal.compare, p)) {
      case (?record) {
        users := Map.add(users, Principal.compare, p, {
          role = record.role;
          addedBy = record.addedBy;
          addedAt = record.addedAt;
          suspended = false;
        });
      };
      case null { assert false };                   // user not found
    };
    auditOk(caller, "unsuspendUser", ?p);
    #ok(())
  };

  public shared ({ caller }) func removeUser(p : Principal) : async Result.Result<(), Text> {
    switch (Auth.requireAuthenticated(caller)) { case (#err(e)) { auditErr(caller, "removeUser", ?p, e); return #err(e) }; case (#ok) {} };
    switch (requireRole(caller, #Partner)) { case (#err(e)) { auditErr(caller, "removeUser", ?p, e); return #err(e) }; case (#ok) {} };
    assert p != masterController;                   // cannot remove master controller (must transfer first)
    users := Map.remove(users, Principal.compare, p);
    auditOk(caller, "removeUser", ?p);
    #ok(())
  };

  // ── L2 Updates — Client lifecycle ────────────────────────────────────────
  // SEC-INV-1: anonymous rejected at every entry point.
  // SEC-INV-2: only #Partner role can mutate.
  // SEC-INV-3: no hard delete; soft-delete via deactivateClient only.
  // SEC-INV-10: every mutator emits exactly one audit entry.
  // SEC-INV-11: no canister_inspect_message boundary.

  public shared ({ caller }) func createClient(
    name : Text,
    clientType : ClientType,
    primaryEmail : ?Text,
    primaryPhone : ?Text,
    identifier : ?Text,
    notes : Text
  ) : async Result.Result<Nat, Text> {
    // SEC-INV-1
    switch (Auth.requireAuthenticated(caller)) {
      case (#err(e)) { auditErr(caller, "createClient", null, e); return #err(e) };
      case (#ok) {};
    };
    // SEC-INV-2
    switch (requireRole(caller, #Partner)) {
      case (#err(e)) { auditErr(caller, "createClient", null, e); return #err(e) };
      case (#ok) {};
    };
    let trimmedName = Text.trim(name, #predicate(func(c : Char) : Bool {
      c == ' ' or c == '\t' or c == '\n' or c == '\r'
    }));
    if (trimmedName == "") {
      let e = "name must not be blank";
      auditErr(caller, "createClient", null, e);
      return #err(e);
    };
    let id = nextClientId;
    nextClientId += 1; // SEC-INV-8: monotonic
    let now = Time.now(); // SEC-INV-9: timestamps from Time.now() only
    MutMap.add(clients, Nat.compare, id, {
      id;
      name = trimmedName;
      clientType;
      primaryEmail;
      primaryPhone;
      identifier;
      notes;
      status = #Active;
      createdAt = now;
      createdBy = caller;
      lastModifiedAt = now;
      lastModifiedBy = caller;
    });
    auditOk(caller, "createClient", null);
    #ok(id)
  };

  public shared ({ caller }) func updateClient(
    id : Nat,
    name : ?Text,
    clientType : ?ClientType,
    primaryEmail : ?Text,
    primaryPhone : ?Text,
    identifier : ?Text,
    notes : ?Text
  ) : async Result.Result<(), Text> {
    switch (Auth.requireAuthenticated(caller)) {
      case (#err(e)) { auditErr(caller, "updateClient", null, e); return #err(e) };
      case (#ok) {};
    };
    switch (requireRole(caller, #Partner)) {
      case (#err(e)) { auditErr(caller, "updateClient", null, e); return #err(e) };
      case (#ok) {};
    };
    switch (MutMap.get(clients, Nat.compare, id)) {
      case null {
        let e = "client " # Nat.toText(id) # " not found";
        auditErr(caller, "updateClient", null, e);
        return #err(e);
      };
      case (?existing) {
        if (existing.status == #Inactive) {
          let e = "client " # Nat.toText(id) # " is inactive";
          auditErr(caller, "updateClient", null, e);
          return #err(e);
        };
        // Sparse update — validate name if provided
        let newName = switch (name) {
          case null existing.name;
          case (?v) {
            let t = Text.trim(v, #predicate(func(c : Char) : Bool {
              c == ' ' or c == '\t' or c == '\n' or c == '\r'
            }));
            if (t == "") {
              let e = "name must not be blank";
              auditErr(caller, "updateClient", null, e);
              return #err(e);
            };
            t
          };
        };
        // SEC-INV-9: lastModifiedAt from Time.now()
        MutMap.add(clients, Nat.compare, id, {
          existing with
          name = newName;
          clientType = switch (clientType) { case null existing.clientType; case (?v) v };
          primaryEmail = switch (primaryEmail) { case null existing.primaryEmail; case (?v) ?v };
          primaryPhone = switch (primaryPhone) { case null existing.primaryPhone; case (?v) ?v };
          identifier = switch (identifier) { case null existing.identifier; case (?v) ?v };
          notes = switch (notes) { case null existing.notes; case (?v) v };
          lastModifiedAt = Time.now();
          lastModifiedBy = caller;
        });
      };
    };
    auditOk(caller, "updateClient", null);
    #ok(())
  };

  public shared ({ caller }) func deactivateClient(id : Nat) : async Result.Result<(), Text> {
    switch (Auth.requireAuthenticated(caller)) {
      case (#err(e)) { auditErr(caller, "deactivateClient", null, e); return #err(e) };
      case (#ok) {};
    };
    switch (requireRole(caller, #Partner)) {
      case (#err(e)) { auditErr(caller, "deactivateClient", null, e); return #err(e) };
      case (#ok) {};
    };
    switch (MutMap.get(clients, Nat.compare, id)) {
      case null {
        let e = "client " # Nat.toText(id) # " not found";
        auditErr(caller, "deactivateClient", null, e);
        return #err(e);
      };
      case (?existing) {
        if (existing.status == #Inactive) {
          let e = "client " # Nat.toText(id) # " is already inactive";
          auditErr(caller, "deactivateClient", null, e);
          return #err(e);
        };
        // SEC-INV-5: reject if client has open or on-hold matters
        let blocking = countMattersByClientAndStatus(id, [#Open, #OnHold]);
        if (blocking > 0) {
          let e = "client " # Nat.toText(id) # " has " # Nat.toText(blocking) # " open matter(s); close or archive them first";
          auditErr(caller, "deactivateClient", null, e);
          return #err(e);
        };
        MutMap.add(clients, Nat.compare, id, {
          existing with
          status = #Inactive;
          lastModifiedAt = Time.now();
          lastModifiedBy = caller;
        });
      };
    };
    auditOk(caller, "deactivateClient", null);
    #ok(())
  };

  public shared ({ caller }) func reactivateClient(id : Nat) : async Result.Result<(), Text> {
    switch (Auth.requireAuthenticated(caller)) {
      case (#err(e)) { auditErr(caller, "reactivateClient", null, e); return #err(e) };
      case (#ok) {};
    };
    switch (requireRole(caller, #Partner)) {
      case (#err(e)) { auditErr(caller, "reactivateClient", null, e); return #err(e) };
      case (#ok) {};
    };
    switch (MutMap.get(clients, Nat.compare, id)) {
      case null {
        let e = "client " # Nat.toText(id) # " not found";
        auditErr(caller, "reactivateClient", null, e);
        return #err(e);
      };
      case (?existing) {
        if (existing.status == #Active) {
          let e = "client " # Nat.toText(id) # " is already active";
          auditErr(caller, "reactivateClient", null, e);
          return #err(e);
        };
        MutMap.add(clients, Nat.compare, id, {
          existing with
          status = #Active;
          lastModifiedAt = Time.now();
          lastModifiedBy = caller;
        });
      };
    };
    auditOk(caller, "reactivateClient", null);
    #ok(())
  };

  // ── L2 Updates — Matter lifecycle ────────────────────────────────────────
  // SEC-INV-6: every transition method validates from-status; invalid → #err + auditErr.
  // SEC-INV-7: #Archived matters are immutable; all methods reject when status = #Archived.

  public shared ({ caller }) func createMatter(
    title : Text,
    matterType : Text,
    clientId : Nat,
    assignedPartner : ?Principal,
    description : Text
  ) : async Result.Result<Nat, Text> {
    switch (Auth.requireAuthenticated(caller)) {
      case (#err(e)) { auditErr(caller, "createMatter", null, e); return #err(e) };
      case (#ok) {};
    };
    switch (requireRole(caller, #Partner)) {
      case (#err(e)) { auditErr(caller, "createMatter", null, e); return #err(e) };
      case (#ok) {};
    };
    let trimmedTitle = Text.trim(title, #predicate(func(c : Char) : Bool {
      c == ' ' or c == '\t' or c == '\n' or c == '\r'
    }));
    if (trimmedTitle == "") {
      let e = "title must not be blank";
      auditErr(caller, "createMatter", null, e);
      return #err(e);
    };
    // SEC-INV-4: FK enforcement — client must exist and be #Active
    switch (lookupClientActive(clientId)) {
      case (#err(e)) { auditErr(caller, "createMatter", null, e); return #err(e) };
      case (#ok(_)) {};
    };
    // Verify assignedPartner if provided
    switch (assignedPartner) {
      case null {};
      case (?p) {
        switch (verifyPartner(p)) {
          case (#err(e)) { auditErr(caller, "createMatter", null, e); return #err(e) };
          case (#ok) {};
        };
      };
    };
    let id = nextMatterId;
    nextMatterId += 1; // SEC-INV-8: monotonic
    let now = Time.now(); // SEC-INV-9
    MutMap.add(matters, Nat.compare, id, {
      id;
      title = trimmedTitle;
      matterType;
      clientId;
      assignedPartner;
      description;
      status = #Open;
      openedAt = now;
      closedAt = null;
      createdAt = now;
      createdBy = caller;
      lastModifiedAt = now;
      lastModifiedBy = caller;
    });
    auditOk(caller, "createMatter", null);
    #ok(id)
  };

  public shared ({ caller }) func updateMatter(
    id : Nat,
    title : ?Text,
    matterType : ?Text,
    clientId : ?Nat,
    assignedPartner : ?(?Principal),
    description : ?Text
  ) : async Result.Result<(), Text> {
    switch (Auth.requireAuthenticated(caller)) {
      case (#err(e)) { auditErr(caller, "updateMatter", null, e); return #err(e) };
      case (#ok) {};
    };
    switch (requireRole(caller, #Partner)) {
      case (#err(e)) { auditErr(caller, "updateMatter", null, e); return #err(e) };
      case (#ok) {};
    };
    switch (MutMap.get(matters, Nat.compare, id)) {
      case null {
        let e = "matter " # Nat.toText(id) # " not found";
        auditErr(caller, "updateMatter", null, e);
        return #err(e);
      };
      case (?existing) {
        // SEC-INV-7: archived matters are immutable
        if (existing.status == #Archived) {
          let e = "matter " # Nat.toText(id) # " is archived";
          auditErr(caller, "updateMatter", null, e);
          return #err(e);
        };
        // SEC-INV-4: FK re-check if clientId is changing
        let newClientId = switch (clientId) {
          case null existing.clientId;
          case (?cid) {
            switch (lookupClientActive(cid)) {
              case (#err(e)) { auditErr(caller, "updateMatter", null, e); return #err(e) };
              case (#ok(_)) cid;
            };
          };
        };
        // Validate title if provided
        let newTitle = switch (title) {
          case null existing.title;
          case (?t) {
            let trimmed = Text.trim(t, #predicate(func(c : Char) : Bool {
              c == ' ' or c == '\t' or c == '\n' or c == '\r'
            }));
            if (trimmed == "") {
              let e = "title must not be blank";
              auditErr(caller, "updateMatter", null, e);
              return #err(e);
            };
            trimmed
          };
        };
        // assignedPartner: ?(?Principal) — outer ? = "is this field being updated?"
        let newAssignedPartner = switch (assignedPartner) {
          case null existing.assignedPartner; // field not being updated
          case (?newVal) {
            // field is being updated; verify if non-null
            switch (newVal) {
              case null null; // unassign
              case (?p) {
                switch (verifyPartner(p)) {
                  case (#err(e)) { auditErr(caller, "updateMatter", null, e); return #err(e) };
                  case (#ok) ?p;
                };
              };
            };
          };
        };
        MutMap.add(matters, Nat.compare, id, {
          existing with
          title = newTitle;
          matterType = switch (matterType) { case null existing.matterType; case (?v) v };
          clientId = newClientId;
          assignedPartner = newAssignedPartner;
          description = switch (description) { case null existing.description; case (?v) v };
          lastModifiedAt = Time.now();
          lastModifiedBy = caller;
        });
      };
    };
    auditOk(caller, "updateMatter", null);
    #ok(())
  };

  public shared ({ caller }) func closeMatter(id : Nat) : async Result.Result<(), Text> {
    switch (Auth.requireAuthenticated(caller)) {
      case (#err(e)) { auditErr(caller, "closeMatter", null, e); return #err(e) };
      case (#ok) {};
    };
    switch (requireRole(caller, #Partner)) {
      case (#err(e)) { auditErr(caller, "closeMatter", null, e); return #err(e) };
      case (#ok) {};
    };
    switch (MutMap.get(matters, Nat.compare, id)) {
      case null {
        let e = "matter " # Nat.toText(id) # " not found";
        auditErr(caller, "closeMatter", null, e);
        return #err(e);
      };
      case (?existing) {
        // SEC-INV-6: validate transition
        if (not MatterModule.isValidMatterTransition(existing.status, #Closed)) {
          let e = "invalid status transition: " # MatterModule.statusText(existing.status) # " \u{2192} Closed";
          auditErr(caller, "closeMatter", null, e);
          return #err(e);
        };
        MutMap.add(matters, Nat.compare, id, {
          existing with
          status = #Closed;
          closedAt = ?Time.now(); // SEC-INV-9
          lastModifiedAt = Time.now();
          lastModifiedBy = caller;
        });
      };
    };
    auditOk(caller, "closeMatter", null);
    #ok(())
  };

  public shared ({ caller }) func reopenMatter(id : Nat) : async Result.Result<(), Text> {
    switch (Auth.requireAuthenticated(caller)) {
      case (#err(e)) { auditErr(caller, "reopenMatter", null, e); return #err(e) };
      case (#ok) {};
    };
    switch (requireRole(caller, #Partner)) {
      case (#err(e)) { auditErr(caller, "reopenMatter", null, e); return #err(e) };
      case (#ok) {};
    };
    switch (MutMap.get(matters, Nat.compare, id)) {
      case null {
        let e = "matter " # Nat.toText(id) # " not found";
        auditErr(caller, "reopenMatter", null, e);
        return #err(e);
      };
      case (?existing) {
        // SEC-INV-6 + SEC-INV-7: cannot reopen #Archived
        if (not MatterModule.isValidMatterTransition(existing.status, #Open)) {
          let e = "invalid status transition: " # MatterModule.statusText(existing.status) # " \u{2192} Open";
          auditErr(caller, "reopenMatter", null, e);
          return #err(e);
        };
        MutMap.add(matters, Nat.compare, id, {
          existing with
          status = #Open;
          closedAt = null;
          lastModifiedAt = Time.now();
          lastModifiedBy = caller;
        });
      };
    };
    auditOk(caller, "reopenMatter", null);
    #ok(())
  };

  public shared ({ caller }) func putMatterOnHold(id : Nat) : async Result.Result<(), Text> {
    switch (Auth.requireAuthenticated(caller)) {
      case (#err(e)) { auditErr(caller, "putMatterOnHold", null, e); return #err(e) };
      case (#ok) {};
    };
    switch (requireRole(caller, #Partner)) {
      case (#err(e)) { auditErr(caller, "putMatterOnHold", null, e); return #err(e) };
      case (#ok) {};
    };
    switch (MutMap.get(matters, Nat.compare, id)) {
      case null {
        let e = "matter " # Nat.toText(id) # " not found";
        auditErr(caller, "putMatterOnHold", null, e);
        return #err(e);
      };
      case (?existing) {
        // SEC-INV-6
        if (not MatterModule.isValidMatterTransition(existing.status, #OnHold)) {
          let e = "invalid status transition: " # MatterModule.statusText(existing.status) # " \u{2192} OnHold";
          auditErr(caller, "putMatterOnHold", null, e);
          return #err(e);
        };
        MutMap.add(matters, Nat.compare, id, {
          existing with
          status = #OnHold;
          lastModifiedAt = Time.now();
          lastModifiedBy = caller;
        });
      };
    };
    auditOk(caller, "putMatterOnHold", null);
    #ok(())
  };

  public shared ({ caller }) func resumeMatter(id : Nat) : async Result.Result<(), Text> {
    switch (Auth.requireAuthenticated(caller)) {
      case (#err(e)) { auditErr(caller, "resumeMatter", null, e); return #err(e) };
      case (#ok) {};
    };
    switch (requireRole(caller, #Partner)) {
      case (#err(e)) { auditErr(caller, "resumeMatter", null, e); return #err(e) };
      case (#ok) {};
    };
    switch (MutMap.get(matters, Nat.compare, id)) {
      case null {
        let e = "matter " # Nat.toText(id) # " not found";
        auditErr(caller, "resumeMatter", null, e);
        return #err(e);
      };
      case (?existing) {
        // SEC-INV-6
        if (not MatterModule.isValidMatterTransition(existing.status, #Open)) {
          let e = "invalid status transition: " # MatterModule.statusText(existing.status) # " \u{2192} Open";
          auditErr(caller, "resumeMatter", null, e);
          return #err(e);
        };
        MutMap.add(matters, Nat.compare, id, {
          existing with
          status = #Open;
          lastModifiedAt = Time.now();
          lastModifiedBy = caller;
        });
      };
    };
    auditOk(caller, "resumeMatter", null);
    #ok(())
  };

  public shared ({ caller }) func archiveMatter(id : Nat) : async Result.Result<(), Text> {
    switch (Auth.requireAuthenticated(caller)) {
      case (#err(e)) { auditErr(caller, "archiveMatter", null, e); return #err(e) };
      case (#ok) {};
    };
    switch (requireRole(caller, #Partner)) {
      case (#err(e)) { auditErr(caller, "archiveMatter", null, e); return #err(e) };
      case (#ok) {};
    };
    switch (MutMap.get(matters, Nat.compare, id)) {
      case null {
        let e = "matter " # Nat.toText(id) # " not found";
        auditErr(caller, "archiveMatter", null, e);
        return #err(e);
      };
      case (?existing) {
        // SEC-INV-6 + SEC-INV-7
        if (not MatterModule.isValidMatterTransition(existing.status, #Archived)) {
          let e = "invalid status transition: " # MatterModule.statusText(existing.status) # " \u{2192} Archived";
          auditErr(caller, "archiveMatter", null, e);
          return #err(e);
        };
        MutMap.add(matters, Nat.compare, id, {
          existing with
          status = #Archived;
          lastModifiedAt = Time.now();
          lastModifiedBy = caller;
        });
      };
    };
    auditOk(caller, "archiveMatter", null);
    #ok(())
  };

  public shared ({ caller }) func assignPartnerToMatter(id : Nat, partner : ?Principal) : async Result.Result<(), Text> {
    switch (Auth.requireAuthenticated(caller)) {
      case (#err(e)) { auditErr(caller, "assignPartnerToMatter", null, e); return #err(e) };
      case (#ok) {};
    };
    switch (requireRole(caller, #Partner)) {
      case (#err(e)) { auditErr(caller, "assignPartnerToMatter", null, e); return #err(e) };
      case (#ok) {};
    };
    switch (MutMap.get(matters, Nat.compare, id)) {
      case null {
        let e = "matter " # Nat.toText(id) # " not found";
        auditErr(caller, "assignPartnerToMatter", null, e);
        return #err(e);
      };
      case (?existing) {
        // SEC-INV-7: archived matters are immutable
        if (existing.status == #Archived) {
          let e = "matter " # Nat.toText(id) # " is archived";
          auditErr(caller, "assignPartnerToMatter", null, e);
          return #err(e);
        };
        switch (partner) {
          case null {};
          case (?p) {
            switch (verifyPartner(p)) {
              case (#err(e)) { auditErr(caller, "assignPartnerToMatter", null, e); return #err(e) };
              case (#ok) {};
            };
          };
        };
        MutMap.add(matters, Nat.compare, id, {
          existing with
          assignedPartner = partner;
          lastModifiedAt = Time.now();
          lastModifiedBy = caller;
        });
      };
    };
    auditOk(caller, "assignPartnerToMatter", null);
    #ok(())
  };

  // ── L2b Upload updates ────────────────────────────────────────────────────
  // SEC-INV-1: anonymous rejected; SEC-INV-2: role >= Associate.
  // SEC-INV-11: every method emits exactly one audit entry.

  public shared ({ caller }) func startUpload(
    matterId : Nat,
    filename : Text,
    contentType : Text,
    totalSizeBytes : Nat,
    uploadNotes : Text,
    replacesDocumentId : ?Nat
  ) : async Result.Result<Nat, Text> {
    // SEC-INV-1
    switch (Auth.requireAuthenticated(caller)) {
      case (#err(e)) { auditErr(caller, "startUpload", null, e); return #err(e) };
      case (#ok) {};
    };
    // SEC-INV-2: Associate or higher
    switch (requireRole(caller, #Associate)) {
      case (#err(e)) { auditErr(caller, "startUpload", null, e); return #err(e) };
      case (#ok) {};
    };
    // SEC-INV-7: file size limit (also reject 0-byte files)
    if (totalSizeBytes == 0) {
      let e = "totalSizeBytes must be > 0";
      auditErr(caller, "startUpload", null, e);
      return #err(e);
    };
    if (totalSizeBytes > DocumentModule.MAX_FILE_SIZE) {
      let e = "file too large: " # Nat.toText(totalSizeBytes) # " bytes exceeds limit of " # Nat.toText(DocumentModule.MAX_FILE_SIZE);
      auditErr(caller, "startUpload", null, e);
      return #err(e);
    };
    // SEC-INV-6: content type whitelist enforced at startUpload
    if (not DocumentModule.isAllowedContentType(contentType)) {
      let e = "content type not allowed: " # contentType;
      auditErr(caller, "startUpload", null, e);
      return #err(e);
    };
    // SEC-INV-8: storage budget enforced at startUpload
    if (totalStorageUsedBytes + totalSizeBytes > storageBudgetBytes) {
      let available = if (storageBudgetBytes >= totalStorageUsedBytes) storageBudgetBytes - totalStorageUsedBytes else 0;
      let e = "storage budget exceeded: would need " # Nat.toText(totalSizeBytes) # " bytes, only " # Nat.toText(available) # " available";
      auditErr(caller, "startUpload", null, e);
      return #err(e);
    };
    // SEC-INV-5: FK — matter must exist and not be #Archived
    switch (lookupMatterActive(matterId)) {
      case (#err(e)) { auditErr(caller, "startUpload", null, e); return #err(e) };
      case (#ok(_)) {};
    };
    // SEC-INV-5: replacesDocumentId FK validation
    switch (replacesDocumentId) {
      case null {};
      case (?replaceId) {
        switch (lookupDocumentActive(replaceId)) {
          case (#err(e)) { auditErr(caller, "startUpload", null, e); return #err(e) };
          case (#ok(doc)) {
            if (doc.matterId != matterId) {
              let e = "document " # Nat.toText(replaceId) # " does not belong to matter " # Nat.toText(matterId);
              auditErr(caller, "startUpload", null, e);
              return #err(e);
            };
          };
        };
      };
    };
    // SEC-INV-9: monotonic session ID
    let sessionId = nextSessionId;
    nextSessionId += 1;
    MutMap.add(uploadSessions, Nat.compare, sessionId, {
      sessionId;
      matterId;
      filename;
      contentType;
      totalSizeBytes;
      expectedChunkCount = DocumentModule.expectedChunkCount(totalSizeBytes);
      uploadNotes;
      replacesDocumentId;
      chunks = Map.empty<Nat, Blob>();  // pure Map — updated by replacing session record
      startedAt = Time.now();
      startedBy = caller; // SEC-INV-3: caller-locked
    });
    auditOk(caller, "startUpload", null);
    #ok(sessionId)
  };

  public shared ({ caller }) func appendChunk(
    sessionId : Nat,
    chunkIndex : Nat,
    chunkBytes : Blob
  ) : async Result.Result<(), Text> {
    // SEC-INV-1
    switch (Auth.requireAuthenticated(caller)) {
      case (#err(e)) { auditErr(caller, "appendChunk", null, e); return #err(e) };
      case (#ok) {};
    };
    // SEC-INV-2
    switch (requireRole(caller, #Associate)) {
      case (#err(e)) { auditErr(caller, "appendChunk", null, e); return #err(e) };
      case (#ok) {};
    };
    let session = switch (MutMap.get(uploadSessions, Nat.compare, sessionId)) {
      case null {
        let e = "session " # Nat.toText(sessionId) # " not found";
        auditErr(caller, "appendChunk", null, e);
        return #err(e);
      };
      case (?s) s;
    };
    // SEC-INV-3: caller-lock
    if (session.startedBy != caller) {
      let e = "not the session owner";
      auditErr(caller, "appendChunk", null, e);
      return #err(e);
    };
    if (chunkIndex >= session.expectedChunkCount) {
      let e = "chunk index " # Nat.toText(chunkIndex) # " out of range (expected " # Nat.toText(session.expectedChunkCount) # " chunks)";
      auditErr(caller, "appendChunk", null, e);
      return #err(e);
    };
    // Validate chunk size: non-last chunks must be exactly CHUNK_SIZE
    let isLastChunk = chunkIndex == session.expectedChunkCount - 1;
    let expectedSize = if (isLastChunk) {
      session.totalSizeBytes - chunkIndex * DocumentModule.CHUNK_SIZE
    } else {
      DocumentModule.CHUNK_SIZE
    };
    if (chunkBytes.size() != expectedSize) {
      let e = "chunk " # Nat.toText(chunkIndex) # " wrong size: expected " # Nat.toText(expectedSize) # ", got " # Nat.toText(chunkBytes.size());
      auditErr(caller, "appendChunk", null, e);
      return #err(e);
    };
    // Idempotent: last write wins for the same chunkIndex
    let newChunks = Map.add(session.chunks, Nat.compare, chunkIndex, chunkBytes);
    MutMap.add(uploadSessions, Nat.compare, sessionId, { session with chunks = newChunks });
    auditOk(caller, "appendChunk", null);
    #ok(())
  };

  public shared ({ caller }) func finalizeUpload(
    sessionId : Nat
  ) : async Result.Result<{ documentId : Nat; versionId : Nat; sha256 : Blob }, Text> {
    // SEC-INV-1
    switch (Auth.requireAuthenticated(caller)) {
      case (#err(e)) { auditErr(caller, "documentUpload:0", null, e); return #err(e) };
      case (#ok) {};
    };
    // SEC-INV-2
    switch (requireRole(caller, #Associate)) {
      case (#err(e)) { auditErr(caller, "documentUpload:0", null, e); return #err(e) };
      case (#ok) {};
    };
    let session = switch (MutMap.get(uploadSessions, Nat.compare, sessionId)) {
      case null {
        let e = "session " # Nat.toText(sessionId) # " not found";
        auditErr(caller, "documentUpload:0", null, e);
        return #err(e);
      };
      case (?s) s;
    };
    // SEC-INV-3: caller-lock
    if (session.startedBy != caller) {
      let e = "not the session owner";
      auditErr(caller, "documentUpload:0", null, e);
      return #err(e);
    };
    // Validate chunk completeness: size check then index-by-index verification
    if (Map.size(session.chunks) != session.expectedChunkCount) {
      let e = "upload incomplete: expected " # Nat.toText(session.expectedChunkCount) # " chunks, have " # Nat.toText(Map.size(session.chunks));
      auditErr(caller, "documentUpload:0", null, e);
      return #err(e);
    };
    var ci : Nat = 0;
    while (ci < session.expectedChunkCount) {
      if (Map.get(session.chunks, Nat.compare, ci) == null) {
        let e = "upload incomplete: missing chunk " # Nat.toText(ci);
        auditErr(caller, "documentUpload:0", null, e);
        return #err(e);
      };
      ci += 1;
    };
    // Assemble blob: concatenate chunks 0..N-1 in order using blob iterator (memory-efficient)
    let assembled = VarArray.repeat<Nat8>(0, session.totalSizeBytes);
    var writePos : Nat = 0;
    ci := 0;
    while (ci < session.expectedChunkCount) {
      switch (Map.get(session.chunks, Nat.compare, ci)) {
        case (?chunk) {
          for (b in chunk.values()) {
            assembled[writePos] := b;
            writePos += 1;
          };
        };
        case null {};
      };
      ci += 1;
    };
    let assembledBlob = Blob.fromVarArray(assembled);
    // Validate assembled size matches declared totalSizeBytes
    if (assembledBlob.size() != session.totalSizeBytes) {
      let e = "assembled size mismatch: expected " # Nat.toText(session.totalSizeBytes) # ", got " # Nat.toText(assembledBlob.size());
      auditErr(caller, "documentUpload:0", null, e);
      return #err(e);
    };
    let sha256 = computeSha256(assembledBlob);
    let now = Time.now();
    // Create document and/or version; re-validate FK on the replace path
    let (documentId, versionId) : (Nat, Nat) = switch (session.replacesDocumentId) {
      case null {
        // New document + v1 version
        let docId = nextDocumentId;
        let verId = nextVersionId;
        nextDocumentId += 1; // SEC-INV-9: monotonic
        nextVersionId += 1;
        MutMap.add(documentVersions, Nat.compare, verId, {
          versionId = verId;
          documentId = docId;
          versionNumber = 1;
          filename = session.filename;
          contentType = session.contentType;
          sizeBytes = session.totalSizeBytes;
          blob = assembledBlob;
          sha256;
          uploadedAt = now;
          uploadedBy = caller;
          uploadNotes = session.uploadNotes;
        });
        MutMap.add(documents, Nat.compare, docId, {
          id = docId;
          matterId = session.matterId;
          currentVersionId = verId;
          status = #Active;
          createdAt = now;
          createdBy = caller;
        });
        appendVersionToDocument(docId, verId);
        (docId, verId)
      };
      case (?replaceId) {
        // Re-validate: doc still exists/active/in this matter; matter not archived mid-upload (SEC-INV-5)
        let doc = switch (lookupDocumentActive(replaceId)) {
          case (#err(e)) { auditErr(caller, "documentUpload:0", null, e); return #err(e) };
          case (#ok(d)) d;
        };
        if (doc.matterId != session.matterId) {
          let e = "document " # Nat.toText(replaceId) # " does not belong to this matter";
          auditErr(caller, "documentUpload:0", null, e);
          return #err(e);
        };
        switch (lookupMatterActive(session.matterId)) {
          case (#err(e)) { auditErr(caller, "documentUpload:0", null, e); return #err(e) };
          case (#ok(_)) {};
        };
        let versionNumber = switch (MutMap.get(versionsByDocument, Nat.compare, replaceId)) {
          case null 2;
          case (?arr) arr.size() + 1;
        };
        let verId = nextVersionId;
        nextVersionId += 1; // SEC-INV-9: monotonic
        MutMap.add(documentVersions, Nat.compare, verId, {
          versionId = verId;
          documentId = replaceId;
          versionNumber;
          filename = session.filename;
          contentType = session.contentType;
          sizeBytes = session.totalSizeBytes;
          blob = assembledBlob;
          sha256;
          uploadedAt = now;
          uploadedBy = caller;
          uploadNotes = session.uploadNotes;
        });
        MutMap.add(documents, Nat.compare, replaceId, { doc with currentVersionId = verId });
        appendVersionToDocument(replaceId, verId);
        (replaceId, verId)
      };
    };
    // Increment storage counter (never decremented — soft-delete keeps bytes)
    totalStorageUsedBytes += session.totalSizeBytes;
    // Delete session; no partial upload state persists after finalize
    MutMap.remove(uploadSessions, Nat.compare, sessionId);
    // SEC-INV-11: exactly one audit entry per mutator
    auditOk(caller, "documentUpload:" # Nat.toText(documentId), null);
    #ok({ documentId; versionId; sha256 })
  };

  public shared ({ caller }) func abandonUpload(sessionId : Nat) : async Result.Result<(), Text> {
    // SEC-INV-1
    switch (Auth.requireAuthenticated(caller)) {
      case (#err(e)) { auditErr(caller, "abandonUpload", null, e); return #err(e) };
      case (#ok) {};
    };
    // SEC-INV-2
    switch (requireRole(caller, #Associate)) {
      case (#err(e)) { auditErr(caller, "abandonUpload", null, e); return #err(e) };
      case (#ok) {};
    };
    let session = switch (MutMap.get(uploadSessions, Nat.compare, sessionId)) {
      case null {
        let e = "session " # Nat.toText(sessionId) # " not found";
        auditErr(caller, "abandonUpload", null, e);
        return #err(e);
      };
      case (?s) s;
    };
    // SEC-INV-3: caller-lock
    if (session.startedBy != caller) {
      let e = "not the session owner";
      auditErr(caller, "abandonUpload", null, e);
      return #err(e);
    };
    MutMap.remove(uploadSessions, Nat.compare, sessionId);
    auditOk(caller, "abandonUpload", null);
    #ok(())
  };

  // ── L2b Document lifecycle ────────────────────────────────────────────────
  // SEC-INV-4: no public method hard-deletes a Document or DocumentVersion.

  public shared ({ caller }) func deleteDocument(documentId : Nat) : async Result.Result<(), Text> {
    // SEC-INV-1
    switch (Auth.requireAuthenticated(caller)) {
      case (#err(e)) { auditErr(caller, "documentDelete:" # Nat.toText(documentId), null, e); return #err(e) };
      case (#ok) {};
    };
    // SEC-INV-2: Partner only for delete
    switch (requireRole(caller, #Partner)) {
      case (#err(e)) { auditErr(caller, "documentDelete:" # Nat.toText(documentId), null, e); return #err(e) };
      case (#ok) {};
    };
    switch (lookupDocumentActive(documentId)) {
      case (#err(e)) { auditErr(caller, "documentDelete:" # Nat.toText(documentId), null, e); return #err(e) };
      case (#ok(doc)) {
        // SEC-INV-4: soft-delete only; bytes remain and count against budget
        MutMap.add(documents, Nat.compare, documentId, { doc with status = #Deleted });
      };
    };
    auditOk(caller, "documentDelete:" # Nat.toText(documentId), null);
    #ok(())
  };

  // ── L2b Download flow ─────────────────────────────────────────────────────
  // UPDATE (not query) — must emit audit entry (SEC-INV-11).
  // Q7: chunk bytes flow via getChunk query (fast, not per-chunk-audited).

  public shared ({ caller }) func prepareDocumentDownload(
    versionId : Nat
  ) : async Result.Result<{ documentId : Nat; sizeBytes : Nat; chunkCount : Nat; sha256 : Blob; contentType : Text; filename : Text }, Text> {
    // SEC-INV-1
    switch (Auth.requireAuthenticated(caller)) {
      case (#err(e)) { auditErr(caller, "documentDownload:0", null, e); return #err(e) };
      case (#ok) {};
    };
    // SEC-INV-2: Staff or higher
    switch (requireRole(caller, #Staff)) {
      case (#err(e)) { auditErr(caller, "documentDownload:0", null, e); return #err(e) };
      case (#ok) {};
    };
    let version = switch (MutMap.get(documentVersions, Nat.compare, versionId)) {
      case null {
        let e = "version " # Nat.toText(versionId) # " not found";
        auditErr(caller, "documentDownload:0", null, e);
        return #err(e);
      };
      case (?v) v;
    };
    // SEC-INV-12: parent document must be #Active
    let doc = switch (MutMap.get(documents, Nat.compare, version.documentId)) {
      case null {
        let e = "document " # Nat.toText(version.documentId) # " not found";
        auditErr(caller, "documentDownload:" # Nat.toText(version.documentId), null, e);
        return #err(e);
      };
      case (?d) d;
    };
    if (doc.status != #Active) {
      let e = "document " # Nat.toText(doc.id) # " is not active";
      auditErr(caller, "documentDownload:" # Nat.toText(doc.id), null, e);
      return #err(e);
    };
    // For downloads: matter only needs to exist — any status including #Archived is readable
    switch (MutMap.get(matters, Nat.compare, doc.matterId)) {
      case null {
        let e = "matter " # Nat.toText(doc.matterId) # " not found";
        auditErr(caller, "documentDownload:" # Nat.toText(doc.id), null, e);
        return #err(e);
      };
      case (?_) {};
    };
    // SEC-INV-11: exactly one audit entry; action encodes documentId (target field has no Nat slot)
    auditOk(caller, "documentDownload:" # Nat.toText(doc.id), null);
    #ok({
      documentId = doc.id;
      sizeBytes = version.sizeBytes;
      chunkCount = DocumentModule.expectedChunkCount(version.sizeBytes);
      sha256 = version.sha256;
      contentType = version.contentType;
      filename = version.filename;
    })
  };

  // ── L2b Admin ─────────────────────────────────────────────────────────────

  public shared ({ caller }) func setStorageBudget(newBudgetBytes : Nat) : async Result.Result<(), Text> {
    // SEC-INV-1
    switch (Auth.requireAuthenticated(caller)) {
      case (#err(e)) { auditErr(caller, "setStorageBudget", null, e); return #err(e) };
      case (#ok) {};
    };
    switch (requireOperationsOrMaster(caller)) {
      case (#err(e)) { auditErr(caller, "setStorageBudget", null, e); return #err(e) };
      case (#ok) {};
    };
    if (newBudgetBytes < totalStorageUsedBytes) {
      let e = "budget cannot be below current usage (" # Nat.toText(totalStorageUsedBytes) # " bytes used)";
      auditErr(caller, "setStorageBudget", null, e);
      return #err(e);
    };
    storageBudgetBytes := newBudgetBytes;
    auditOk(caller, "setStorageBudget", null);
    #ok(())
  };

  // ── L4 Queries — search ──────────────────────────────────────────────────
  // SEC-INV-1 (L4): trap on anonymous — queries cannot emit audit; trap is correct.
  // SEC-INV-5 (L4): search is read-only over existing Maps; no state mutation.
  // SEC-INV-6 (L4): limit clamped to min(limit, 1000).
  // Searches not audited — consistent with listClients/listMatters (spec §2 Q5).

  public query ({ caller }) func searchClients(filter : ClientFilter, after : Nat, limit : Nat) : async [Client] {
    switch (Auth.requireAuthenticated(caller)) { case (#err(_)) assert false; case (#ok) {} };
    let cap = if (limit > 1000) 1000 else limit;
    let base = MutMap.entriesFrom(clients, Nat.compare, after + 1);
    let matched = Iter.filter(base, func((_, c) : (Nat, Client)) : Bool {
      Search.matchesClientFilter(c, filter)
    });
    Iter.toArray(Iter.map(Iter.take(matched, cap), func((_, c) : (Nat, Client)) : Client { c }))
  };

  public query ({ caller }) func searchMatters(filter : MatterFilter, after : Nat, limit : Nat) : async [Matter] {
    switch (Auth.requireAuthenticated(caller)) { case (#err(_)) assert false; case (#ok) {} };
    let cap = if (limit > 1000) 1000 else limit;
    let base = MutMap.entriesFrom(matters, Nat.compare, after + 1);
    let matched = Iter.filter(base, func((_, m) : (Nat, Matter)) : Bool {
      Search.matchesMatterFilter(m, filter)
    });
    Iter.toArray(Iter.map(Iter.take(matched, cap), func((_, m) : (Nat, Matter)) : Matter { m }))
  };

  // SEC-INV-9 (L4): matches against currentVersion only — never searches historical versions.
  // A document whose current version does not match the filter is excluded even if an older
  // version would have matched. See spec §2 derived decisions and §6 invariant 9.
  public query ({ caller }) func searchDocuments(filter : DocumentFilter, after : Nat, limit : Nat) : async [DocumentSearchResult] {
    switch (Auth.requireAuthenticated(caller)) { case (#err(_)) assert false; case (#ok) {} };
    let cap = if (limit > 1000) 1000 else limit;
    let base = MutMap.entriesFrom(documents, Nat.compare, after + 1);
    let matched = Iter.filterMap<(Nat, Document), DocumentSearchResult>(base,
      func((_, d) : (Nat, Document)) : ?DocumentSearchResult {
        switch (MutMap.get(documentVersions, Nat.compare, d.currentVersionId)) {
          case null null;
          case (?v) {
            if (Search.matchesDocumentFilter(d, v, filter))
              ?{ document = d; currentVersion = stripBlobFromVersion(v) }
            else null
          };
        };
      }
    );
    Iter.toArray(Iter.take(matched, cap))
  };

  // ── L4 Queries — dashboard counts ────────────────────────────────────────
  // Single-pass O(n) counts; not cached. SEC-INV-1: trap on anonymous.

  public query ({ caller }) func mattersByStatus() : async MatterStatusCounts {
    switch (Auth.requireAuthenticated(caller)) { case (#err(_)) assert false; case (#ok) {} };
    var open = 0; var onHold = 0; var closed = 0; var archived = 0;
    for ((_, m) in MutMap.entries(matters)) {
      switch (m.status) {
        case (#Open)     { open     += 1 };
        case (#OnHold)   { onHold   += 1 };
        case (#Closed)   { closed   += 1 };
        case (#Archived) { archived += 1 };
      };
    };
    { open; onHold; closed; archived }
  };

  public query ({ caller }) func clientsByStatus() : async ClientStatusCounts {
    switch (Auth.requireAuthenticated(caller)) { case (#err(_)) assert false; case (#ok) {} };
    var active = 0; var inactive = 0;
    for ((_, c) in MutMap.entries(clients)) {
      switch (c.status) {
        case (#Active)   { active   += 1 };
        case (#Inactive) { inactive += 1 };
      };
    };
    { active; inactive }
  };

  public query ({ caller }) func documentsByStatus() : async DocumentStatusCounts {
    switch (Auth.requireAuthenticated(caller)) { case (#err(_)) assert false; case (#ok) {} };
    var active = 0; var deleted = 0;
    for ((_, d) in MutMap.entries(documents)) {
      switch (d.status) {
        case (#Active)  { active  += 1 };
        case (#Deleted) { deleted += 1 };
      };
    };
    { active; deleted }
  };

  // ── Firm Library — Folder queries (not audited) ──────────────────────────
  // SEC-INV-1: trap on anonymous (queries can't audit).

  public query ({ caller }) func getFolder(folderId : Nat) : async ?Folder {
    switch (Auth.requireAuthenticated(caller)) { case (#err(_)) assert false; case (#ok) {} };
    MutMap.get(folders, Nat.compare, folderId)
  };

  public query ({ caller }) func listAllFolders() : async [Folder] {
    switch (Auth.requireAuthenticated(caller)) { case (#err(_)) assert false; case (#ok) {} };
    Iter.toArray(Iter.map(MutMap.entries(folders), func((_, f) : (Nat, Folder)) : Folder { f }))
  };

  // #Root: root-level folders + root items; #Folder id: children of id + items in id.
  // #Any / #Subtree: undefined for this method — returns empty FolderListing.
  public query ({ caller }) func listFolderContents(scope : FolderScope) : async FolderListing {
    switch (Auth.requireAuthenticated(caller)) { case (#err(_)) assert false; case (#ok) {} };
    switch scope {
      case (#Root) {
        let childFolders = Iter.toArray(Iter.map(
          Iter.filter(MutMap.entries(folders), func((_, f) : (Nat, Folder)) : Bool { f.parentId == null }),
          func((_, f) : (Nat, Folder)) : Folder { f }
        ));
        let rootItems = Iter.toArray(Iter.filterMap<(Nat, LibraryItem), LibraryItemSearchResult>(
          MutMap.entries(libraryItems),
          func((_, item) : (Nat, LibraryItem)) : ?LibraryItemSearchResult {
            if (item.folderId != null or item.status == #Deleted) return null;
            switch (MutMap.get(libraryVersions, Nat.compare, item.currentVersionId)) {
              case null null;
              case (?v) ?{ item; currentVersion = Library.stripBlobFromLibraryVersion(v) };
            };
          }
        ));
        { folders = childFolders; items = rootItems }
      };
      case (#Folder fid) {
        let childFolders = Iter.toArray(Iter.map(
          Iter.filter(MutMap.entries(folders), func((_, f) : (Nat, Folder)) : Bool { f.parentId == ?fid }),
          func((_, f) : (Nat, Folder)) : Folder { f }
        ));
        let folderItems = Iter.toArray(Iter.filterMap<(Nat, LibraryItem), LibraryItemSearchResult>(
          MutMap.entries(libraryItems),
          func((_, item) : (Nat, LibraryItem)) : ?LibraryItemSearchResult {
            if (item.folderId != ?fid or item.status == #Deleted) return null;
            switch (MutMap.get(libraryVersions, Nat.compare, item.currentVersionId)) {
              case null null;
              case (?v) ?{ item; currentVersion = Library.stripBlobFromLibraryVersion(v) };
            };
          }
        ));
        { folders = childFolders; items = folderItems }
      };
      case _ { { folders = []; items = [] } };  // #Any/#Subtree undefined for this method
    }
  };

  public query ({ caller }) func getFolderDepth(folderId : Nat) : async ?Nat {
    switch (Auth.requireAuthenticated(caller)) { case (#err(_)) assert false; case (#ok) {} };
    switch (MutMap.get(folders, Nat.compare, folderId)) {
      case null null;
      case (?_) ?computeFolderDepth(folderId);
    }
  };

  public query ({ caller }) func getFolderCount() : async Nat {
    switch (Auth.requireAuthenticated(caller)) { case (#err(_)) assert false; case (#ok) {} };
    MutMap.size(folders)
  };

  // ── Firm Library — Item queries (not audited) ─────────────────────────────

  public query ({ caller }) func getLibraryItem(id : Nat) : async ?LibraryItem {
    switch (Auth.requireAuthenticated(caller)) { case (#err(_)) assert false; case (#ok) {} };
    MutMap.get(libraryItems, Nat.compare, id)
  };

  public query ({ caller }) func listLibraryItems(filter : LibraryFilter, after : Nat, limit : Nat) : async [LibraryItemSearchResult] {
    switch (Auth.requireAuthenticated(caller)) { case (#err(_)) assert false; case (#ok) {} };
    doSearchLibrary(filter, after, limit)
  };

  // Returns full version including blob — for inspection. Use prepareLibraryDownload + getLibraryChunk for download.
  public query ({ caller }) func getLibraryVersion(versionId : Nat) : async ?LibraryVersion {
    switch (Auth.requireAuthenticated(caller)) { case (#err(_)) assert false; case (#ok) {} };
    MutMap.get(libraryVersions, Nat.compare, versionId)
  };

  // Blob stripped; use getLibraryChunk for actual bytes.
  public query ({ caller }) func listLibraryVersions(itemId : Nat) : async [LibraryVersion] {
    switch (Auth.requireAuthenticated(caller)) { case (#err(_)) assert false; case (#ok) {} };
    let vids : [Nat] = switch (MutMap.get(libraryVersionsByItem, Nat.compare, itemId)) {
      case null [];
      case (?arr) arr;
    };
    Array.filterMap<Nat, LibraryVersion>(vids, func(vid) {
      switch (MutMap.get(libraryVersions, Nat.compare, vid)) {
        case null null;
        case (?v) ?Library.stripBlobFromLibraryVersion(v);
      };
    })
  };

  public query ({ caller }) func getLibraryItemCount() : async Nat {
    switch (Auth.requireAuthenticated(caller)) { case (#err(_)) assert false; case (#ok) {} };
    MutMap.size(libraryItems)
  };

  // SEC-INV-18: blob slicing via iterator (NOT Blob.toArray()) — critical for 5 GiB files.
  // SEC-INV-15: allows #Active and #Archived; rejects #Deleted (returns null). Not audited per chunk.
  public query ({ caller }) func getLibraryChunk(versionId : Nat, chunkIndex : Nat) : async ?Blob {
    switch (Auth.requireAuthenticated(caller)) { case (#err(_)) assert false; case (#ok) {} };
    switch (requireRole(caller, #Staff)) { case (#err(_)) assert false; case (#ok) {} };
    switch (MutMap.get(libraryVersions, Nat.compare, versionId)) {
      case null null;
      case (?version) {
        switch (MutMap.get(libraryItems, Nat.compare, version.itemId)) {
          case null null;
          case (?item) {
            if (item.status == #Deleted) return null;
            let count = DocumentModule.expectedChunkCount(version.sizeBytes);
            if (chunkIndex >= count) return null;
            let (startByte, endByte) = DocumentModule.chunkRange(chunkIndex, version.sizeBytes);
            let chunkSize = endByte - startByte;
            let result = VarArray.repeat<Nat8>(0, chunkSize);
            var bytePos : Nat = 0;
            var writePos : Nat = 0;
            label sliceLoop for (b in version.blob.values()) {
              if (bytePos >= endByte) break sliceLoop;
              if (bytePos >= startByte) {
                result[writePos] := b;
                writePos += 1;
              };
              bytePos += 1;
            };
            ?Blob.fromVarArray(result)
          };
        };
      };
    };
  };

  // ── Firm Library — Search (not audited) ───────────────────────────────────
  // SEC-INV-21: matches current version only — older versions not searched.
  // SEC-INV-19: limit capped at 1000.

  public query ({ caller }) func searchLibrary(filter : LibraryFilter, after : Nat, limit : Nat) : async [LibraryItemSearchResult] {
    switch (Auth.requireAuthenticated(caller)) { case (#err(_)) assert false; case (#ok) {} };
    doSearchLibrary(filter, after, limit)
  };

  // ── Firm Library — Folder updates (audited) ───────────────────────────────
  // SEC-INV-2: Associate or higher for create/rename/move; Partner only for delete.
  // SEC-INV-17: every mutator emits exactly one audit entry.
  // SEC-INV-20: no Runtime.trap on mutator path — all errors return Result.

  public shared ({ caller }) func createFolder(name : Text, parentId : ?Nat) : async Result.Result<Nat, Text> {
    switch (Auth.requireAuthenticated(caller)) { case (#err(e)) { auditErr(caller, "folder.create", null, e); return #err(e) }; case (#ok) {} };
    switch (requireRole(caller, #Associate)) { case (#err(e)) { auditErr(caller, "folder.create", null, e); return #err(e) }; case (#ok) {} };
    switch (Library.validateFolderName(name)) {
      case (#err(e)) { auditErr(caller, "folder.create", null, e); return #err(e) };
      case (#ok) {};
    };
    // SEC-INV-11: depth check
    switch (parentId) {
      case null {};  // depth = 1, always OK
      case (?pid) {
        switch (lookupFolder(pid)) {
          case (#err(e)) { auditErr(caller, "folder.create", null, e); return #err(e) };
          case (#ok(_)) {
            if (computeFolderDepth(pid) + 1 > Library.MAX_FOLDER_DEPTH) {
              let e = "folder depth exceeded: max depth is " # Nat.toText(Library.MAX_FOLDER_DEPTH);
              auditErr(caller, "folder.create", null, e);
              return #err(e);
            };
          };
        };
      };
    };
    let folderId = nextFolderId;
    nextFolderId += 1;
    MutMap.add(folders, Nat.compare, folderId, {
      id = folderId; name; parentId;
      createdAt = Time.now(); createdBy = caller;
    });
    auditOk(caller, "folder.create:" # Nat.toText(folderId), null);
    #ok(folderId)
  };

  public shared ({ caller }) func renameFolder(folderId : Nat, newName : Text) : async Result.Result<(), Text> {
    switch (Auth.requireAuthenticated(caller)) { case (#err(e)) { auditErr(caller, "folder.rename:" # Nat.toText(folderId), null, e); return #err(e) }; case (#ok) {} };
    switch (requireRole(caller, #Associate)) { case (#err(e)) { auditErr(caller, "folder.rename:" # Nat.toText(folderId), null, e); return #err(e) }; case (#ok) {} };
    let folder = switch (lookupFolder(folderId)) {
      case (#err(e)) { auditErr(caller, "folder.rename:" # Nat.toText(folderId), null, e); return #err(e) };
      case (#ok(f)) f;
    };
    switch (Library.validateFolderName(newName)) {
      case (#err(e)) { auditErr(caller, "folder.rename:" # Nat.toText(folderId), null, e); return #err(e) };
      case (#ok) {};
    };
    MutMap.add(folders, Nat.compare, folderId, { folder with name = newName });
    auditOk(caller, "folder.rename:" # Nat.toText(folderId), null);
    #ok(())
  };

  public shared ({ caller }) func moveFolder(folderId : Nat, newParentId : ?Nat) : async Result.Result<(), Text> {
    let actionStr = "folder.move:" # Nat.toText(folderId);
    switch (Auth.requireAuthenticated(caller)) { case (#err(e)) { auditErr(caller, actionStr, null, e); return #err(e) }; case (#ok) {} };
    switch (requireRole(caller, #Associate)) { case (#err(e)) { auditErr(caller, actionStr, null, e); return #err(e) }; case (#ok) {} };
    let folder = switch (lookupFolder(folderId)) {
      case (#err(e)) { auditErr(caller, actionStr, null, e); return #err(e) };
      case (#ok(f)) f;
    };
    // SEC-INV-12: cycle prevention — newParentId must not be folderId or any descendant
    let candidateId = switch (newParentId) {
      case null { 0 };  // moving to root; no cycle possible (0 is not a valid folder ID)
      case (?pid) pid;
    };
    switch (newParentId) {
      case (?pid) {
        if (subtreeContains(folderId, pid)) {
          let e = "cycle detected: cannot move folder into its own subtree";
          auditErr(caller, actionStr, null, e);
          return #err(e);
        };
        switch (lookupFolder(pid)) {
          case (#err(e)) { auditErr(caller, actionStr, null, e); return #err(e) };
          case (#ok(_)) {};
        };
        // Depth check: newParentDepth + subtreeDepth(folderId) + 1 ≤ MAX_FOLDER_DEPTH (spec §2 derived)
        let newParentDepth = computeFolderDepth(pid);
        if (newParentDepth + subtreeDepth(folderId) + 1 > Library.MAX_FOLDER_DEPTH) {
          let e = "folder depth exceeded: move would push descendants beyond max depth " # Nat.toText(Library.MAX_FOLDER_DEPTH);
          auditErr(caller, actionStr, null, e);
          return #err(e);
        };
      };
      case null {
        // Moving to root: depth becomes 1; subtreeDepth + 1 ≤ MAX_FOLDER_DEPTH
        if (subtreeDepth(folderId) + 1 > Library.MAX_FOLDER_DEPTH) {
          let e = "folder depth exceeded: subtree too deep to place at root";
          auditErr(caller, actionStr, null, e);
          return #err(e);
        };
      };
    };
    ignore candidateId;
    MutMap.add(folders, Nat.compare, folderId, { folder with parentId = newParentId });
    let toStr = switch (newParentId) { case null "root"; case (?pid) Nat.toText(pid) };
    auditOk(caller, actionStr # ":to:" # toStr, null);
    #ok(())
  };

  // Partner only. Hard delete — folder records are tiny; soft-delete adds no value. SEC-INV-13.
  public shared ({ caller }) func deleteFolder(folderId : Nat) : async Result.Result<(), Text> {
    let actionStr = "folder.delete:" # Nat.toText(folderId);
    switch (Auth.requireAuthenticated(caller)) { case (#err(e)) { auditErr(caller, actionStr, null, e); return #err(e) }; case (#ok) {} };
    switch (requireRole(caller, #Partner)) { case (#err(e)) { auditErr(caller, actionStr, null, e); return #err(e) }; case (#ok) {} };
    switch (lookupFolder(folderId)) {
      case (#err(e)) { auditErr(caller, actionStr, null, e); return #err(e) };
      case (#ok(_)) {};
    };
    switch (folderHasDependents(folderId)) {
      case (?reason) {
        let e = "folder not empty: " # reason;
        auditErr(caller, actionStr, null, e);
        return #err(e);
      };
      case null {};
    };
    MutMap.remove(folders, Nat.compare, folderId);
    auditOk(caller, actionStr, null);
    #ok(())
  };

  // ── Firm Library — Upload updates (session-based) ─────────────────────────
  // SEC-INV-5: caller-locked sessions. SEC-INV-7: 5 GiB per-item ceiling. SEC-INV-6: shared budget.

  public shared ({ caller }) func startLibraryUpload(
    name : Text,
    folderId : ?Nat,
    tags : [Text],
    description : Text,
    filename : Text,
    contentType : Text,
    totalSizeBytes : Nat,
    uploadNotes : Text,
    replacesItemId : ?Nat
  ) : async Result.Result<Nat, Text> {
    switch (Auth.requireAuthenticated(caller)) { case (#err(e)) { auditErr(caller, "library.upload.start", null, e); return #err(e) }; case (#ok) {} };
    switch (requireRole(caller, #Associate)) { case (#err(e)) { auditErr(caller, "library.upload.start", null, e); return #err(e) }; case (#ok) {} };
    // SEC-INV-7: size ceiling (reject zero and over-limit)
    if (totalSizeBytes == 0) {
      let e = "empty file: totalSizeBytes must be > 0";
      auditErr(caller, "library.upload.start", null, e); return #err(e);
    };
    if (totalSizeBytes > Library.MAX_LIBRARY_ITEM_SIZE) {
      let e = "file too large: exceeds 5 GiB library limit";
      auditErr(caller, "library.upload.start", null, e); return #err(e);
    };
    // SEC-INV-8: content type validation
    switch (Library.validateContentType(contentType)) {
      case (#err(e)) { auditErr(caller, "library.upload.start", null, e); return #err(e) };
      case (#ok) {};
    };
    // SEC-INV-6: shared budget check
    switch (validateLibraryBudgetAvailable(totalSizeBytes)) {
      case (#err(e)) { auditErr(caller, "library.upload.start", null, e); return #err(e) };
      case (#ok) {};
    };
    // validate description length
    if (description.size() > Library.MAX_LIBRARY_DESCRIPTION_LENGTH) {
      let e = "description too long: max " # Nat.toText(Library.MAX_LIBRARY_DESCRIPTION_LENGTH) # " chars";
      auditErr(caller, "library.upload.start", null, e); return #err(e);
    };
    // Validate per path: new item vs replacement
    switch (replacesItemId) {
      case null {
        // New item: validate name, folder, tags
        if (name.size() == 0 or name.size() > Library.MAX_LIBRARY_NAME_LENGTH) {
          let e = "name must be 1–" # Nat.toText(Library.MAX_LIBRARY_NAME_LENGTH) # " chars";
          auditErr(caller, "library.upload.start", null, e); return #err(e);
        };
        switch (folderId) {
          case null {};
          case (?fid) switch (lookupFolder(fid)) {
            case (#err(e)) { auditErr(caller, "library.upload.start", null, e); return #err(e) };
            case (#ok(_)) {};
          };
        };
        switch (Library.validateTags(tags)) {
          case (#err(e)) { auditErr(caller, "library.upload.start", null, e); return #err(e) };
          case (#ok(_)) {};
        };
      };
      case (?replaceId) {
        // Replacement: item must exist and be #Active
        switch (lookupLibraryItemActive(replaceId)) {
          case (#err(e)) { auditErr(caller, "library.upload.start", null, e); return #err(e) };
          case (#ok(_)) {};
        };
      };
    };
    let sessionId = nextLibrarySessionId;
    nextLibrarySessionId += 1;
    // Validate and normalise tags for the session record
    let normalizedTags = switch (Library.validateTags(tags)) {
      case (#err(_)) [];
      case (#ok(t)) t;
    };
    MutMap.add(libraryUploadSessions, Nat.compare, sessionId, {
      sessionId; name; folderId; tags = normalizedTags; description;
      filename; contentType; totalSizeBytes;
      expectedChunkCount = DocumentModule.expectedChunkCount(totalSizeBytes);
      uploadNotes; replacesItemId;
      chunks = Map.empty<Nat, Blob>();
      startedAt = Time.now(); startedBy = caller;
    });
    auditOk(caller, "library.upload.start", null);
    #ok(sessionId)
  };

  public shared ({ caller }) func appendLibraryChunk(
    sessionId : Nat, chunkIndex : Nat, chunkBytes : Blob
  ) : async Result.Result<(), Text> {
    switch (Auth.requireAuthenticated(caller)) { case (#err(e)) { auditErr(caller, "appendLibraryChunk", null, e); return #err(e) }; case (#ok) {} };
    switch (requireRole(caller, #Associate)) { case (#err(e)) { auditErr(caller, "appendLibraryChunk", null, e); return #err(e) }; case (#ok) {} };
    let session = switch (MutMap.get(libraryUploadSessions, Nat.compare, sessionId)) {
      case null { let e = "session " # Nat.toText(sessionId) # " not found"; auditErr(caller, "appendLibraryChunk", null, e); return #err(e) };
      case (?s) s;
    };
    // SEC-INV-5: caller-lock
    if (session.startedBy != caller) {
      let e = "not the session owner"; auditErr(caller, "appendLibraryChunk", null, e); return #err(e);
    };
    if (chunkIndex >= session.expectedChunkCount) {
      let e = "chunk index " # Nat.toText(chunkIndex) # " out of range";
      auditErr(caller, "appendLibraryChunk", null, e); return #err(e);
    };
    // Chunk size validation: non-last = CHUNK_SIZE, last = remainder
    let isLastChunk = chunkIndex == session.expectedChunkCount - 1;
    let expectedSize = if (isLastChunk) {
      session.totalSizeBytes - chunkIndex * DocumentModule.CHUNK_SIZE
    } else DocumentModule.CHUNK_SIZE;
    if (chunkBytes.size() != expectedSize) {
      let e = "chunk " # Nat.toText(chunkIndex) # " wrong size: expected " # Nat.toText(expectedSize) # ", got " # Nat.toText(chunkBytes.size());
      auditErr(caller, "appendLibraryChunk", null, e); return #err(e);
    };
    // Idempotent: last write wins (same as L2b)
    let newChunks = Map.add(session.chunks, Nat.compare, chunkIndex, chunkBytes);
    MutMap.add(libraryUploadSessions, Nat.compare, sessionId, { session with chunks = newChunks });
    auditOk(caller, "appendLibraryChunk", null);
    #ok(())
  };

  public shared ({ caller }) func finalizeLibraryUpload(
    sessionId : Nat
  ) : async Result.Result<{ itemId : Nat; versionId : Nat; sha256 : Blob }, Text> {
    switch (Auth.requireAuthenticated(caller)) { case (#err(e)) { auditErr(caller, "library.upload:0", null, e); return #err(e) }; case (#ok) {} };
    switch (requireRole(caller, #Associate)) { case (#err(e)) { auditErr(caller, "library.upload:0", null, e); return #err(e) }; case (#ok) {} };
    let session = switch (MutMap.get(libraryUploadSessions, Nat.compare, sessionId)) {
      case null { let e = "session " # Nat.toText(sessionId) # " not found"; auditErr(caller, "library.upload:0", null, e); return #err(e) };
      case (?s) s;
    };
    if (session.startedBy != caller) {
      let e = "not the session owner"; auditErr(caller, "library.upload:0", null, e); return #err(e);
    };
    // Completeness check
    if (Map.size(session.chunks) != session.expectedChunkCount) {
      let e = "upload incomplete: expected " # Nat.toText(session.expectedChunkCount) # " chunks, have " # Nat.toText(Map.size(session.chunks));
      auditErr(caller, "library.upload:0", null, e); return #err(e);
    };
    var ci : Nat = 0;
    while (ci < session.expectedChunkCount) {
      if (Map.get(session.chunks, Nat.compare, ci) == null) {
        let e = "upload incomplete: missing chunk " # Nat.toText(ci);
        auditErr(caller, "library.upload:0", null, e); return #err(e);
      };
      ci += 1;
    };
    // Assemble blob via iterator — SEC-INV-18: never Blob.toArray() for library items
    let assembled = VarArray.repeat<Nat8>(0, session.totalSizeBytes);
    var writePos : Nat = 0;
    ci := 0;
    while (ci < session.expectedChunkCount) {
      switch (Map.get(session.chunks, Nat.compare, ci)) {
        case (?chunk) { for (b in chunk.values()) { assembled[writePos] := b; writePos += 1 } };
        case null {};
      };
      ci += 1;
    };
    let assembledBlob = Blob.fromVarArray(assembled);
    if (assembledBlob.size() != session.totalSizeBytes) {
      let e = "assembled size mismatch";
      auditErr(caller, "library.upload:0", null, e); return #err(e);
    };
    let sha256 = computeSha256(assembledBlob);
    let now = Time.now();
    // Create item and/or version
    let (itemId, versionId) : (Nat, Nat) = switch (session.replacesItemId) {
      case null {
        // New item + v1 version
        let iid = nextLibraryItemId;
        let vid = nextLibraryVersionId;
        nextLibraryItemId += 1;
        nextLibraryVersionId += 1;
        MutMap.add(libraryVersions, Nat.compare, vid, {
          versionId = vid; itemId = iid; versionNumber = 1;
          filename = session.filename; contentType = session.contentType;
          sizeBytes = session.totalSizeBytes; blob = assembledBlob; sha256;
          uploadedAt = now; uploadedBy = caller; uploadNotes = session.uploadNotes;
        });
        MutMap.add(libraryItems, Nat.compare, iid, {
          id = iid; name = session.name; folderId = session.folderId;
          tags = session.tags; description = session.description;
          currentVersionId = vid; status = #Active;
          createdAt = now; createdBy = caller;
        });
        appendVersionToLibraryItem(iid, vid);
        (iid, vid)
      };
      case (?replaceId) {
        // New version of existing item — re-validate still active
        let item = switch (lookupLibraryItemActive(replaceId)) {
          case (#err(e)) { auditErr(caller, "library.upload:0", null, e); return #err(e) };
          case (#ok(i)) i;
        };
        let versionNumber = switch (MutMap.get(libraryVersionsByItem, Nat.compare, replaceId)) {
          case null 2;
          case (?arr) arr.size() + 1;
        };
        let vid = nextLibraryVersionId;
        nextLibraryVersionId += 1;
        MutMap.add(libraryVersions, Nat.compare, vid, {
          versionId = vid; itemId = replaceId; versionNumber;
          filename = session.filename; contentType = session.contentType;
          sizeBytes = session.totalSizeBytes; blob = assembledBlob; sha256;
          uploadedAt = now; uploadedBy = caller; uploadNotes = session.uploadNotes;
        });
        MutMap.add(libraryItems, Nat.compare, replaceId, { item with currentVersionId = vid });
        appendVersionToLibraryItem(replaceId, vid);
        (replaceId, vid)
      };
    };
    // Shared counter — library uploads count against the same budget as L2b docs (Q8)
    totalStorageUsedBytes += session.totalSizeBytes;
    MutMap.remove(libraryUploadSessions, Nat.compare, sessionId);
    auditOk(caller, "library.upload:" # Nat.toText(itemId), null);
    #ok({ itemId; versionId; sha256 })
  };

  public shared ({ caller }) func abandonLibraryUpload(sessionId : Nat) : async Result.Result<(), Text> {
    switch (Auth.requireAuthenticated(caller)) { case (#err(e)) { auditErr(caller, "library.upload.abandon", null, e); return #err(e) }; case (#ok) {} };
    switch (requireRole(caller, #Associate)) { case (#err(e)) { auditErr(caller, "library.upload.abandon", null, e); return #err(e) }; case (#ok) {} };
    let session = switch (MutMap.get(libraryUploadSessions, Nat.compare, sessionId)) {
      case null { let e = "session " # Nat.toText(sessionId) # " not found"; auditErr(caller, "library.upload.abandon", null, e); return #err(e) };
      case (?s) s;
    };
    if (session.startedBy != caller) {
      let e = "not the session owner"; auditErr(caller, "library.upload.abandon", null, e); return #err(e);
    };
    MutMap.remove(libraryUploadSessions, Nat.compare, sessionId);
    auditOk(caller, "library.upload.abandon", null);
    #ok(())
  };

  // ── Firm Library — Item metadata updates ─────────────────────────────────
  // Associate or higher; item must be #Active for all edits.

  public shared ({ caller }) func renameLibraryItem(itemId : Nat, newName : Text) : async Result.Result<(), Text> {
    let act = "library.rename:" # Nat.toText(itemId);
    switch (Auth.requireAuthenticated(caller)) { case (#err(e)) { auditErr(caller, act, null, e); return #err(e) }; case (#ok) {} };
    switch (requireRole(caller, #Associate)) { case (#err(e)) { auditErr(caller, act, null, e); return #err(e) }; case (#ok) {} };
    let item = switch (lookupLibraryItemActive(itemId)) {
      case (#err(e)) { auditErr(caller, act, null, e); return #err(e) };
      case (#ok(i)) i;
    };
    if (newName.size() == 0 or newName.size() > Library.MAX_LIBRARY_NAME_LENGTH) {
      let e = "name must be 1–" # Nat.toText(Library.MAX_LIBRARY_NAME_LENGTH) # " chars";
      auditErr(caller, act, null, e); return #err(e);
    };
    MutMap.add(libraryItems, Nat.compare, itemId, { item with name = newName });
    auditOk(caller, act, null);
    #ok(())
  };

  public shared ({ caller }) func moveLibraryItem(itemId : Nat, newFolderId : ?Nat) : async Result.Result<(), Text> {
    let act = "library.move:" # Nat.toText(itemId);
    switch (Auth.requireAuthenticated(caller)) { case (#err(e)) { auditErr(caller, act, null, e); return #err(e) }; case (#ok) {} };
    switch (requireRole(caller, #Associate)) { case (#err(e)) { auditErr(caller, act, null, e); return #err(e) }; case (#ok) {} };
    let item = switch (lookupLibraryItemActive(itemId)) {
      case (#err(e)) { auditErr(caller, act, null, e); return #err(e) };
      case (#ok(i)) i;
    };
    switch (newFolderId) {
      case null {};
      case (?fid) switch (lookupFolder(fid)) {
        case (#err(e)) { auditErr(caller, act, null, e); return #err(e) };
        case (#ok(_)) {};
      };
    };
    MutMap.add(libraryItems, Nat.compare, itemId, { item with folderId = newFolderId });
    let toStr = switch (newFolderId) { case null "root"; case (?fid) Nat.toText(fid) };
    auditOk(caller, act # ":to:" # toStr, null);
    #ok(())
  };

  public shared ({ caller }) func updateLibraryItemDescription(itemId : Nat, newDescription : Text) : async Result.Result<(), Text> {
    let act = "library.description:" # Nat.toText(itemId);
    switch (Auth.requireAuthenticated(caller)) { case (#err(e)) { auditErr(caller, act, null, e); return #err(e) }; case (#ok) {} };
    switch (requireRole(caller, #Associate)) { case (#err(e)) { auditErr(caller, act, null, e); return #err(e) }; case (#ok) {} };
    let item = switch (lookupLibraryItemActive(itemId)) {
      case (#err(e)) { auditErr(caller, act, null, e); return #err(e) };
      case (#ok(i)) i;
    };
    if (newDescription.size() > Library.MAX_LIBRARY_DESCRIPTION_LENGTH) {
      let e = "description too long";
      auditErr(caller, act, null, e); return #err(e);
    };
    MutMap.add(libraryItems, Nat.compare, itemId, { item with description = newDescription });
    auditOk(caller, act, null);
    #ok(())
  };

  public shared ({ caller }) func addLibraryItemTag(itemId : Nat, tag : Text) : async Result.Result<(), Text> {
    let act = "library.tag.add:" # Nat.toText(itemId);
    switch (Auth.requireAuthenticated(caller)) { case (#err(e)) { auditErr(caller, act, null, e); return #err(e) }; case (#ok) {} };
    switch (requireRole(caller, #Associate)) { case (#err(e)) { auditErr(caller, act, null, e); return #err(e) }; case (#ok) {} };
    let item = switch (lookupLibraryItemActive(itemId)) {
      case (#err(e)) { auditErr(caller, act, null, e); return #err(e) };
      case (#ok(i)) i;
    };
    let nt = switch (Library.normalizeTag(tag)) {
      case (#err(e)) { auditErr(caller, act, null, e); return #err(e) };
      case (#ok(t)) t;
    };
    if (item.tags.size() >= Library.MAX_LIBRARY_TAGS) {
      let e = "tag limit reached: max " # Nat.toText(Library.MAX_LIBRARY_TAGS);
      auditErr(caller, act, null, e); return #err(e);
    };
    // Only add if not already present
    var dup = false;
    for (existing in item.tags.vals()) { if (existing == nt) dup := true };
    let newTags = if (dup) item.tags else Array.concat<Text>(item.tags, [nt]);
    MutMap.add(libraryItems, Nat.compare, itemId, { item with tags = newTags });
    auditOk(caller, act, null);
    #ok(())
  };

  public shared ({ caller }) func removeLibraryItemTag(itemId : Nat, tag : Text) : async Result.Result<(), Text> {
    let act = "library.tag.remove:" # Nat.toText(itemId);
    switch (Auth.requireAuthenticated(caller)) { case (#err(e)) { auditErr(caller, act, null, e); return #err(e) }; case (#ok) {} };
    switch (requireRole(caller, #Associate)) { case (#err(e)) { auditErr(caller, act, null, e); return #err(e) }; case (#ok) {} };
    let item = switch (lookupLibraryItemActive(itemId)) {
      case (#err(e)) { auditErr(caller, act, null, e); return #err(e) };
      case (#ok(i)) i;
    };
    let nt = switch (Library.normalizeTag(tag)) {
      case (#err(e)) { auditErr(caller, act, null, e); return #err(e) };
      case (#ok(t)) t;
    };
    let newTags = Array.filter<Text>(item.tags, func(t) { t != nt });
    MutMap.add(libraryItems, Nat.compare, itemId, { item with tags = newTags });
    auditOk(caller, act, null);
    #ok(())
  };

  public shared ({ caller }) func setLibraryItemTags(itemId : Nat, tags : [Text]) : async Result.Result<(), Text> {
    let act = "library.tag.set:" # Nat.toText(itemId);
    switch (Auth.requireAuthenticated(caller)) { case (#err(e)) { auditErr(caller, act, null, e); return #err(e) }; case (#ok) {} };
    switch (requireRole(caller, #Associate)) { case (#err(e)) { auditErr(caller, act, null, e); return #err(e) }; case (#ok) {} };
    let item = switch (lookupLibraryItemActive(itemId)) {
      case (#err(e)) { auditErr(caller, act, null, e); return #err(e) };
      case (#ok(i)) i;
    };
    let newTags = switch (Library.validateTags(tags)) {
      case (#err(e)) { auditErr(caller, act, null, e); return #err(e) };
      case (#ok(t)) t;
    };
    MutMap.add(libraryItems, Nat.compare, itemId, { item with tags = newTags });
    auditOk(caller, act, null);
    #ok(())
  };

  // ── Firm Library — Item lifecycle ─────────────────────────────────────────
  // Archive/unarchive: Associate or higher. Delete: Partner only.

  public shared ({ caller }) func archiveLibraryItem(itemId : Nat) : async Result.Result<(), Text> {
    let act = "library.archive:" # Nat.toText(itemId);
    switch (Auth.requireAuthenticated(caller)) { case (#err(e)) { auditErr(caller, act, null, e); return #err(e) }; case (#ok) {} };
    switch (requireRole(caller, #Associate)) { case (#err(e)) { auditErr(caller, act, null, e); return #err(e) }; case (#ok) {} };
    let item = switch (lookupLibraryItemActive(itemId)) {
      case (#err(e)) { auditErr(caller, act, null, e); return #err(e) };
      case (#ok(i)) i;
    };
    MutMap.add(libraryItems, Nat.compare, itemId, { item with status = #Archived });
    auditOk(caller, act, null);
    #ok(())
  };

  public shared ({ caller }) func unarchiveLibraryItem(itemId : Nat) : async Result.Result<(), Text> {
    let act = "library.unarchive:" # Nat.toText(itemId);
    switch (Auth.requireAuthenticated(caller)) { case (#err(e)) { auditErr(caller, act, null, e); return #err(e) }; case (#ok) {} };
    switch (requireRole(caller, #Associate)) { case (#err(e)) { auditErr(caller, act, null, e); return #err(e) }; case (#ok) {} };
    switch (MutMap.get(libraryItems, Nat.compare, itemId)) {
      case null {
        let e = "library item " # Nat.toText(itemId) # " not found";
        auditErr(caller, act, null, e); return #err(e);
      };
      case (?item) {
        if (item.status != #Archived) {
          let e = "library item " # Nat.toText(itemId) # " is not archived";
          auditErr(caller, act, null, e); return #err(e);
        };
        MutMap.add(libraryItems, Nat.compare, itemId, { item with status = #Active });
      };
    };
    auditOk(caller, act, null);
    #ok(())
  };

  // Partner only; soft-delete only (bytes remain, no storage reclamation). SEC-INV-4.
  public shared ({ caller }) func deleteLibraryItem(itemId : Nat) : async Result.Result<(), Text> {
    let act = "library.delete:" # Nat.toText(itemId);
    switch (Auth.requireAuthenticated(caller)) { case (#err(e)) { auditErr(caller, act, null, e); return #err(e) }; case (#ok) {} };
    switch (requireRole(caller, #Partner)) { case (#err(e)) { auditErr(caller, act, null, e); return #err(e) }; case (#ok) {} };
    switch (MutMap.get(libraryItems, Nat.compare, itemId)) {
      case null {
        let e = "library item " # Nat.toText(itemId) # " not found";
        auditErr(caller, act, null, e); return #err(e);
      };
      case (?item) {
        if (item.status == #Deleted) {
          let e = "library item " # Nat.toText(itemId) # " is already deleted";
          auditErr(caller, act, null, e); return #err(e);
        };
        MutMap.add(libraryItems, Nat.compare, itemId, { item with status = #Deleted });
      };
    };
    auditOk(caller, act, null);
    #ok(())
  };

  // ── Firm Library — Download flow ──────────────────────────────────────────
  // UPDATE (not query) — must emit audit entry. Chunk bytes via getLibraryChunk query.
  // SEC-INV-15: #Active and #Archived allowed; #Deleted rejected.

  public shared ({ caller }) func prepareLibraryDownload(
    versionId : Nat
  ) : async Result.Result<{ itemId : Nat; versionId : Nat; chunkCount : Nat; contentType : Text; sizeBytes : Nat; filename : Text; sha256 : Blob }, Text> {
    switch (Auth.requireAuthenticated(caller)) { case (#err(e)) { auditErr(caller, "library.download:0:0", null, e); return #err(e) }; case (#ok) {} };
    switch (requireRole(caller, #Staff)) { case (#err(e)) { auditErr(caller, "library.download:0:0", null, e); return #err(e) }; case (#ok) {} };
    let version = switch (lookupLibraryVersion(versionId)) {
      case (#err(e)) { auditErr(caller, "library.download:0:0", null, e); return #err(e) };
      case (#ok(v)) v;
    };
    let item = switch (lookupLibraryItemReadable(version.itemId)) {
      case (#err(e)) { auditErr(caller, "library.download:0:" # Nat.toText(versionId), null, e); return #err(e) };
      case (#ok(i)) i;
    };
    let actStr = "library.download:" # Nat.toText(item.id) # ":" # Nat.toText(versionId);
    auditOk(caller, actStr, null);
    #ok({
      itemId = item.id; versionId;
      chunkCount = DocumentModule.expectedChunkCount(version.sizeBytes);
      contentType = version.contentType; sizeBytes = version.sizeBytes;
      filename = version.filename; sha256 = version.sha256;
    })
  };

  // ── L4 Update — export ───────────────────────────────────────────────────
  // SEC-INV-3 (L4): Partner role required. Operations principal has no user role
  //                 per L1, so requireRole fails — cannot export.
  // SEC-INV-4 (L4): exactly one audit entry per call (auditOk on success, auditErr on failure).
  // SEC-INV-5 (L4): read-only over all L1-L2b Maps; only side effect is the audit append.
  // SEC-INV-11 (L4): update call (not query) — required to emit the audit entry.

  public shared ({ caller }) func createExportManifest() : async Result.Result<ExportManifest, Text> {
    switch (Auth.requireAuthenticated(caller)) {
      case (#err(e)) { auditErr(caller, "createExportManifest", null, e); return #err(e) };
      case (#ok) {};
    };
    // SEC-INV-3 (L4): Partner only; operations principal has no user role per L1
    switch (requireRole(caller, #Partner)) {
      case (#err(e)) { auditErr(caller, "createExportManifest", null, e); return #err(e) };
      case (#ok) {};
    };
    let clientIds = Iter.toArray(
      Iter.map(MutMap.entries(clients), func((id, _) : (Nat, Client)) : Nat { id })
    );
    let matterIds = Iter.toArray(
      Iter.map(MutMap.entries(matters), func((id, _) : (Nat, Matter)) : Nat { id })
    );
    let docEntries = Iter.toArray(
      Iter.map(MutMap.entries(documents), func((id, _) : (Nat, Document)) : { documentId : Nat; versionIds : [Nat] } {
        let vids = switch (MutMap.get(versionsByDocument, Nat.compare, id)) {
          case null   [];
          case (?arr) arr;
        };
        { documentId = id; versionIds = vids }
      })
    );
    let userPrincipals = Iter.toArray(
      Iter.map(Map.entries(users), func((p, _) : (Principal, UserRecord)) : Principal { p })
    );
    // Firm Library fields (Phase 1.5)
    let allFolders = Iter.toArray(
      Iter.map(MutMap.entries(folders), func((_, f) : (Nat, Folder)) : Folder { f })
    );
    let libraryEntries = Iter.toArray(
      Iter.map(MutMap.entries(libraryItems), func((id, _) : (Nat, LibraryItem)) : { itemId : Nat; versionIds : [Nat] } {
        let vids = switch (MutMap.get(libraryVersionsByItem, Nat.compare, id)) {
          case null   [];
          case (?arr) arr;
        };
        { itemId = id; versionIds = vids }
      })
    );
    let totalLibraryVersions : Nat = Array.foldLeft<{ itemId : Nat; versionIds : [Nat] }, Nat>(
      libraryEntries, 0, func(acc, e) { acc + e.versionIds.size() }
    );
    let manifest : ExportManifest = {
      generatedAt           = Time.now();
      generatedBy           = caller;
      totalClients          = MutMap.size(clients);
      totalMatters          = MutMap.size(matters);
      totalDocuments        = MutMap.size(documents);
      totalVersions         = MutMap.size(documentVersions);
      totalFolders          = MutMap.size(folders);
      totalLibraryItems     = MutMap.size(libraryItems);
      totalLibraryVersions;
      totalAuditEntries     = nextAuditId - 1;  // nextAuditId is 1-indexed; -1 gives count
      storageUsedBytes      = totalStorageUsedBytes;
      storageBudgetBytes    = storageBudgetBytes;
      masterController      = masterController;
      operationsPrincipal   = operationsPrincipal;
      clientIds;
      matterIds;
      documents             = docEntries;
      folders               = allFolders;
      libraryItems          = libraryEntries;
      userPrincipals;
    };
    auditOk(caller, "createExportManifest", null);
    #ok(manifest)
  };

  // ── Firm Library private helpers ─────────────────────────────────────────
  // All are stateful (close over actor Maps); stateless helpers live in Library.mo.

  // Lookup folder by ID; #err if not found.
  func lookupFolder(id : Nat) : Result.Result<Folder, Text> {
    switch (MutMap.get(folders, Nat.compare, id)) {
      case null #err("folder " # Nat.toText(id) # " not found");
      case (?f) #ok(f);
    };
  };

  // Walk parent chain upward: depth 1 = root-level folder (parentId = null).
  func computeFolderDepth(folderId : Nat) : Nat {
    switch (MutMap.get(folders, Nat.compare, folderId)) {
      case null 0;
      case (?f) switch (f.parentId) {
        case null 1;
        case (?pid) 1 + computeFolderDepth(pid);
      };
    };
  };

  // True if candidateId is folderId or any descendant (used for cycle detection). SEC-INV-12.
  func subtreeContains(rootId : Nat, candidateId : Nat) : Bool {
    if (rootId == candidateId) return true;
    for ((_, f) in MutMap.entries(folders)) {
      switch (f.parentId) {
        case (?pid) {
          if (pid == rootId and subtreeContains(f.id, candidateId)) return true;
        };
        case null {};
      };
    };
    false
  };

  // Max depth of descendants below folderId (0 = leaf). Used for depth-on-move check.
  func subtreeDepth(folderId : Nat) : Nat {
    var maxChildDepth : Nat = 0;
    for ((_, f) in MutMap.entries(folders)) {
      switch (f.parentId) {
        case (?pid) {
          if (pid == folderId) {
            let d = 1 + subtreeDepth(f.id);
            if (d > maxChildDepth) maxChildDepth := d;
          };
        };
        case null {};
      };
    };
    maxChildDepth
  };

  // SEC-INV-13: reject folder delete if any child folder or any item (any status) references it.
  func folderHasDependents(folderId : Nat) : ?Text {
    var childFolders : Nat = 0;
    var childItems : Nat = 0;
    for ((_, f) in MutMap.entries(folders)) {
      switch (f.parentId) {
        case (?pid) if (pid == folderId) childFolders += 1;
        case null {};
      };
    };
    for ((_, item) in MutMap.entries(libraryItems)) {
      switch (item.folderId) {
        case (?fid) if (fid == folderId) childItems += 1;
        case null {};
      };
    };
    if (childFolders == 0 and childItems == 0) null
    else {
      let msg = if (childFolders > 0 and childItems > 0) {
        Nat.toText(childFolders) # " child folder(s), " # Nat.toText(childItems) # " item(s)"
      } else if (childFolders > 0) {
        Nat.toText(childFolders) # " child folder(s)"
      } else {
        Nat.toText(childItems) # " item(s)"
      };
      ?msg
    }
  };

  // Item exists AND status #Active.
  func lookupLibraryItemActive(id : Nat) : Result.Result<LibraryItem, Text> {
    switch (MutMap.get(libraryItems, Nat.compare, id)) {
      case null #err("library item " # Nat.toText(id) # " not found");
      case (?item) {
        if (item.status != #Active) #err("library item " # Nat.toText(id) # " is not active")
        else #ok(item)
      };
    };
  };

  // Item exists AND status #Active or #Archived (allows download of archived items). SEC-INV-15.
  func lookupLibraryItemReadable(id : Nat) : Result.Result<LibraryItem, Text> {
    switch (MutMap.get(libraryItems, Nat.compare, id)) {
      case null #err("library item " # Nat.toText(id) # " not found");
      case (?item) {
        if (item.status == #Deleted) #err("library item " # Nat.toText(id) # " is deleted")
        else #ok(item)
      };
    };
  };

  // Library version exists.
  func lookupLibraryVersion(id : Nat) : Result.Result<LibraryVersion, Text> {
    switch (MutMap.get(libraryVersions, Nat.compare, id)) {
      case null #err("library version " # Nat.toText(id) # " not found");
      case (?v) #ok(v);
    };
  };

  // SEC-INV-6: shared budget check with L2b (Q8).
  func validateLibraryBudgetAvailable(sizeBytes : Nat) : Result.Result<(), Text> {
    if (totalStorageUsedBytes + sizeBytes > storageBudgetBytes) {
      let available = if (storageBudgetBytes >= totalStorageUsedBytes) storageBudgetBytes - totalStorageUsedBytes else 0;
      #err("storage budget exceeded: need " # Nat.toText(sizeBytes) # " bytes, only " # Nat.toText(available) # " available")
    } else #ok(())
  };

  // Resolve FolderScope membership for an item. Subtree walk uses actor state. SEC-INV-22.
  func evaluateFolderScope(item : LibraryItem, scope : FolderScope) : Bool {
    switch scope {
      case (#Any) true;
      case (#Root) item.folderId == null;
      case (#Folder fid) item.folderId == ?fid;
      case (#Subtree rid) {
        switch (item.folderId) {
          case null false;
          case (?fid) subtreeContains(rid, fid);
        };
      };
    };
  };

  // Append versionId to libraryVersionsByItem[itemId]; initialise list if absent.
  func appendVersionToLibraryItem(itemId : Nat, versionId : Nat) : () {
    let existing : [Nat] = switch (MutMap.get(libraryVersionsByItem, Nat.compare, itemId)) {
      case null [];
      case (?arr) arr;
    };
    MutMap.add(libraryVersionsByItem, Nat.compare, itemId, Array.concat<Nat>(existing, [versionId]));
  };

  // Internal search: shared by searchLibrary and listLibraryItems. SEC-INV-19: limit ≤ 1000.
  func doSearchLibrary(filter : LibraryFilter, after : Nat, limit : Nat) : [LibraryItemSearchResult] {
    let cap = if (limit > 1000) 1000 else limit;
    let base = MutMap.entriesFrom(libraryItems, Nat.compare, after + 1);
    let matched = Iter.filterMap<(Nat, LibraryItem), LibraryItemSearchResult>(base,
      func((_, item) : (Nat, LibraryItem)) : ?LibraryItemSearchResult {
        let isInScope = evaluateFolderScope(item, filter.folderScope);
        switch (MutMap.get(libraryVersions, Nat.compare, item.currentVersionId)) {
          case null null;
          case (?v) {
            if (Library.matchesLibraryFilter(item, v, filter, isInScope))
              ?{ item; currentVersion = Library.stripBlobFromLibraryVersion(v) }
            else null
          };
        };
      }
    );
    Iter.toArray(Iter.take(matched, cap))
  };

  // ── Admin / Cycle Management ──────────────────────────────────────────────
  // SEC-INV: createTopUpRequest/cancelTopUpRequest → master controller only.
  //          fulfillTopUpRequest → operations principal only.
  //          getTopUpRequest/listTopUpRequests → master OR ops (query, trap on auth failure).
  //          getCycleBalance → public query, no auth check (balance is public on-chain anyway).

  public shared ({ caller }) func createTopUpRequest(amountT : Nat, note : Text) : async Result.Result<Nat, Text> {
    switch (Auth.requireAuthenticated(caller)) { case (#err(e)) { auditErr(caller, "topUpRequest.create", null, e); return #err(e) }; case (#ok) {} };
    switch (Auth.requireMasterController(caller, masterController)) { case (#err(e)) { auditErr(caller, "topUpRequest.create", null, e); return #err(e) }; case (#ok) {} };
    if (amountT < MIN_TOPUP_T_CYCLES or amountT > MAX_TOPUP_T_CYCLES) {
      let e = "requestedTrillionCycles must be between " # Nat.toText(MIN_TOPUP_T_CYCLES) # " and " # Nat.toText(MAX_TOPUP_T_CYCLES);
      auditErr(caller, "topUpRequest.create", null, e);
      return #err(e);
    };
    if (note.size() > MAX_TOPUP_NOTE_LENGTH) {
      let e = "note exceeds maximum length of " # Nat.toText(MAX_TOPUP_NOTE_LENGTH) # " characters";
      auditErr(caller, "topUpRequest.create", null, e);
      return #err(e);
    };
    let id = nextTopUpRequestId;
    nextTopUpRequestId += 1;
    MutMap.add(topUpRequests, Nat.compare, id, {
      id;
      requestedTrillionCycles = amountT;
      note;
      status = #Pending;
      createdAt = Time.now();
      createdBy = caller;
      fulfilledAt = null;
      fulfilledBy = null;
      cancelledAt = null;
      cancelledBy = null;
    });
    auditOk(caller, "topUpRequest.create", null);
    #ok(id)
  };

  public shared ({ caller }) func cancelTopUpRequest(id : Nat) : async Result.Result<(), Text> {
    switch (Auth.requireAuthenticated(caller)) { case (#err(e)) { auditErr(caller, "topUpRequest.cancel", null, e); return #err(e) }; case (#ok) {} };
    switch (Auth.requireMasterController(caller, masterController)) { case (#err(e)) { auditErr(caller, "topUpRequest.cancel", null, e); return #err(e) }; case (#ok) {} };
    let req = switch (MutMap.get(topUpRequests, Nat.compare, id)) {
      case null {
        let e = "top-up request " # Nat.toText(id) # " not found";
        auditErr(caller, "topUpRequest.cancel", null, e); return #err(e);
      };
      case (?r) r;
    };
    if (req.status != #Pending) {
      let e = "request is not pending";
      auditErr(caller, "topUpRequest.cancel", null, e); return #err(e);
    };
    MutMap.add(topUpRequests, Nat.compare, id, {
      req with
      status = #Cancelled;
      cancelledAt = ?Time.now();
      cancelledBy = ?caller;
    });
    auditOk(caller, "topUpRequest.cancel", null);
    #ok(())
  };

  public shared ({ caller }) func fulfillTopUpRequest(id : Nat) : async Result.Result<(), Text> {
    switch (Auth.requireAuthenticated(caller)) { case (#err(e)) { auditErr(caller, "topUpRequest.fulfill", null, e); return #err(e) }; case (#ok) {} };
    switch (requireOperationsPrincipal(caller)) { case (#err(e)) { auditErr(caller, "topUpRequest.fulfill", null, e); return #err(e) }; case (#ok) {} };
    let req = switch (MutMap.get(topUpRequests, Nat.compare, id)) {
      case null {
        let e = "top-up request " # Nat.toText(id) # " not found";
        auditErr(caller, "topUpRequest.fulfill", null, e); return #err(e);
      };
      case (?r) r;
    };
    if (req.status != #Pending) {
      let e = "request is not pending";
      auditErr(caller, "topUpRequest.fulfill", null, e); return #err(e);
    };
    MutMap.add(topUpRequests, Nat.compare, id, {
      req with
      status = #Fulfilled;
      fulfilledAt = ?Time.now();
      fulfilledBy = ?caller;
    });
    auditOk(caller, "topUpRequest.fulfill", null);
    #ok(())
  };

  public query ({ caller }) func getTopUpRequest(id : Nat) : async ?TopUpRequestRecord {
    switch (Auth.requireAuthenticated(caller)) { case (#err(_)) assert false; case (#ok) {} };
    switch (requireOperationsOrMaster(caller)) { case (#err(_)) assert false; case (#ok) {} };
    MutMap.get(topUpRequests, Nat.compare, id)
  };

  public query ({ caller }) func listTopUpRequests(statusFilter : ?TopUpRequestStatus) : async [TopUpRequestRecord] {
    switch (Auth.requireAuthenticated(caller)) { case (#err(_)) assert false; case (#ok) {} };
    switch (requireOperationsOrMaster(caller)) { case (#err(_)) assert false; case (#ok) {} };
    Iter.toArray(Iter.map(
      Iter.filter(MutMap.entries(topUpRequests), func((_, r) : (Nat, TopUpRequestRecord)) : Bool {
        switch (statusFilter) {
          case null true;
          case (?s) r.status == s;
        }
      }),
      func((_, r) : (Nat, TopUpRequestRecord)) : TopUpRequestRecord { r }
    ))
  };

  public query func getCycleBalance() : async Nat {
    Cycles.balance()
  };

  // ── L5 Audit read ─────────────────────────────────────────────────────────
  // SEC-INV-1: this is the only method that reads auditLog — no dump/count/oldest endpoint.
  // SEC-INV-4: every call to readAuditEntries is itself audited (update, not query).
  // SEC-INV-5: Partner-only — role check enforced inside the method body.
  // SEC-INV-8: no canister_inspect_message boundary.
  // SEC-INV-9: auditLog is not exposed by any other public method.
  public shared ({ caller }) func readAuditEntries(after : Nat, limit : Nat) : async Result.Result<[AuditEntry], Text> {
    switch (Auth.requireAuthenticated(caller)) {
      case (#err(e)) { auditErr(caller, "readAuditEntries", null, e); return #err(e) };
      case (#ok) {};
    };
    switch (requireRole(caller, #Partner)) { // SEC-INV-5
      case (#err(_)) {
        // SEC-INV-4: auth failure is itself audited before returning
        auditErr(caller, "readAuditEntries", null, "not authorized");
        return #err("not authorized")
      };
      case (#ok) {};
    };
    // SEC-INV-4: emit this call's entry BEFORE collecting, so it appears as the last
    // entry in the results — proving the meta-trust property (watchers are watched).
    auditOk(caller, "readAuditEntries", null);
    let cap = if (limit > 1000) 1000 else limit; // Q7: cursor pagination, max 1000
    // SEC-INV-6: entriesFrom starts at after+1 (exclusive lower bound = id > after)
    let iter = MutMap.entriesFrom(auditLog, Nat.compare, after + 1);
    let results = Iter.toArray(
      Iter.map(
        Iter.take(iter, cap),
        func(kv : (Nat, AuditEntry)) : AuditEntry { kv.1 }
      )
    );
    #ok(results)
  };
};
