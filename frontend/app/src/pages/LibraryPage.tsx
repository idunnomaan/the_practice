import { useEffect, useRef, useState } from "react";
import { useAuth } from "../auth/useAuth";
import { useLibrary } from "../hooks/useLibrary";
import { Role, LibraryItemStatus } from "../backend/api/backend";
import type { Folder, FolderScope, LibraryItem, LibraryItemSearchResult } from "../backend/api/backend";
import LoadingSpinner from "../components/LoadingSpinner";
import ErrorMessage from "../components/ErrorMessage";
import ConfirmDialog from "../components/ConfirmDialog";

const MAX_SIZE = 5 * 1024 * 1024 * 1024; // 5 GiB per-item ceiling (Q9)

// ── Folder tree ──────────────────────────────────────────────────────────────

interface TreeNode { folder: Folder; children: TreeNode[] }

function buildTree(folders: Folder[], parentId?: bigint): TreeNode[] {
  return folders
    .filter(f => f.parentId === parentId)
    .map(f => ({ folder: f, children: buildTree(folders, f.id) }));
}

function FolderTree({
  nodes, selectedId, onSelect, depth = 0,
}: {
  nodes: TreeNode[]; selectedId: bigint | null;
  onSelect: (id: bigint) => void; depth?: number;
}) {
  return (
    <>
      {nodes.map(({ folder, children }) => (
        <div key={String(folder.id)}>
          <button
            style={{
              display: "flex", alignItems: "center", gap: 6,
              width: "100%", padding: `5px 8px 5px ${12 + depth * 14}px`,
              background: selectedId === folder.id ? "var(--ac)" : "none",
              color: selectedId === folder.id ? "var(--ac-text)" : "var(--tx)",
              border: "none", borderRadius: 4, cursor: "pointer",
              fontSize: 13, textAlign: "left",
            }}
            onClick={() => onSelect(folder.id)}
          >
            <i className="ti ti-folder" style={{ fontSize: 14 }} />
            {folder.name}
          </button>
          {children.length > 0 && (
            <FolderTree nodes={children} selectedId={selectedId} onSelect={onSelect} depth={depth + 1} />
          )}
        </div>
      ))}
    </>
  );
}

// ── Helpers ──────────────────────────────────────────────────────────────────

function fileIcon(ct?: string) {
  if (!ct) return "ti-file";
  if (ct === "application/pdf") return "ti-file-type-pdf";
  if (ct.startsWith("image/")) return "ti-photo";
  return "ti-file-text";
}

function formatBytes(bytes: bigint) {
  const n = Number(bytes);
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  return `${(n / (1024 * 1024)).toFixed(1)} MB`;
}

// ── Page ─────────────────────────────────────────────────────────────────────

export default function LibraryPage() {
  const { role, actor } = useAuth();
  const {
    folders, listing, loading, error,
    loadFolders, loadContents,
    createFolder, deleteFolder,
    upload, download, deleteItem,
  } = useLibrary();

  const [scope, setScope] = useState<FolderScope>({ __kind__: "Any", Any: null });
  const selectedFolderId: bigint | null = scope.__kind__ === "Folder" ? scope.Folder : null;

  const [showNewFolder, setShowNewFolder] = useState(false);
  const [newFolderName, setNewFolderName] = useState("");
  const [folderError, setFolderError] = useState<string | null>(null);

  const fileRef = useRef<HTMLInputElement>(null);
  const [showUpload, setShowUpload] = useState(false);
  const [uploadName, setUploadName] = useState("");
  const [uploadTags, setUploadTags] = useState("");
  const [uploadDesc, setUploadDesc] = useState("");
  const [uploadNotes, setUploadNotes] = useState("");
  const [uploadFile, setUploadFile] = useState<File | null>(null);
  const [uploading, setUploading] = useState(false);
  const [progress, setProgress] = useState(0);
  const [uploadError, setUploadError] = useState<string | null>(null);

  const [actionError, setActionError] = useState<string | null>(null);
  const [confirmDeleteItem, setConfirmDeleteItem] = useState<bigint | null>(null);
  const [confirmDeleteFolder, setConfirmDeleteFolder] = useState<bigint | null>(null);
  const [downloading, setDownloading] = useState<bigint | null>(null);
  const [searchQuery, setSearchQuery] = useState("");
  const [searchResults, setSearchResults] = useState<LibraryItemSearchResult[] | null>(null);
  const [searchLoading, setSearchLoading] = useState(false);

  useEffect(() => { void loadFolders(); }, [loadFolders]);
  useEffect(() => { void loadContents(scope); }, [loadContents, scope]);

  const tree = buildTree(folders);
  const uploadFolderId: bigint | null = scope.__kind__ === "Folder" ? scope.Folder : null;
  const canUpload = role === Role.Partner || role === Role.Associate;
  const canDeleteItem = role === Role.Partner;

  function selectScope(s: FolderScope) {
    setScope(s);
    setShowNewFolder(false);
    setShowUpload(false);
    setSearchQuery("");
    setSearchResults(null);
  }

  async function handleSearch(e: React.FormEvent) {
    e.preventDefault();
    if (!actor || !searchQuery.trim()) { setSearchResults(null); return; }
    setSearchLoading(true);
    try {
      const results = await actor.searchLibrary(
        { folderScope: { __kind__: "Any", Any: null }, nameContains: searchQuery.trim() },
        0n, 200n,
      );
      setSearchResults(results);
    } catch (err) {
      setSearchResults([]);
    } finally {
      setSearchLoading(false);
    }
  }

  function clearSearch() {
    setSearchQuery("");
    setSearchResults(null);
  }

  async function handleCreateFolder(e: React.FormEvent) {
    e.preventDefault();
    if (!newFolderName.trim()) return;
    setFolderError(null);
    const parentId = scope.__kind__ === "Folder" ? scope.Folder : null;
    const result = await createFolder(newFolderName.trim(), parentId);
    if (result.__kind__ === "ok") {
      setShowNewFolder(false);
      setNewFolderName("");
      void loadFolders();
      void loadContents(scope);
    } else {
      setFolderError(result.err);
    }
  }

  async function handleDeleteFolder() {
    if (confirmDeleteFolder === null) return;
    const id = confirmDeleteFolder;
    setConfirmDeleteFolder(null);
    setActionError(null);
    const result = await deleteFolder(id);
    if (result.__kind__ === "err") {
      setActionError(result.err);
    } else {
      if (selectedFolderId === id) selectScope({ __kind__: "Any", Any: null });
      void loadFolders();
      void loadContents(scope);
    }
  }

  function handleFileSelect(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;
    if (file.size > MAX_SIZE) { setUploadError("File exceeds 5 GiB limit."); return; }
    setUploadFile(file);
    if (!uploadName) setUploadName(file.name.replace(/\.[^.]+$/, ""));
    setUploadError(null);
  }

  async function handleUpload(e: React.FormEvent) {
    e.preventDefault();
    if (!uploadFile || !uploadName.trim()) return;
    setUploading(true);
    setProgress(0);
    setUploadError(null);
    const tags = uploadTags.split(",").map(t => t.trim()).filter(Boolean);
    const result = await upload(
      uploadFile, uploadName.trim(), uploadFolderId,
      tags, uploadDesc.trim(), uploadNotes.trim(),
      (pct) => setProgress(pct),
    );
    setUploading(false);
    if (result.__kind__ === "err") {
      setUploadError(result.err);
    } else {
      setShowUpload(false);
      setUploadFile(null);
      setUploadName(""); setUploadTags(""); setUploadDesc(""); setUploadNotes("");
      if (fileRef.current) fileRef.current.value = "";
      void loadContents(scope);
    }
  }

  async function handleDownload(item: LibraryItem) {
    setDownloading(item.id);
    setActionError(null);
    try { await download(item); }
    catch (e) { setActionError(String(e)); }
    finally { setDownloading(null); }
  }

  async function handleDeleteItem() {
    if (confirmDeleteItem === null) return;
    const id = confirmDeleteItem;
    setConfirmDeleteItem(null);
    setActionError(null);
    const result = await deleteItem(id);
    if (result.__kind__ === "err") setActionError(result.err);
    else void loadContents(scope);
  }

  return (
    <div>
      <div className="page-header">
        <div className="page-title">Firm Library</div>
      </div>

      {confirmDeleteItem !== null && (
        <ConfirmDialog
          message="Delete this library item? This cannot be undone."
          onConfirm={() => { void handleDeleteItem(); }}
          onCancel={() => setConfirmDeleteItem(null)}
        />
      )}
      {confirmDeleteFolder !== null && (
        <ConfirmDialog
          message="Delete this folder? It must be empty first."
          onConfirm={() => { void handleDeleteFolder(); }}
          onCancel={() => setConfirmDeleteFolder(null)}
        />
      )}

      <div style={{ display: "flex", gap: 16, alignItems: "flex-start" }}>

        {/* ── Left: folder tree ─────────────────────────────────────────── */}
        <div className="card" style={{ width: 200, flexShrink: 0, padding: "8px 0" }}>
          <div className="section-head" style={{ padding: "0 12px 4px" }}>Folders</div>

          {/* All Items pseudo-entry */}
          <button
            style={{
              display: "flex", alignItems: "center", gap: 6,
              width: "100%", padding: "5px 8px 5px 12px",
              background: scope.__kind__ === "Any" ? "var(--ac)" : "none",
              color: scope.__kind__ === "Any" ? "var(--ac-text)" : "var(--tx)",
              border: "none", borderRadius: 4, cursor: "pointer", fontSize: 13,
            }}
            onClick={() => selectScope({ __kind__: "Any", Any: null })}
          >
            <i className="ti ti-layout-list" style={{ fontSize: 14 }} />
            All Items
          </button>

          <FolderTree
            nodes={tree}
            selectedId={selectedFolderId}
            onSelect={id => selectScope({ __kind__: "Folder", Folder: id })}
          />

          {canUpload && (
            <div style={{ padding: "8px" }}>
              {showNewFolder ? (
                <form onSubmit={(e) => { void handleCreateFolder(e); }}>
                  {folderError && <ErrorMessage message={folderError} onDismiss={() => setFolderError(null)} />}
                  <input
                    className="tp-input"
                    style={{ marginBottom: 4, fontSize: 12 }}
                    value={newFolderName}
                    onChange={e => setNewFolderName(e.target.value)}
                    placeholder="Folder name"
                    autoFocus
                  />
                  <div style={{ display: "flex", gap: 4 }}>
                    <button type="submit" className="btn btn-primary btn-sm">Add</button>
                    <button type="button" className="btn btn-neutral btn-sm"
                      onClick={() => { setShowNewFolder(false); setNewFolderName(""); }}>
                      Cancel
                    </button>
                  </div>
                </form>
              ) : (
                <button className="btn btn-neutral btn-sm" style={{ width: "100%" }}
                  onClick={() => setShowNewFolder(true)}>
                  <i className="ti ti-folder-plus" /> New folder
                </button>
              )}
            </div>
          )}
        </div>

        {/* ── Right: items panel ────────────────────────────────────────── */}
        <div style={{ flex: 1, minWidth: 0 }}>

          {canUpload && (
            <div style={{ marginBottom: 12 }}>
              {showUpload ? (
                <form className="tp-form" onSubmit={(e) => { void handleUpload(e); }}>
                  {uploadError && <ErrorMessage message={uploadError} onDismiss={() => setUploadError(null)} />}
                  <label className="tp-label">Name *
                    <input className="tp-input" value={uploadName}
                      onChange={e => setUploadName(e.target.value)} required />
                  </label>
                  <label className="tp-label">File *
                    <div className="upload-area">
                      <input ref={fileRef} type="file" onChange={handleFileSelect} disabled={uploading} />
                      {uploadFile && (
                        <span style={{ fontSize: 12, color: "var(--tx2)" }}>
                          {uploadFile.name} ({formatBytes(BigInt(uploadFile.size))})
                        </span>
                      )}
                      {uploading && (
                        <>
                          <div className="progress-bar">
                            <div className="progress-fill" style={{ width: `${progress}%` }} />
                          </div>
                          <div className="progress-label">Uploading… {progress}%</div>
                        </>
                      )}
                    </div>
                  </label>
                  <label className="tp-label">Tags (comma-separated)
                    <input className="tp-input" value={uploadTags}
                      onChange={e => setUploadTags(e.target.value)}
                      placeholder="e.g. template, contract" />
                  </label>
                  <label className="tp-label">Description
                    <textarea className="tp-input tp-textarea" value={uploadDesc}
                      onChange={e => setUploadDesc(e.target.value)} />
                  </label>
                  <label className="tp-label">Upload notes
                    <input className="tp-input" value={uploadNotes}
                      onChange={e => setUploadNotes(e.target.value)} />
                  </label>
                  <div style={{ display: "flex", gap: 8 }}>
                    <button type="submit" className="btn btn-primary"
                      disabled={uploading || !uploadFile}>
                      {uploading ? "Uploading…" : "Upload"}
                    </button>
                    <button type="button" className="btn btn-neutral"
                      onClick={() => setShowUpload(false)} disabled={uploading}>
                      Cancel
                    </button>
                  </div>
                </form>
              ) : (
                <button className="add-btn" onClick={() => setShowUpload(true)}>
                  <i className="ti ti-upload" /> Upload file
                </button>
              )}
            </div>
          )}

          {actionError && <ErrorMessage message={actionError} onDismiss={() => setActionError(null)} />}
          {error && <ErrorMessage message={error} />}
          {(loading || searchLoading) && <LoadingSpinner />}

          {/* Search */}
          <form onSubmit={(e) => { void handleSearch(e); }}
            style={{ display: "flex", gap: 6, marginBottom: 12 }}>
            <input
              className="tp-input"
              style={{ flex: 1 }}
              value={searchQuery}
              onChange={e => setSearchQuery(e.target.value)}
              placeholder="Search by name…"
            />
            <button type="submit" className="btn btn-neutral" disabled={!searchQuery.trim() || searchLoading}>
              <i className="ti ti-search" /> Search
            </button>
            {searchResults !== null && (
              <button type="button" className="btn btn-neutral" onClick={clearSearch}>
                Clear
              </button>
            )}
          </form>

          {/* Items */}
          <div className="card">
            {searchResults !== null && (
              <div style={{ fontSize: 12, color: "var(--tx2)", marginBottom: 8 }}>
                Showing {searchResults.length} result{searchResults.length !== 1 ? "s" : ""} for "{searchQuery}"
              </div>
            )}
            <table className="tp-table">
              <thead>
                <tr>
                  <th>Name</th>
                  <th>File</th>
                  <th>Size</th>
                  <th>Tags</th>
                  <th>Status</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                {(searchResults ?? listing.items).map(({ item, currentVersion: ver }) => (
                  <tr key={String(item.id)}
                    style={{ opacity: item.status !== LibraryItemStatus.Active ? 0.6 : 1 }}>
                    <td>
                      <i className={`ti ${fileIcon(ver.contentType)} file-icon`} />
                      {item.name}
                    </td>
                    <td style={{ color: "var(--tx2)", fontSize: 12 }}>{ver.filename}</td>
                    <td>{formatBytes(ver.sizeBytes)}</td>
                    <td>
                      {item.tags.map(tag => (
                        <span key={tag} className="badge" style={{ marginRight: 3, fontSize: 11 }}>{tag}</span>
                      ))}
                    </td>
                    <td>
                      <span className={item.status === LibraryItemStatus.Active
                        ? "badge badge-active" : "badge badge-archived"}>
                        {item.status}
                      </span>
                    </td>
                    <td>
                      <div style={{ display: "flex", gap: 6 }}>
                        <button className="btn btn-neutral btn-sm"
                          onClick={() => { void handleDownload(item); }}
                          disabled={downloading === item.id}>
                          {downloading === item.id ? "…" : "Download"}
                        </button>
                        {canDeleteItem && item.status === LibraryItemStatus.Active && (
                          <button className="btn btn-danger btn-sm"
                            onClick={() => setConfirmDeleteItem(item.id)}>
                            Delete
                          </button>
                        )}
                      </div>
                    </td>
                  </tr>
                ))}
                {!loading && !searchLoading && (searchResults ?? listing.items).length === 0 && (
                  <tr><td colSpan={6} className="empty-state">
                    {searchResults !== null ? "No results." : "No items."}
                  </td></tr>
                )}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
  );
}
