import Time "mo:core/Time";

module {

  public type ExportManifest = {
    generatedAt : Time.Time;
    generatedBy : Principal;
    totalClients : Nat;
    totalMatters : Nat;
    totalDocuments : Nat;
    totalVersions : Nat;
    totalAuditEntries : Nat;
    storageUsedBytes : Nat;
    storageBudgetBytes : Nat;
    masterController : Principal;
    operationsPrincipal : ?Principal;
    clientIds : [Nat];
    matterIds : [Nat];
    documents : [{ documentId : Nat; versionIds : [Nat] }];
    userPrincipals : [Principal];
  };

};
