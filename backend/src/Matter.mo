import Time "mo:core/Time";

module {
  public type MatterStatus = {
    #Open;
    #OnHold;
    #Closed;
    #Archived;   // terminal — no further transitions allowed
  };

  public type Matter = {
    id : Nat;
    title : Text;
    matterType : Text;            // free-form per Q4
    clientId : Nat;               // FK → Client.id; enforced on create/update
    assignedPartner : ?Principal; // null = unassigned; Partner role enforced when set
    description : Text;           // free-form; empty string allowed
    status : MatterStatus;
    openedAt : Time.Time;         // set at create time = Time.now()
    closedAt : ?Time.Time;        // set when status becomes #Closed; null otherwise
    createdAt : Time.Time;
    createdBy : Principal;
    lastModifiedAt : Time.Time;
    lastModifiedBy : Principal;
  };

  // Pure helper encoding the §3.4 transition table.
  // #Open → #OnHold, #Closed
  // #OnHold → #Open, #Closed
  // #Closed → #Open, #Archived
  // #Archived → (terminal)
  public func isValidMatterTransition(from : MatterStatus, to : MatterStatus) : Bool {
    switch (from, to) {
      case (#Open,   #OnHold)   true;
      case (#Open,   #Closed)   true;
      case (#OnHold, #Open)     true;
      case (#OnHold, #Closed)   true;
      case (#Closed, #Open)     true;
      case (#Closed, #Archived) true;
      case _                    false;
    };
  };

  public func statusText(s : MatterStatus) : Text {
    switch s {
      case (#Open)     "Open";
      case (#OnHold)   "OnHold";
      case (#Closed)   "Closed";
      case (#Archived) "Archived";
    };
  };
};
