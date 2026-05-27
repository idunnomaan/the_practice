import { useState, useCallback } from "react";
import { useAuth } from "../auth/useAuth";
import { FileAccessKind } from "../backend/api/backend";
import type {
  Folder,
  FolderListing,
  FolderScope,
  LibraryItem,
} from "../backend/api/backend";

const CHUNK_SIZE = 1024 * 1024; // 1 MB

export function useLibrary() {
  const { actor } = useAuth();
  const [folders, setFolders] = useState<Folder[]>([]);
  const [listing, setListing] = useState<FolderListing>({ folders: [], items: [] });
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const loadFolders = useCallback(async () => {
    if (!actor) return;
    setFolders(await actor.listAllFolders());
  }, [actor]);

  const loadContents = useCallback(async (scope: FolderScope) => {
    if (!actor) return;
    setLoading(true);
    setError(null);
    try {
      if (scope.__kind__ === "Any") {
        // listFolderContents returns empty for #Any — use listLibraryItems instead
        const results = await actor.listLibraryItems({ folderScope: scope }, 0n, 1000n);
        setListing({ folders: [], items: results });
      } else {
        setListing(await actor.listFolderContents(scope));
      }
    } catch (e) {
      setError(String(e));
    } finally {
      setLoading(false);
    }
  }, [actor]);

  const createFolder = useCallback(async (name: string, parentId: bigint | null) => {
    if (!actor) return { __kind__: "err" as const, err: "Not connected" };
    return actor.createFolder(name, parentId);
  }, [actor]);

  const deleteFolder = useCallback(async (folderId: bigint) => {
    if (!actor) return { __kind__: "err" as const, err: "Not connected" };
    return actor.deleteFolder(folderId);
  }, [actor]);

  const upload = useCallback(async (
    file: File,
    name: string,
    folderId: bigint | null,
    tags: string[],
    description: string,
    uploadNotes: string,
    onProgress: (pct: number) => void,
  ) => {
    if (!actor) return { __kind__: "err" as const, err: "Not connected" };

    const bytes = new Uint8Array(await file.arrayBuffer());
    const totalChunks = Math.ceil(bytes.length / CHUNK_SIZE);

    const startResult = await actor.startLibraryUpload(
      name, folderId, tags, description,
      file.name, file.type, BigInt(bytes.length), uploadNotes, null,
    );
    if (startResult.__kind__ === "err") return startResult;
    const sessionId = startResult.ok;

    for (let i = 0; i < totalChunks; i++) {
      const chunk = bytes.slice(i * CHUNK_SIZE, (i + 1) * CHUNK_SIZE);
      const appendResult = await actor.appendLibraryChunk(sessionId, BigInt(i), chunk);
      if (appendResult.__kind__ === "err") {
        await actor.abandonLibraryUpload(sessionId);
        return appendResult;
      }
      onProgress(Math.round(((i + 1) / totalChunks) * 100));
    }

    return actor.finalizeLibraryUpload(sessionId);
  }, [actor]);

  const download = useCallback(async (item: LibraryItem) => {
    if (!actor) return;

    const prepResult = await actor.prepareLibraryDownload(item.currentVersionId, FileAccessKind.Download);
    if (prepResult.__kind__ === "err") throw new Error(prepResult.err);
    const { chunkCount, filename, contentType } = prepResult.ok;
    const parts: Uint8Array[] = [];

    for (let i = 0n; i < chunkCount; i++) {
      const chunk = await actor.getLibraryChunk(item.currentVersionId, i);
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

  const deleteItem = useCallback(async (itemId: bigint) => {
    if (!actor) return { __kind__: "err" as const, err: "Not connected" };
    return actor.deleteLibraryItem(itemId);
  }, [actor]);

  return {
    folders, listing, loading, error,
    loadFolders, loadContents,
    createFolder, deleteFolder,
    upload, download, deleteItem,
  };
}
