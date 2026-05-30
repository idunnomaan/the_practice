import { useEffect, useRef, useState } from "react";
import { useAuth } from "../auth/useAuth";
import { useLibrary } from "../hooks/useLibrary";
import { Role, LibraryItemStatus } from "../backend/api/backend";
import type { AuditEntry, Folder, FolderScope, LibraryItem, LibraryItemSearchResult } from "../backend/api/backend";
import LoadingSpinner from "../components/LoadingSpinner";
import ErrorMessage from "../components/ErrorMessage";
import ConfirmDialog from "../components/ConfirmDialog";
import { useFileViewer } from "../state/fileViewerStore";

type FilterType = "All" | "Folders" | "PDFs" | "Docs" | "Video" | "Images";
type SortBy = "newest" | "oldest" | "name-az" | "size";

const MAX_SIZE = 5 * 1024 * 1024 * 1024;

// ── Helpers ──────────────────────────────────────────────────────────────────

function fileIcon(ct?: string) {
  if (!ct) return "ti-file";
  if (ct === "application/pdf") return "ti-file-type-pdf";
  if (ct.startsWith("image/")) return "ti-photo";
  if (ct.includes("word") || ct.includes("document")) return "ti-file-word";
  if (ct.startsWith("video/")) return "ti-video";
  return "ti-file-text";
}

function formatBytes(bytes: bigint) {
  const n = Number(bytes);
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  return `${(n / (1024 * 1024)).toFixed(1)} MB`;
}

function relativeTime(ns: bigint) {
  const diffMs = Date.now() - Number(ns / 1_000_000n);
  const mins = Math.floor(diffMs / 60_000);
  if (mins < 2) return "Just now";
  if (mins < 60) return `${mins}m ago`;
  const hours = Math.floor(mins / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  if (days === 1) return "Yesterday";
  return `${days}d ago`;
}

function typeMatches(ct: string, f: FilterType): boolean {
  if (f === "All") return true;
  if (f === "PDFs") return ct === "application/pdf";
  if (f === "Docs") return ct.includes("word") || ct.includes("document") || ct.startsWith("text/");
  if (f === "Video") return ct.startsWith("video/");
  if (f === "Images") return ct.startsWith("image/");
  return true;
}

function extractLibraryItemId(action: string): bigint | null {
  if (!action.startsWith("libraryItem.view:") && !action.startsWith("library.download:")) return null;
  const parts = action.split(":");
  try { return BigInt(parts[1]); } catch { return null; }
}

// ── Image thumbnail (loads first chunk lazily) ────────────────────────────────

function ImageThumb({ versionId, contentType, actor }: {
  versionId: bigint;
  contentType: string;
  actor: { getLibraryChunk(v: bigint, c: bigint): Promise<Uint8Array | null> } | null;
}) {
  const [url, setUrl] = useState<string | null>(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    if (!actor) return;
    let cancelled = false;
    let createdUrl: string | null = null;
    actor.getLibraryChunk(versionId, 0n).then(chunk => {
      if (cancelled || !chunk) return;
      const blob = new Blob([chunk], { type: contentType });
      createdUrl = URL.createObjectURL(blob);
      setUrl(createdUrl);
    }).catch(() => {});
    return () => {
      cancelled = true;
      if (createdUrl) URL.revokeObjectURL(createdUrl);
    };
  }, [versionId, contentType, actor]);

  if (!url || failed) return <i className="ti ti-photo" style={{ fontSize: 28, color: "var(--tx2)" }} />;
  return <img src={url} style={{ width: "100%", height: "100%", objectFit: "cover" }} alt="" onError={() => setFailed(true)} />;
}

// ── Page ─────────────────────────────────────────────────────────────────────

export default function LibraryPage() {
  const { role, actor } = useAuth();
  const { openViewer } = useFileViewer();
  const {
    folders, listing, loading, error,
    loadFolders, loadContents,
    createFolder, deleteFolder,
    upload, download, deleteItem,
  } = useLibrary();

  // navigation
  const [breadcrumb, setBreadcrumb] = useState<{ id: bigint | null; name: string }[]>([{ id: null, name: "Home" }]);
  const currentFolderId = breadcrumb[breadcrumb.length - 1].id;
  const currentScope: FolderScope = currentFolderId !== null
    ? { __kind__: "Folder", Folder: currentFolderId }
    : { __kind__: "Any", Any: null };

  // view / filter / sort
  const [viewMode, setViewMode] = useState<"grid" | "list">("grid");
  const [filterType, setFilterType] = useState<FilterType>("All");
  const [sortBy, setSortBy] = useState<SortBy>("newest");

  // search
  const [searchQuery, setSearchQuery] = useState("");
  const [searchResults, setSearchResults] = useState<LibraryItemSearchResult[] | null>(null);
  const [searchLoading, setSearchLoading] = useState(false);

  // upload form
  const fileRef = useRef<HTMLInputElement>(null);
  const [showUploadForm, setShowUploadForm] = useState(false);
  const [uploadName, setUploadName] = useState("");
  const [uploadTags, setUploadTags] = useState("");
  const [uploadDesc, setUploadDesc] = useState("");
  const [uploadNotes, setUploadNotes] = useState("");
  const [uploadFile, setUploadFile] = useState<File | null>(null);
  const [uploading, setUploading] = useState(false);
  const [uploadProgress, setUploadProgress] = useState(0);
  const [uploadError, setUploadError] = useState<string | null>(null);

  // drag-drop
  const [dragOver, setDragOver] = useState(false);
  const [dragUploading, setDragUploading] = useState<string | null>(null);
  const dragCounter = useRef(0);

  // folder creation
  const [showNewFolder, setShowNewFolder] = useState(false);
  const [newFolderName, setNewFolderName] = useState("");
  const [folderError, setFolderError] = useState<string | null>(null);

  // misc
  const [actionError, setActionError] = useState<string | null>(null);
  const [confirmDeleteFolder, setConfirmDeleteFolder] = useState<bigint | null>(null);
  const [downloading, setDownloading] = useState<bigint | null>(null);

  // audit log for access stats
  const [auditEntries, setAuditEntries] = useState<AuditEntry[]>([]);

  const canUpload = role === Role.Partner || role === Role.Associate;
  const canDeleteItem = role === Role.Partner;

  useEffect(() => { void loadFolders(); }, [loadFolders]);

  useEffect(() => {
    void loadContents(currentScope);
    setFilterType("All");
    setSearchQuery("");
    setSearchResults(null);
  }, [breadcrumb]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    if (!actor) return;
    actor.readAuditEntries(0n, 500n).then(r => {
      if (r.__kind__ === "ok") setAuditEntries(r.ok);
    }).catch(() => {});
  }, [actor]);

  // ── Derived: access map + recently accessed ──────────────────────────────────

  const accessCountMap = new Map<string, number>();
  for (const e of auditEntries) {
    const itemId = extractLibraryItemId(e.action);
    if (itemId !== null) {
      const key = String(itemId);
      accessCountMap.set(key, (accessCountMap.get(key) ?? 0) + 1);
    }
  }

  const accessEntries = [...auditEntries]
    .filter(e => extractLibraryItemId(e.action) !== null)
    .sort((a, b) => Number(b.timestamp - a.timestamp));

  const recentIds: bigint[] = [];
  const seenIds = new Set<string>();
  for (const e of accessEntries) {
    const id = extractLibraryItemId(e.action)!;
    const key = String(id);
    if (!seenIds.has(key)) { seenIds.add(key); recentIds.push(id); }
    if (recentIds.length >= 5) break;
  }

  const recentItems = recentIds.flatMap(id => {
    const found = listing.items.find(r => r.item.id === id);
    if (!found) return [];
    const ts = accessEntries.find(e => extractLibraryItemId(e.action) === id)?.timestamp ?? 0n;
    return [{ item: found.item, ver: found.currentVersion, ts }];
  });

  // ── Derived: displayed folders + items ───────────────────────────────────────

  const displayFolders = currentFolderId === null
    ? folders.filter(f => !f.parentId)
    : listing.folders;

  const sourceItems = searchResults !== null ? searchResults : listing.items;

  const filteredItems = filterType === "Folders"
    ? []
    : sourceItems.filter(r => typeMatches(r.currentVersion.contentType, filterType));

  const sortedItems = [...filteredItems].sort((a, b) => {
    if (sortBy === "newest") return Number(b.item.createdAt - a.item.createdAt);
    if (sortBy === "oldest") return Number(a.item.createdAt - b.item.createdAt);
    if (sortBy === "name-az") return a.item.name.localeCompare(b.item.name);
    if (sortBy === "size") return Number(b.currentVersion.sizeBytes - a.currentVersion.sizeBytes);
    return 0;
  });

  function folderItemCount(folderId: bigint): number {
    return listing.items.filter(r => r.item.folderId === folderId).length;
  }

  // ── Navigation ────────────────────────────────────────────────────────────────

  function enterFolder(folder: Folder) {
    setBreadcrumb(prev => [...prev, { id: folder.id, name: folder.name }]);
  }

  function navigateTo(index: number) {
    setBreadcrumb(prev => prev.slice(0, index + 1));
  }

  // ── Search ────────────────────────────────────────────────────────────────────

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
    } finally { setSearchLoading(false); }
  }

  // ── Create folder ─────────────────────────────────────────────────────────────

  async function handleCreateFolder(e: React.FormEvent) {
    e.preventDefault();
    if (!newFolderName.trim()) return;
    setFolderError(null);
    const result = await createFolder(newFolderName.trim(), currentFolderId);
    if (result.__kind__ === "ok") {
      setShowNewFolder(false);
      setNewFolderName("");
      void loadFolders();
      void loadContents(currentScope);
    } else { setFolderError(result.err); }
  }

  // ── Delete folder ─────────────────────────────────────────────────────────────

  async function handleDeleteFolder() {
    if (confirmDeleteFolder === null) return;
    const id = confirmDeleteFolder;
    setConfirmDeleteFolder(null);
    setActionError(null);
    const result = await deleteFolder(id);
    if (result.__kind__ === "err") {
      setActionError(result.err);
    } else {
      void loadFolders();
      if (currentFolderId === id) {
        navigateTo(breadcrumb.length - 2); // useEffect triggers loadContents
      } else {
        void loadContents(currentScope);
      }
    }
  }

  // ── Upload (form) ─────────────────────────────────────────────────────────────

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
    setUploadProgress(0);
    setUploadError(null);
    const tags = uploadTags.split(",").map(t => t.trim()).filter(Boolean);
    const result = await upload(
      uploadFile, uploadName.trim(), currentFolderId, tags,
      uploadDesc.trim(), uploadNotes.trim(), pct => setUploadProgress(pct),
    );
    setUploading(false);
    if (result.__kind__ === "err") {
      setUploadError(result.err);
    } else {
      setShowUploadForm(false);
      setUploadFile(null);
      setUploadName(""); setUploadTags(""); setUploadDesc(""); setUploadNotes("");
      if (fileRef.current) fileRef.current.value = "";
      void loadContents(currentScope);
    }
  }

  // ── Drag-drop ─────────────────────────────────────────────────────────────────

  async function handleDrop(e: React.DragEvent) {
    e.preventDefault();
    dragCounter.current = 0;
    setDragOver(false);
    if (!canUpload) return;
    const files = Array.from(e.dataTransfer.files);
    for (const file of files) {
      if (file.size > MAX_SIZE) continue;
      setDragUploading(file.name);
      const name = file.name.replace(/\.[^.]+$/, "");
      await upload(file, name, currentFolderId, [], "", "", () => {});
    }
    setDragUploading(null);
    void loadContents(currentScope);
  }

  // ── Download ──────────────────────────────────────────────────────────────────

  async function handleDownload(item: LibraryItem) {
    setDownloading(item.id);
    setActionError(null);
    try { await download(item); }
    catch (e) { setActionError(String(e)); }
    finally { setDownloading(null); }
  }

  // ── Delete item ───────────────────────────────────────────────────────────────

  async function handleDeleteItem(id: bigint) {
    setActionError(null);
    const result = await deleteItem(id);
    if (result.__kind__ === "err") setActionError(result.err);
    else void loadContents(currentScope);
  }

  // ── Render ────────────────────────────────────────────────────────────────────

  return (
    <div
      onDragEnter={e => { e.preventDefault(); if (!canUpload) return; dragCounter.current++; setDragOver(true); }}
      onDragLeave={() => { dragCounter.current--; if (dragCounter.current <= 0) { dragCounter.current = 0; setDragOver(false); } }}
      onDragOver={e => e.preventDefault()}
      onDrop={e => { void handleDrop(e); }}
    >
      {confirmDeleteFolder !== null && (
        <ConfirmDialog
          message="Delete this folder? It must be empty first."
          onConfirm={() => { void handleDeleteFolder(); }}
          onCancel={() => setConfirmDeleteFolder(null)}
        />
      )}

      {/* ── Top bar ────────────────────────────────────────────────────────── */}
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 12, flexWrap: "wrap", gap: 8 }}>
        {/* Breadcrumb */}
        <div style={{ display: "flex", alignItems: "center", gap: 4, fontSize: 13, flexWrap: "wrap" }}>
          {breadcrumb.map((seg, i) => (
            <span key={i} style={{ display: "flex", alignItems: "center", gap: 4 }}>
              {i > 0 && <span style={{ color: "var(--tx2)", padding: "0 2px" }}>›</span>}
              {i < breadcrumb.length - 1 ? (
                <button onClick={() => navigateTo(i)} style={{
                  background: "none", border: "none", cursor: "pointer",
                  color: "var(--ac)", fontSize: 13, padding: 0,
                }}>
                  {seg.name}
                </button>
              ) : (
                <span style={{ fontWeight: 600 }}>{seg.name}</span>
              )}
            </span>
          ))}
        </div>
        {/* Actions */}
        <div style={{ display: "flex", gap: 6, alignItems: "center" }}>
          <form onSubmit={e => { void handleSearch(e); }} style={{ display: "flex", gap: 4 }}>
            <input
              className="tp-input"
              style={{ width: 150, fontSize: 12 }}
              value={searchQuery}
              onChange={e => setSearchQuery(e.target.value)}
              placeholder="Search…"
            />
            {searchResults !== null && (
              <button type="button" className="btn btn-neutral btn-sm"
                onClick={() => { setSearchResults(null); setSearchQuery(""); }}>×</button>
            )}
          </form>
          <button className="btn btn-neutral btn-sm"
            onClick={() => setViewMode(v => v === "grid" ? "list" : "grid")}
            title={viewMode === "grid" ? "List view" : "Grid view"}>
            <i className={`ti ${viewMode === "grid" ? "ti-list" : "ti-grid-dots"}`} />
          </button>
          {canUpload && (
            <button className="btn btn-neutral btn-sm" onClick={() => { setShowNewFolder(v => !v); }}>
              <i className="ti ti-folder-plus" /> New folder
            </button>
          )}
          {canUpload && (
            <button className="btn btn-primary btn-sm" onClick={() => { setShowUploadForm(v => !v); }}>
              <i className="ti ti-upload" /> Upload
            </button>
          )}
        </div>
      </div>

      {/* ── Recently accessed strip ──────────────────────────────────────── */}
      {recentItems.length > 0 && !searchResults && (
        <div style={{ marginBottom: 14 }}>
          <div style={{ fontSize: 11, color: "var(--tx2)", textTransform: "uppercase", letterSpacing: "0.06em", marginBottom: 6 }}>
            Recently accessed
          </div>
          <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
            {recentItems.map(({ item, ver, ts }) => (
              <button key={String(item.id)}
                onClick={() => openViewer({ kind: "library", id: item.id, versionId: ver.versionId, filename: ver.filename, contentType: ver.contentType, sizeBytes: ver.sizeBytes })}
                style={{
                  display: "inline-flex", alignItems: "center", gap: 6,
                  background: "var(--surf)", border: "1px solid var(--bd)", borderRadius: 6,
                  padding: "4px 10px", cursor: "pointer", fontSize: 12, color: "var(--tx)",
                }}>
                <i className={`ti ${fileIcon(ver.contentType)}`} style={{ fontSize: 13, color: "var(--tx2)" }} />
                <span>{ver.filename}</span>
                <span style={{ color: "var(--tx2)", fontSize: 11 }}>{relativeTime(ts)}</span>
              </button>
            ))}
          </div>
        </div>
      )}

      {/* ── New folder inline form ───────────────────────────────────────── */}
      {showNewFolder && (
        <form onSubmit={e => { void handleCreateFolder(e); }}
          style={{ marginBottom: 12, display: "flex", gap: 6, alignItems: "flex-start" }}>
          {folderError && <ErrorMessage message={folderError} onDismiss={() => setFolderError(null)} />}
          <input
            className="tp-input"
            style={{ width: 200, fontSize: 13 }}
            value={newFolderName}
            onChange={e => setNewFolderName(e.target.value)}
            placeholder="Folder name"
            autoFocus
          />
          <button type="submit" className="btn btn-primary btn-sm">Create</button>
          <button type="button" className="btn btn-neutral btn-sm"
            onClick={() => { setShowNewFolder(false); setNewFolderName(""); }}>Cancel</button>
        </form>
      )}

      {/* ── Upload form ──────────────────────────────────────────────────── */}
      {showUploadForm && canUpload && (
        <form className="tp-form" onSubmit={e => { void handleUpload(e); }}
          style={{ marginBottom: 16, background: "var(--surf)", border: "1px solid var(--bd)", borderRadius: 8, padding: "14px 16px" }}>
          {uploadError && <ErrorMessage message={uploadError} onDismiss={() => setUploadError(null)} />}
          <label className="tp-label">Name *
            <input className="tp-input" value={uploadName} onChange={e => setUploadName(e.target.value)} required />
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
                  <div className="progress-bar"><div className="progress-fill" style={{ width: `${uploadProgress}%` }} /></div>
                  <div className="progress-label">Uploading… {uploadProgress}%</div>
                </>
              )}
            </div>
          </label>
          <label className="tp-label">Tags (comma-separated)
            <input className="tp-input" value={uploadTags} onChange={e => setUploadTags(e.target.value)} placeholder="e.g. template, contract" />
          </label>
          <label className="tp-label">Description
            <textarea className="tp-input tp-textarea" value={uploadDesc} onChange={e => setUploadDesc(e.target.value)} />
          </label>
          <label className="tp-label">Upload notes
            <input className="tp-input" value={uploadNotes} onChange={e => setUploadNotes(e.target.value)} />
          </label>
          <div style={{ display: "flex", gap: 8 }}>
            <button type="submit" className="btn btn-primary" disabled={uploading || !uploadFile}>
              {uploading ? "Uploading…" : "Upload"}
            </button>
            <button type="button" className="btn btn-neutral" onClick={() => setShowUploadForm(false)} disabled={uploading}>
              Cancel
            </button>
          </div>
        </form>
      )}

      {/* ── Filter + Sort toolbar ─────────────────────────────────────────── */}
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 8, flexWrap: "wrap", gap: 6 }}>
        <div style={{ display: "flex", gap: 4 }}>
          {(["All", "Folders", "PDFs", "Docs", "Video", "Images"] as FilterType[]).map(f => (
            <button key={f} onClick={() => setFilterType(f)}
              className={filterType === f ? "btn btn-primary btn-sm" : "btn btn-neutral btn-sm"}
              style={{ fontSize: 11, padding: "3px 10px" }}>
              {f}
            </button>
          ))}
        </div>
        <select className="tp-input" style={{ width: "auto", fontSize: 12, padding: "3px 8px" }}
          value={sortBy} onChange={e => setSortBy(e.target.value as SortBy)}>
          <option value="newest">Newest</option>
          <option value="oldest">Oldest</option>
          <option value="name-az">Name A–Z</option>
          <option value="size">Size</option>
        </select>
      </div>

      {/* ── Drag-drop zone ────────────────────────────────────────────────── */}
      {canUpload && (
        <div style={{
          border: `2px dashed ${dragOver ? "var(--ac)" : "var(--bd)"}`,
          borderRadius: 8, padding: "8px 16px", marginBottom: 16,
          background: dragOver ? "color-mix(in srgb, var(--ac) 6%, transparent)" : "transparent",
          textAlign: "center", fontSize: 12,
          color: dragOver ? "var(--ac)" : "var(--tx2)",
          transition: "all 0.15s",
        }}>
          {dragUploading
            ? <><i className="ti ti-loader" style={{ marginRight: 6 }} />Uploading {dragUploading}…</>
            : <><i className="ti ti-upload" style={{ marginRight: 6 }} />Drag files from your desktop to upload</>}
        </div>
      )}

      {actionError && <ErrorMessage message={actionError} onDismiss={() => setActionError(null)} />}
      {error && <ErrorMessage message={error} />}
      {(loading || searchLoading) && <LoadingSpinner />}

      {searchResults !== null && (
        <div style={{ fontSize: 12, color: "var(--tx2)", marginBottom: 8 }}>
          {searchResults.length} result{searchResults.length !== 1 ? "s" : ""} for "{searchQuery}"
        </div>
      )}

      {/* ── Folders section ──────────────────────────────────────────────── */}
      {filterType !== "PDFs" && filterType !== "Docs" && filterType !== "Video" && filterType !== "Images"
        && !searchResults && displayFolders.length > 0 && (
        <div style={{ marginBottom: 20 }}>
          <div style={{ fontSize: 12, color: "var(--tx2)", textTransform: "uppercase", letterSpacing: "0.05em", marginBottom: 8 }}>
            Folders ({displayFolders.length})
          </div>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(110px, 1fr))", gap: 10 }}>
            {displayFolders.map(folder => {
              const count = folderItemCount(folder.id);
              return (
                <div key={String(folder.id)} onClick={() => enterFolder(folder)}
                  style={{
                    background: "var(--surf)", border: "1px solid var(--bd)", borderRadius: 8,
                    padding: "12px 8px", cursor: "pointer", textAlign: "center",
                    display: "flex", flexDirection: "column", alignItems: "center", gap: 6,
                    transition: "border-color 0.1s",
                  }}
                  onMouseEnter={e => (e.currentTarget.style.borderColor = "var(--ac)")}
                  onMouseLeave={e => (e.currentTarget.style.borderColor = "var(--bd)")}
                >
                  <div style={{ position: "relative" }}>
                    <i className="ti ti-folder-filled" style={{ fontSize: 36, color: "#1976d2" }} />
                    {count > 0 && (
                      <span style={{
                        position: "absolute", bottom: -2, right: -6,
                        background: "var(--surf2)", border: "1px solid var(--bd)",
                        borderRadius: 8, fontSize: 9, padding: "1px 4px", fontWeight: 600,
                      }}>{count}</span>
                    )}
                  </div>
                  <div style={{
                    fontSize: 11, textAlign: "center", wordBreak: "break-word",
                    display: "-webkit-box", WebkitLineClamp: 2, WebkitBoxOrient: "vertical",
                    overflow: "hidden",
                  }}>
                    {folder.name}
                  </div>
                  {canDeleteItem && (
                    <button onClick={e => { e.stopPropagation(); setConfirmDeleteFolder(folder.id); }}
                      style={{ background: "none", border: "none", cursor: "pointer", color: "var(--tx2)", fontSize: 11, padding: "2px 4px" }}
                      title="Delete folder">
                      <i className="ti ti-trash" />
                    </button>
                  )}
                </div>
              );
            })}
          </div>
        </div>
      )}

      {/* ── Files section ────────────────────────────────────────────────── */}
      {filterType !== "Folders" && (
        <div>
          {sortedItems.length > 0 && (
            <div style={{ fontSize: 12, color: "var(--tx2)", textTransform: "uppercase", letterSpacing: "0.05em", marginBottom: 8 }}>
              Files ({sortedItems.length})
            </div>
          )}

          {viewMode === "grid" ? (
            <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(110px, 1fr))", gap: 10 }}>
              {sortedItems.map(({ item, currentVersion: ver }) => {
                const accessCount = accessCountMap.get(String(item.id)) ?? 0;
                const verified = ver.sha256.length > 0;
                return (
                  <div key={String(item.id)}
                    onClick={() => openViewer({ kind: "library", id: item.id, versionId: ver.versionId, filename: ver.filename, contentType: ver.contentType, sizeBytes: ver.sizeBytes })}
                    style={{
                      background: "var(--surf)", border: "1px solid var(--bd)", borderRadius: 8,
                      overflow: "hidden", cursor: "pointer",
                      opacity: item.status !== LibraryItemStatus.Active ? 0.6 : 1,
                      display: "flex", flexDirection: "column",
                      transition: "border-color 0.1s",
                    }}
                    onMouseEnter={e => (e.currentTarget.style.borderColor = "var(--ac)")}
                    onMouseLeave={e => (e.currentTarget.style.borderColor = "var(--bd)")}
                  >
                    {/* Thumbnail */}
                    <div style={{
                      height: 60, display: "flex", alignItems: "center", justifyContent: "center",
                      background: "var(--surf2)", flexShrink: 0, overflow: "hidden",
                    }}>
                      {ver.contentType.startsWith("image/") ? (
                        <ImageThumb versionId={ver.versionId} contentType={ver.contentType} actor={actor} />
                      ) : (
                        <i className={`ti ${fileIcon(ver.contentType)}`} style={{ fontSize: 28, color: "var(--tx2)" }} />
                      )}
                    </div>
                    {/* Info */}
                    <div style={{ padding: "6px 8px", flex: 1, display: "flex", flexDirection: "column", gap: 3 }}>
                      <div style={{
                        fontSize: 11, overflow: "hidden", textOverflow: "ellipsis",
                        whiteSpace: "nowrap",
                      }} title={item.name}>
                        {item.name}
                      </div>
                      <div style={{ display: "flex", gap: 4, flexWrap: "wrap" }}>
                        {verified && (
                          <span style={{
                            fontSize: 9, background: "#dcfce7", color: "#166534",
                            borderRadius: 4, padding: "1px 4px", fontWeight: 600,
                          }}>✓ Verified</span>
                        )}
                        {accessCount > 0 && (
                          <span style={{ fontSize: 9, color: "var(--tx2)" }}>
                            Opened {accessCount}×
                          </span>
                        )}
                      </div>
                    </div>
                  </div>
                );
              })}
              {!loading && sortedItems.length === 0 && (
                <div style={{ gridColumn: "1 / -1", textAlign: "center", padding: "40px 0", color: "var(--tx2)", fontSize: 13 }}>
                  {searchResults !== null ? "No results." : "No files here."}
                </div>
              )}
            </div>
          ) : (
            /* List view */
            <div className="card">
              <table className="tp-table">
                <thead>
                  <tr>
                    <th>Name</th>
                    <th>File</th>
                    <th>Size</th>
                    <th>Tags</th>
                    <th>Status</th>
                    <th>Verified</th>
                    <th></th>
                  </tr>
                </thead>
                <tbody>
                  {sortedItems.map(({ item, currentVersion: ver }) => (
                    <tr key={String(item.id)} style={{ opacity: item.status !== LibraryItemStatus.Active ? 0.6 : 1 }}>
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
                        <span className={item.status === LibraryItemStatus.Active ? "badge badge-active" : "badge badge-archived"}>
                          {item.status}
                        </span>
                      </td>
                      <td>
                        {ver.sha256.length > 0 && (
                          <span style={{ fontSize: 11, background: "#dcfce7", color: "#166534", borderRadius: 4, padding: "1px 6px", fontWeight: 600 }}>✓</span>
                        )}
                      </td>
                      <td>
                        <div style={{ display: "flex", gap: 6 }}>
                          <button className="btn btn-neutral btn-sm"
                            onClick={() => openViewer({ kind: "library", id: item.id, versionId: ver.versionId, filename: ver.filename, contentType: ver.contentType, sizeBytes: ver.sizeBytes })}>
                            View
                          </button>
                          <button className="btn btn-neutral btn-sm"
                            onClick={() => { void handleDownload(item); }}
                            disabled={downloading === item.id}>
                            {downloading === item.id ? "…" : "Download"}
                          </button>
                          {canDeleteItem && item.status === LibraryItemStatus.Active && (
                            <button
                              className="btn btn-danger btn-sm"
                              style={{ border: "1px solid var(--danger, #ef4444)", background: "transparent", color: "var(--danger, #ef4444)" }}
                              onClick={() => { if (window.confirm(`Delete '${item.name}'? This cannot be undone.`)) { void handleDeleteItem(item.id); } }}>
                              Delete
                            </button>
                          )}
                        </div>
                      </td>
                    </tr>
                  ))}
                  {!loading && sortedItems.length === 0 && (
                    <tr><td colSpan={7} className="empty-state">
                      {searchResults !== null ? "No results." : "No files."}
                    </td></tr>
                  )}
                </tbody>
              </table>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
