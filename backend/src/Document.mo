import Time "mo:core/Time";
import Map "mo:core/pure/Map";

module {
  public let CHUNK_SIZE : Nat = 1_048_576;
  public let MAX_FILE_SIZE : Nat = 100_000_000;
  public let DEFAULT_STORAGE_BUDGET : Nat = 53_687_091_200;

  public let ALLOWED_CONTENT_TYPES : [Text] = [
    "application/pdf",
    "application/msword",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "image/png",
    "image/jpeg",
    "image/gif",
    "image/webp",
  ];

  public type DocumentStatus = {
    #Active;
    #Deleted;
  };

  public type Document = {
    id : Nat;
    matterId : Nat;
    currentVersionId : Nat;
    status : DocumentStatus;
    createdAt : Time.Time;
    createdBy : Principal;
  };

  public type DocumentVersion = {
    versionId : Nat;
    documentId : Nat;
    versionNumber : Nat;
    filename : Text;
    contentType : Text;
    sizeBytes : Nat;
    blob : Blob;
    sha256 : Blob;
    uploadedAt : Time.Time;
    uploadedBy : Principal;
    uploadNotes : Text;
  };

  // Transient — deleted on finalize or abandon
  public type UploadSession = {
    sessionId : Nat;
    matterId : Nat;
    filename : Text;
    contentType : Text;
    totalSizeBytes : Nat;
    expectedChunkCount : Nat;
    uploadNotes : Text;
    replacesDocumentId : ?Nat;
    chunks : Map.Map<Nat, Blob>;  // keyed 0..N-1; pure Map updated via session record replacement
    startedAt : Time.Time;
    startedBy : Principal;        // session is caller-locked
  };

  public func isAllowedContentType(ct : Text) : Bool {
    for (allowed in ALLOWED_CONTENT_TYPES.vals()) {
      if (ct == allowed) return true;
    };
    false
  };

  // ceil(totalSizeBytes / CHUNK_SIZE)
  public func expectedChunkCount(totalSizeBytes : Nat) : Nat {
    if (totalSizeBytes == 0) return 0;
    (totalSizeBytes + CHUNK_SIZE - 1) / CHUNK_SIZE
  };

  // Returns (startByte, endByte) for chunk at chunkIndex in a blob of totalSize bytes.
  // endByte = min((chunkIndex+1) * CHUNK_SIZE, totalSize)
  public func chunkRange(chunkIndex : Nat, totalSize : Nat) : (Nat, Nat) {
    let startByte = chunkIndex * CHUNK_SIZE;
    let endByte = if (startByte + CHUNK_SIZE < totalSize) startByte + CHUNK_SIZE else totalSize;
    (startByte, endByte)
  };
};
