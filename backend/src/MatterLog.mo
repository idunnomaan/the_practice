import Time "mo:core/Time";

module {
  public type SystemEventKind = {
    #MatterOpened;
    #MatterPutOnHold;
    #MatterResumed;
    #MatterClosed;
    #MatterArchived;
  };

  public type MatterLogEntryKind = {
    #SessionNote;
    #SystemEvent : SystemEventKind;
  };

  public type MatterLogEntry = {
    id : Nat;
    matterId : Nat;
    author : Principal;
    createdAt : Time.Time;
    note : Text;
    attachedDocumentIds : [Nat];
    kind : MatterLogEntryKind;
  };
}
