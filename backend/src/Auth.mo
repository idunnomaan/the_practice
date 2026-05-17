import Principal "mo:core/Principal";
import Result "mo:core/Result";
import Types "./Types";

module {
  type Role = Types.Role;

  // INV-1: anonymous principal cannot hold any identity
  public func requireAuthenticated(caller : Principal) : Result.Result<(), Text> {
    if (Principal.isAnonymous(caller)) #err("anonymous caller not allowed")
    else #ok(())
  };

  public func requireMasterController(caller : Principal, master : Principal) : Result.Result<(), Text> {
    if (caller != master) #err("not authorized")
    else #ok(())
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
