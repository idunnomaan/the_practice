import Time "mo:core/Time";
import Text "mo:core/Text";
import Principal "mo:core/Principal";
import ClientModule "./Client";
import MatterModule "./Matter";
import DocumentModule "./Document";

module {

  // ── Filter types ──────────────────────────────────────────────────────────

  public type ClientFilter = {
    nameContains : ?Text;
    clientType : ?ClientModule.ClientType;
    statusFilter : ?ClientModule.ClientStatus;  // null → #Active only (spec §2 default)
    identifierContains : ?Text;
    createdAfter : ?Time.Time;
    createdBefore : ?Time.Time;
  };

  public type MatterFilter = {
    titleContains : ?Text;
    matterTypeContains : ?Text;
    clientId : ?Nat;
    assignedPartner : ?Principal;
    statusFilter : ?MatterModule.MatterStatus;  // null → all except #Archived
    openedAfter : ?Time.Time;
    openedBefore : ?Time.Time;
    closedAfter : ?Time.Time;
    closedBefore : ?Time.Time;
  };

  public type DocumentFilter = {
    filenameContains : ?Text;
    contentType : ?Text;                            // exact match (whitelist value)
    matterId : ?Nat;
    statusFilter : ?DocumentModule.DocumentStatus;  // null → #Active only
    uploadedAfter : ?Time.Time;
    uploadedBefore : ?Time.Time;
    uploadedBy : ?Principal;
  };

  // ── Search result types ───────────────────────────────────────────────────

  public type DocumentSearchResult = {
    document : DocumentModule.Document;
    currentVersion : DocumentModule.DocumentVersion;  // blob stripped to empty Blob
  };

  // ── Dashboard count types ─────────────────────────────────────────────────

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

  // ── Stateless match helpers ───────────────────────────────────────────────

  // Case-insensitive substring check.
  // Uses Text.toLower — mo:core 2.3.1 does NOT export Text.toLowercase; the
  // correct function name is Text.toLower (bound to Prim.textLowercase).
  public func containsCI(haystack : Text, needle : Text) : Bool {
    let lh = Text.toLower(haystack);
    let ln = Text.toLower(needle);
    Text.contains(lh, #text ln)
  };

  // True if t is strictly within (after, before); null bound = unbounded on that side.
  public func inTimeRange(t : Time.Time, after : ?Time.Time, before : ?Time.Time) : Bool {
    let afterOk = switch after { case null true; case (?a) t > a };
    let beforeOk = switch before { case null true; case (?b) t < b };
    afterOk and beforeOk
  };

  // SEC-INV-8 (L4): all non-null fields AND together; default statusFilter = #Active only.
  public func matchesClientFilter(c : ClientModule.Client, f : ClientFilter) : Bool {
    let statusOk = switch (f.statusFilter) {
      case null    c.status == #Active;
      case (?s)    c.status == s;
    };
    if (not statusOk) return false;

    switch (f.nameContains) {
      case (?n) if (not containsCI(c.name, n)) return false;
      case null {};
    };

    switch (f.clientType) {
      case (?ct) if (c.clientType != ct) return false;
      case null  {};
    };

    switch (f.identifierContains) {
      case (?id) {
        switch (c.identifier) {
          case null     return false;
          case (?cid)   if (not containsCI(cid, id)) return false;
        };
      };
      case null {};
    };

    if (not inTimeRange(c.createdAt, f.createdAfter, f.createdBefore)) return false;

    true
  };

  // SEC-INV-8 (L4): all non-null fields AND together; default statusFilter excludes #Archived.
  public func matchesMatterFilter(m : MatterModule.Matter, f : MatterFilter) : Bool {
    let statusOk = switch (f.statusFilter) {
      case null   m.status != #Archived;
      case (?s)   m.status == s;
    };
    if (not statusOk) return false;

    switch (f.titleContains) {
      case (?t) if (not containsCI(m.title, t)) return false;
      case null {};
    };

    switch (f.matterTypeContains) {
      case (?mt) if (not containsCI(m.matterType, mt)) return false;
      case null  {};
    };

    switch (f.clientId) {
      case (?cid) if (m.clientId != cid) return false;
      case null   {};
    };

    switch (f.assignedPartner) {
      case (?p) {
        switch (m.assignedPartner) {
          case null     return false;
          case (?ap)    if (ap != p) return false;
        };
      };
      case null {};
    };

    if (not inTimeRange(m.openedAt, f.openedAfter, f.openedBefore)) return false;

    // closedAt filters: if either bound is set, exclude matters with no closedAt
    switch (f.closedAfter, f.closedBefore) {
      case (null, null) {};
      case _ {
        switch (m.closedAt) {
          case null    return false;
          case (?cat)  if (not inTimeRange(cat, f.closedAfter, f.closedBefore)) return false;
        };
      };
    };

    true
  };

  // SEC-INV-9 (L4): matches against current version only — never searches historical versions.
  // A document whose current version does not match the filter is excluded even if an older
  // version would have matched. Filters apply across both Document and DocumentVersion fields.
  public func matchesDocumentFilter(
    d : DocumentModule.Document,
    v : DocumentModule.DocumentVersion,
    f : DocumentFilter
  ) : Bool {
    let statusOk = switch (f.statusFilter) {
      case null   d.status == #Active;
      case (?s)   d.status == s;
    };
    if (not statusOk) return false;

    switch (f.matterId) {
      case (?mid) if (d.matterId != mid) return false;
      case null   {};
    };

    switch (f.filenameContains) {
      case (?fn) if (not containsCI(v.filename, fn)) return false;
      case null  {};
    };

    switch (f.contentType) {
      case (?ct) if (v.contentType != ct) return false;
      case null  {};
    };

    switch (f.uploadedBy) {
      case (?p) if (v.uploadedBy != p) return false;
      case null {};
    };

    if (not inTimeRange(v.uploadedAt, f.uploadedAfter, f.uploadedBefore)) return false;

    true
  };

};
