import Time "mo:core/Time";

module {
  // Outcome of an auditable action.
  public type AuditOutcome = {
    #ok;
    #err : Text;
  };

  // Immutable record written once into the append-only ledger.
  public type AuditEntry = {
    id : Nat;              // monotonically increasing; starts at 1
    timestamp : Time.Time; // nanoseconds since epoch — Time.now() only (SEC-INV-7)
    caller : Principal;    // who initiated the action
    action : Text;         // method name, e.g. "grantOperations"
    target : ?Principal;   // principal acted upon, if any
    outcome : AuditOutcome;
  };
};
