import Time "mo:core/Time";
import Library "./Library";

module {

  public type ExportManifest = {
    generatedAt : Time.Time;
    generatedBy : Principal;
    totalClients : Nat;
    totalMatters : Nat;
    totalDocuments : Nat;
    totalVersions : Nat;
    totalFolders : Nat;                                        // Firm Library (Phase 1.5)
    totalLibraryItems : Nat;                                   // Firm Library (Phase 1.5)
    totalLibraryVersions : Nat;                                // Firm Library (Phase 1.5)
    totalAuditEntries : Nat;
    storageUsedBytes : Nat;
    storageBudgetBytes : Nat;
    masterController : Principal;
    operationsPrincipal : ?Principal;
    clientIds : [Nat];
    matterIds : [Nat];
    documents : [{ documentId : Nat; versionIds : [Nat] }];
    folders : [Library.Folder];                                // Firm Library (Phase 1.5)
    libraryItems : [{ itemId : Nat; versionIds : [Nat] }];    // Firm Library (Phase 1.5)
    userPrincipals : [Principal];
  };

};
