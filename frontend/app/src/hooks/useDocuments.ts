import { useState, useCallback } from "react";
import { useAuth } from "../auth/useAuth";
import type { Document, DocumentVersion } from "../backend/api/backend";

const CHUNK_SIZE = 1024 * 1024; // 1 MB

export function useDocuments(matterId: bigint) {
  const { actor } = useAuth();
  const [documents, setDocuments] = useState<Document[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!actor) return;
    setLoading(true);
    setError(null);
    try {
      setDocuments(await actor.listDocumentsByMatter(matterId, 0n, 100n, false));
    } catch (e) {
      setError(String(e));
    } finally {
      setLoading(false);
    }
  }, [actor, matterId]);

  const getVersion = useCallback(async (versionId: bigint): Promise<DocumentVersion | null> => {
    if (!actor) return null;
    return actor.getDocumentVersion(versionId);
  }, [actor]);

  const upload = useCallback(async (
    file: File,
    onProgress: (pct: number) => void,
  ) => {
    if (!actor) return { __kind__: "err" as const, err: "Not connected" };

    const bytes = new Uint8Array(await file.arrayBuffer());
    const totalChunks = Math.ceil(bytes.length / CHUNK_SIZE);

    const startResult = await actor.startUpload(
      matterId,
      file.name,
      file.type,
      BigInt(bytes.length),
      "",
      null,
    );
    if (startResult.__kind__ === "err") return startResult;
    const sessionId = startResult.ok;

    for (let i = 0; i < totalChunks; i++) {
      const chunk = bytes.slice(i * CHUNK_SIZE, (i + 1) * CHUNK_SIZE);
      const appendResult = await actor.appendChunk(sessionId, BigInt(i), chunk);
      if (appendResult.__kind__ === "err") {
        await actor.abandonUpload(sessionId);
        return appendResult;
      }
      onProgress(Math.round(((i + 1) / totalChunks) * 100));
    }

    return actor.finalizeUpload(sessionId);
  }, [actor, matterId]);

  const download = useCallback(async (doc: Document) => {
    if (!actor) return;

    const prepResult = await actor.prepareDocumentDownload(doc.currentVersionId);
    if (prepResult.__kind__ === "err") {
      throw new Error(prepResult.err);
    }
    const { chunkCount, filename, contentType } = prepResult.ok;
    const parts: Uint8Array[] = [];

    for (let i = 0n; i < chunkCount; i++) {
      const chunk = await actor.getChunk(doc.currentVersionId, i);
      if (chunk) parts.push(chunk);
    }

    const blob = new Blob(parts, { type: contentType });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = filename;
    a.click();
    URL.revokeObjectURL(url);
  }, [actor]);

  const deleteDocument = useCallback(async (documentId: bigint) => {
    if (!actor) return null;
    return actor.deleteDocument(documentId);
  }, [actor]);

  return {
    documents, loading, error,
    load, getVersion, upload, download, deleteDocument,
  };
}
