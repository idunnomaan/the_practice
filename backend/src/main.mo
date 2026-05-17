import Principal "mo:core/Principal";
import Map "mo:core/pure/Map";
import MutMap "mo:core/Map";
import Nat "mo:core/Nat";
import Text "mo:core/Text";
import Time "mo:core/Time";
import Iter "mo:core/Iter";
import Result "mo:core/Result";
import Types "./Types";
import Auth "./Auth";
import Audit "./Audit";
import ClientModule "./Client";
import MatterModule "./Matter";

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

  // INV-1: anonymous principal cannot hold any identity — trap at install if anonymous
  assert not Principal.isAnonymous(masterControllerArg);

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
