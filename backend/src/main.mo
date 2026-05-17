import Principal "mo:core/Principal";
import Map "mo:core/pure/Map";
import MutMap "mo:core/Map";
import Nat "mo:core/Nat";
import Time "mo:core/Time";
import Iter "mo:core/Iter";
import Result "mo:core/Result";
import Types "./Types";
import Auth "./Auth";
import Audit "./Audit";

shared(installer) persistent actor class ThePractice(
  masterControllerArg : Principal
) = this {

  type Role = Types.Role;
  type UserRecord = Types.UserRecord;
  type AuditEntry = Audit.AuditEntry;

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
