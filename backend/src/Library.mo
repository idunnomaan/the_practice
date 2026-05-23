import Text "mo:core/Text";
import Result "mo:core/Result";
import Array "mo:core/Array";
import Nat "mo:core/Nat";
import Time "mo:core/Time";
import Map "mo:core/pure/Map";

module {

  // ── Constants ─────────────────────────────────────────────────────────────
  // Library reuses DocumentModule.CHUNK_SIZE (1 MB) — do not redeclare here.
  public let MAX_LIBRARY_ITEM_SIZE : Nat = 5_368_709_120;   // 5 GiB (Q9 — per-item ceiling)
  public let MAX_LIBRARY_TAGS : Nat = 20;                    // SEC-INV-9
  public let MAX_LIBRARY_TAG_LENGTH : Nat = 64;
  public let MAX_LIBRARY_NAME_LENGTH : Nat = 256;
  public let MAX_LIBRARY_DESCRIPTION_LENGTH : Nat = 1024;
  public let MAX_LIBRARY_CONTENT_TYPE_LENGTH : Nat = 127;
  public let MAX_FOLDER_DEPTH : Nat = 5;                     // SEC-INV-11
  public let MAX_FOLDER_NAME_LENGTH : Nat = 128;             // SEC-INV-10

  // ── Types ──────────────────────────────────────────────────────────────────

  // Q11: three states — Active (default), Archived (hidden from default lists),
  //      Deleted (soft-deleted; surfaced only via explicit statusFilter).
  public type LibraryItemStatus = {
    #Active;
    #Archived;
    #Deleted;
  };

  // §3.2 — primary navigation entity; depth cap = MAX_FOLDER_DEPTH (SEC-INV-11).
  public type Folder = {
    id : Nat;
    name : Text;
    parentId : ?Nat;                 // null = root level; ?id = nested
    createdAt : Time.Time;
    createdBy : Principal;
  };

  // §3.3 — firm-owned item, not matter-scoped (Q1/Q2).
  // name: user-supplied label, mutable via renameLibraryItem.
  // tags: normalized (lowercased, deduped, ≤ MAX_LIBRARY_TAGS).
  public type LibraryItem = {
    id : Nat;
    name : Text;
    folderId : ?Nat;                 // null = root level
    tags : [Text];
    description : Text;
    currentVersionId : Nat;
    status : LibraryItemStatus;
    createdAt : Time.Time;
    createdBy : Principal;
  };

  // §3.4 — versioned; blob holds the full binary. Stripped in search results.
  public type LibraryVersion = {
    versionId : Nat;
    itemId : Nat;
    versionNumber : Nat;
    filename : Text;
    contentType : Text;
    sizeBytes : Nat;
    blob : Blob;
    sha256 : Blob;
    uploadedAt : Time.Time;
    uploadedBy : Principal;
    uploadNotes : Text;
  };

  // §3.5 — transient; deleted on finalize or abandon (Q10).
  // chunks: pure Map updated via session record replacement (same pattern as L2b).
  public type LibraryUploadSession = {
    sessionId : Nat;
    name : Text;                     // for new items; ignored on replacesItemId path
    folderId : ?Nat;
    tags : [Text];
    description : Text;
    filename : Text;
    contentType : Text;
    totalSizeBytes : Nat;
    expectedChunkCount : Nat;
    uploadNotes : Text;
    replacesItemId : ?Nat;           // null = new item; ?id = new version of existing
    chunks : Map.Map<Nat, Blob>;
    startedAt : Time.Time;
    startedBy : Principal;           // caller-locked (SEC-INV-5)
  };

  // §3.6.1 — discriminated union replacing two ?Nat fields.
  // #Any: no folder filter; #Root: folderId == null; #Folder id: exact;
  // #Subtree id: item is in this folder or any descendant.
  public type FolderScope = {
    #Any;
    #Root;
    #Folder : Nat;
    #Subtree : Nat;
  };

  // §3.6 — all fields optional; null means "no filter on this dimension".
  // folderScope replaces folderId/?folderIdRecursive per locked §3.6.1 decision.
  public type LibraryFilter = {
    nameContains : ?Text;
    currentFilenameContains : ?Text;
    folderScope : FolderScope;
    tagsContainsAny : ?[Text];
    contentType : ?Text;
    statusFilter : ?LibraryItemStatus;
    uploadedAfter : ?Time.Time;
    uploadedBefore : ?Time.Time;
    uploadedBy : ?Principal;
  };

  public type LibraryItemSearchResult = {
    item : LibraryItem;
    currentVersion : LibraryVersion;  // blob stripped to empty Blob (SEC-INV-21)
  };

  public type FolderListing = {
    folders : [Folder];
    items : [LibraryItemSearchResult];
  };

  // ── Stateless helpers ─────────────────────────────────────────────────────

  // SEC-INV-8: non-empty, has '/', ≤ MAX_LIBRARY_CONTENT_TYPE_LENGTH.
  // No whitelist — audio/video types are too numerous (derived §2 + Q3).
  public func validateContentType(ct : Text) : Result.Result<(), Text> {
    if (ct == "") return #err("contentType must not be empty");
    if (ct.size() > MAX_LIBRARY_CONTENT_TYPE_LENGTH) {
      return #err("contentType too long: max " # Nat.toText(MAX_LIBRARY_CONTENT_TYPE_LENGTH) # " chars")
    };
    if (not Text.contains(ct, #char '/')) return #err("contentType must contain '/'");
    #ok(())
  };

  // SEC-INV-9: trim → lowercase → validate non-empty, no '/' or ',', ≤ MAX_LIBRARY_TAG_LENGTH.
  public func normalizeTag(t : Text) : Result.Result<Text, Text> {
    let trimmed = Text.trim(t, #predicate(func(c : Char) : Bool {
      c == ' ' or c == '\t' or c == '\n' or c == '\r'
    }));
    if (trimmed == "") return #err("tag must not be empty after trimming");
    let lower = Text.toLower(trimmed);
    if (lower.size() > MAX_LIBRARY_TAG_LENGTH) {
      return #err("tag too long: max " # Nat.toText(MAX_LIBRARY_TAG_LENGTH) # " chars")
    };
    if (Text.contains(lower, #char '/')) return #err("tag must not contain '/'");
    if (Text.contains(lower, #char ',')) return #err("tag must not contain ','");
    #ok(lower)
  };

  // SEC-INV-9: normalise + dedup + validate count ≤ MAX_LIBRARY_TAGS.
  public func validateTags(tags : [Text]) : Result.Result<[Text], Text> {
    if (tags.size() > MAX_LIBRARY_TAGS) {
      return #err("too many tags: max " # Nat.toText(MAX_LIBRARY_TAGS))
    };
    var normalized : [Text] = [];
    for (t in tags.vals()) {
      switch (normalizeTag(t)) {
        case (#err(e)) return #err(e);
        case (#ok(nt)) {
          // dedup: O(n²), fine since n ≤ 20
          var dup = false;
          for (existing in normalized.vals()) {
            if (existing == nt) { dup := true };
          };
          if (not dup) {
            normalized := Array.concat<Text>(normalized, [nt]);
          };
        };
      };
    };
    #ok(normalized)
  };

  // SEC-INV-10: non-empty after trim, ≤ MAX_FOLDER_NAME_LENGTH (128).
  public func validateFolderName(name : Text) : Result.Result<(), Text> {
    let trimmed = Text.trim(name, #predicate(func(c : Char) : Bool {
      c == ' ' or c == '\t' or c == '\n' or c == '\r'
    }));
    if (trimmed == "") return #err("folder name must not be empty");
    if (trimmed.size() > MAX_FOLDER_NAME_LENGTH) {
      return #err("folder name too long: max " # Nat.toText(MAX_FOLDER_NAME_LENGTH) # " chars")
    };
    #ok(())
  };

  // All non-null filter fields AND together. folderScope membership is pre-evaluated
  // by the actor (subtree walk needs actor state) and passed as isInScope : Bool.
  // tagsContainsAny: item must have ≥ 1 matching tag (OR within that field, AND with rest).
  // Default statusFilter (null) returns only #Active items.
  public func matchesLibraryFilter(
    item : LibraryItem,
    currentVersion : LibraryVersion,
    filter : LibraryFilter,
    isInScope : Bool           // pre-computed by evaluateFolderScope on actor
  ) : Bool {
    // SEC-INV-22: folder scope evaluated by caller
    if (not isInScope) return false;

    // Status: default = #Active only
    let statusOk = switch (filter.statusFilter) {
      case null   item.status == #Active;
      case (?s)   item.status == s;
    };
    if (not statusOk) return false;

    // nameContains: case-insensitive substring on item.name
    switch (filter.nameContains) {
      case (?n) {
        let lhName = Text.toLower(item.name);
        let lnName = Text.toLower(n);
        if (not Text.contains(lhName, #text lnName)) return false;
      };
      case null {};
    };

    // currentFilenameContains: case-insensitive on currentVersion.filename
    switch (filter.currentFilenameContains) {
      case (?fn) {
        let lhFile = Text.toLower(currentVersion.filename);
        let lnFile = Text.toLower(fn);
        if (not Text.contains(lhFile, #text lnFile)) return false;
      };
      case null {};
    };

    // tagsContainsAny: item.tags intersects filter tags (any-match)
    switch (filter.tagsContainsAny) {
      case null {};
      case (?filterTags) {
        var found = false;
        label tagSearch for (ft in filterTags.vals()) {
          let normFt = Text.toLower(ft);
          for (it in item.tags.vals()) {
            if (it == normFt) { found := true; break tagSearch };
          };
        };
        if (not found) return false;
      };
    };

    // contentType: exact match on currentVersion.contentType
    switch (filter.contentType) {
      case (?ct) if (currentVersion.contentType != ct) return false;
      case null {};
    };

    // uploadedBy: exact principal match
    switch (filter.uploadedBy) {
      case (?p) if (currentVersion.uploadedBy != p) return false;
      case null {};
    };

    // Time range: uploadedAt of current version (exclusive bounds, matching L4 pattern)
    switch (filter.uploadedAfter) {
      case (?a) if (currentVersion.uploadedAt <= a) return false;
      case null {};
    };
    switch (filter.uploadedBefore) {
      case (?b) if (currentVersion.uploadedAt >= b) return false;
      case null {};
    };

    true
  };

  // Strip blob — keeps metadata, clears binary payload.
  // Used in search results, listLibraryVersions, listFolderContents to avoid heap pressure.
  public func stripBlobFromLibraryVersion(v : LibraryVersion) : LibraryVersion {
    { v with blob = "" }
  };

};
