import Time "mo:core/Time";
import Principal "mo:core/Principal";

module {
  public type TopUpRequestStatus = {
    #Pending;
    #Fulfilled;
    #Cancelled;
  };

  public type TopUpRequest = {
    id : Nat;
    requestedTrillionCycles : Nat;
    note : Text;
    status : TopUpRequestStatus;
    createdAt : Time.Time;
    createdBy : Principal;
    fulfilledAt : ?Time.Time;
    fulfilledBy : ?Principal;
    cancelledAt : ?Time.Time;
    cancelledBy : ?Principal;
  };
};
