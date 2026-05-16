import Principal "mo:core/Principal";
import Map "mo:core/pure/Map";
import Time "mo:core/Time";
import Iter "mo:core/Iter";
import Types "./Types";
import Auth "./Auth";

shared(installer) persistent actor class ThePractice(
  masterControllerArg : Principal
) = this {

  type Role = Types.Role;
  type UserRecord = Types.UserRecord;

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

  // Stub — body replaced when L5 lands; callers do not change
  func audit(_actor : Principal, _action : Text, _target : ?Principal) {
    // TODO L5: wire to audit log
  };

  // INV-4: suspension blocks role checks for any role, even Partner.
  // Closes over actor-state `users`; not in Auth.mo to avoid exposing Map.Map.
  func requireRole(caller : Principal, minRole : Role) {
    switch (Map.get(users, Principal.compare, caller)) {
      case (?record) {
        assert not record.suspended;
        assert Auth.roleRank(record.role) >= Auth.roleRank(minRole);
      };
      case null { assert false }; // not registered
    };
  };

  // ── Queries ──────────────────────────────────────────────────────────────
  // INV-6: no canister_inspect_message boundary — all checks are inside method bodies.

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
    requireRole(caller, #Partner);
    Map.size(users);
  };

  public query ({ caller }) func listUsers() : async [(Principal, UserRecord)] {
    requireRole(caller, #Partner);
    Iter.toArray(Map.entries(users));
  };

  // ── Updates ──────────────────────────────────────────────────────────────
  // Every update: (1) reject anonymous, (2) role/controller check, (3) audit before return.

  public shared ({ caller }) func grantOperations(p : Principal) : async () {
    Auth.requireAuthenticated(caller);
    Auth.requireMasterController(caller, masterController);
    assert not Principal.isAnonymous(p);            // INV-1
    assert p != masterController;
    assert Map.get(users, Principal.compare, p) == null; // INV-3: ops never in users registry
    assert operationsPrincipal == null;             // must revoke first
    operationsPrincipal := ?p;
    audit(caller, "grantOperations", ?p);
  };

  public shared ({ caller }) func revokeOperations() : async () {
    Auth.requireAuthenticated(caller);
    Auth.requireMasterController(caller, masterController);
    operationsPrincipal := null; // idempotent
    audit(caller, "revokeOperations", null);
  };

  public shared ({ caller }) func transferMasterController(p : Principal) : async () {
    Auth.requireAuthenticated(caller);
    Auth.requireMasterController(caller, masterController);
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
    audit(caller, "transferMasterController", ?p);
  };

  public shared ({ caller }) func addUser(p : Principal, role : Role) : async () {
    Auth.requireAuthenticated(caller);
    requireRole(caller, #Partner);
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
    audit(caller, "addUser", ?p);
  };

  public shared ({ caller }) func setUserRole(p : Principal, role : Role) : async () {
    Auth.requireAuthenticated(caller);
    requireRole(caller, #Partner);
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
    audit(caller, "setUserRole", ?p);
  };

  public shared ({ caller }) func suspendUser(p : Principal) : async () {
    Auth.requireAuthenticated(caller);
    requireRole(caller, #Partner);
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
    audit(caller, "suspendUser", ?p);
  };

  public shared ({ caller }) func unsuspendUser(p : Principal) : async () {
    Auth.requireAuthenticated(caller);
    requireRole(caller, #Partner);
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
    audit(caller, "unsuspendUser", ?p);
  };

  public shared ({ caller }) func removeUser(p : Principal) : async () {
    Auth.requireAuthenticated(caller);
    requireRole(caller, #Partner);
    assert p != masterController;                   // cannot remove master controller (must transfer first)
    users := Map.remove(users, Principal.compare, p);
    audit(caller, "removeUser", ?p);
  };
};
