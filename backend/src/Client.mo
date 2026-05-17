import Time "mo:core/Time";

module {
  public type ClientType = {
    #Individual;
    #Company;
    #Other;
  };

  public type ClientStatus = {
    #Active;
    #Inactive;   // soft-deleted; not surfaced in default listings
  };

  public type Client = {
    id : Nat;
    name : Text;
    clientType : ClientType;
    primaryEmail : ?Text;
    primaryPhone : ?Text;
    identifier : ?Text;           // NIC for individuals, BR-no for companies — free-form
    notes : Text;                 // free-form; empty string allowed
    status : ClientStatus;
    createdAt : Time.Time;
    createdBy : Principal;
    lastModifiedAt : Time.Time;
    lastModifiedBy : Principal;
  };
};
