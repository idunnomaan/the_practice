import Principal "mo:core/Principal";
import Types "./Types";

module {
  type Role = Types.Role;

  // INV-1: anonymous principal cannot hold any identity
  public func requireAuthenticated(caller : Principal) {
    assert not Principal.isAnonymous(caller);
  };

  public func requireMasterController(caller : Principal, master : Principal) {
    assert caller == master;
  };

  // Partner ⊃ Associate ⊃ Staff hierarchy (Q3)
  public func roleRank(role : Role) : Nat {
    switch role {
      case (#Partner) 2;
      case (#Associate) 1;
      case (#Staff) 0;
    };
  };
};
