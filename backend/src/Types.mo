import Time "mo:core/Time";

module {
  public type Role = {
    #Partner;
    #Associate;
    #Staff;
  };

  public type UserRecord = {
    role : Role;
    addedBy : Principal;   // who registered this user (audit lineage)
    addedAt : Time.Time;   // nanoseconds since epoch
    suspended : Bool;      // F-08 toggles this; default false
  };
};
