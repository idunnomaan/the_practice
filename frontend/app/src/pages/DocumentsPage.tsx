import { useEffect, useRef, useState } from "react";
import { useParams, Link } from "react-router-dom";
import { useDocuments } from "../hooks/useDocuments";
import { useMatters } from "../hooks/useMatters";
import { useAuth } from "../auth/useAuth";
import { Role, DocumentStatus } from "../backend/api/backend";
import type { Document, DocumentVersion, DocumentSearchResult } from "../backend/api/backend";
import LoadingSpinner from "../components/LoadingSpinner";
import ErrorMessage from "../components/ErrorMessage";
import ConfirmDialog from "../components/ConfirmDialog";
import { useFileViewer } from "../state/fileViewerStore";

const ALLOWED_TYPES = ["application/pdf", "application/vnd.openxmlformats-officedocument.wordprocessingml.document", "image/png", "image/jpeg"];
const MAX_SIZE = 100 * 1024 * 1024; // 100 MB

function fileIcon(contentType?: string) {
  if (!contentType) return "ti-file";
  if (contentType === "application/pdf") return "ti-file-type-pdf";
  if (contentType.startsWith("image/")) return "ti-photo";
  return "ti-file-text";
}

function docStatusBadge(status: string) {
  return status === "Active" ? "badge badge-active" : "badge badge-archived";
}

export default function DocumentsPage() {
  const { id } = useParams<{ id: string }>();
  const matterId = BigInt(id ?? "0");
  const { role, actor } = useAuth();
  const { openViewer } = useFileViewer();
  const { documents, loading, error, load, upload, download, deleteDocument, getVersion } = useDocuments(matterId);
  const { getMatter } = useMatters();
  const [matterTitle, setMatterTitle] = useState<string | null>(null);

  useEffect(() => {
    if (id) {
      getMatter(BigInt(id)).then(m => { if (m) setMatterTitle(m.title); });
    }
  }, [id]); // eslint-disable-line react-hooks/exhaustive-deps

  const fileRef = useRef<HTMLInputElement>(null);
  const [uploadError, setUploadError] = useState<string | null>(null);
  const [uploading, setUploading] = useState(false);
  const [progress, setProgress] = useState(0);
  const [actionError, setActionError] = useState<string | null>(null);
  const [confirmDelete, setConfirmDelete] = useState<bigint | null>(null);
  const [versions, setVersions] = useState<Map<bigint, DocumentVersion>>(new Map());
  const [downloading, setDownloading] = useState<bigint | null>(null);
  const [searchQuery, setSearchQuery] = useState("");
  const [searchResults, setSearchResults] = useState<DocumentSearchResult[] | null>(null);
  const [searchLoading, setSearchLoading] = useState(false);

  useEffect(() => { void load(); }, [load]);

  async function loadVersions(docs: Document[]) {
    const map = new Map<bigint, DocumentVersion>();
    for (const doc of docs) {
      const v = await getVersion(doc.currentVersionId);
      if (v) map.set(doc.id, v);
    }
    setVersions(map);
  }

  useEffect(() => {
    if (documents.length > 0) void loadVersions(documents);
  }, [documents]); // eslint-disable-line react-hooks/exhaustive-deps

  async function handleFileChange(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;
    setUploadError(null);

    if (!ALLOWED_TYPES.includes(file.type)) {
      setUploadError("Unsupported file type. Allowed: PDF, DOCX, PNG, JPEG.");
      return;
    }
    if (file.size > MAX_SIZE) {
      setUploadError("File too large. Maximum 100 MB.");
      return;
    }

    setUploading(true);
    setProgress(0);
    const result = await upload(file, (pct) => setProgress(pct));
    setUploading(false);
    if (result.__kind__ === "err") {
      setUploadError(result.err);
    } else {
      void load();
    }
    if (fileRef.current) fileRef.current.value = "";
  }

  async function handleDownload(doc: Document) {
    setDownloading(doc.id);
    setActionError(null);
    try {
      await download(doc);
    } catch (e) {
      setActionError(String(e));
    } finally {
      setDownloading(null);
    }
  }

  async function handleSearch(e: React.FormEvent) {
    e.preventDefault();
    if (!actor || !searchQuery.trim()) { setSearchResults(null); return; }
    setSearchLoading(true);
    try {
      const results = await actor.searchDocuments(
        { filenameContains: searchQuery.trim(), matterId: matterId },
        0n, 200n,
      );
      setSearchResults(results);
    } catch {
      setSearchResults([]);
    } finally {
      setSearchLoading(false);
    }
  }

  async function handleDelete() {
    if (confirmDelete === null) return;
    const docId = confirmDelete;
    setConfirmDelete(null);
    setActionError(null);
    const result = await deleteDocument(docId);
    if (!result) return;
    if (result.__kind__ === "err") setActionError(result.err);
    else void load();
  }

  return (
    <div>
      <div style={{ fontSize: "0.8rem", color: "#888", marginBottom: "0.5rem" }}>
        <Link to={`/matters/${id}`} style={{ color: "#888" }}>← Matter {matterTitle ?? id}</Link>
      </div>
      <div className="page-header">
        <div className="page-title">Documents — {matterTitle ?? `Matter ${id}`}</div>
        <button className="add-btn" onClick={() => fileRef.current?.click()} disabled={uploading}>
          <i className="ti ti-upload" /> Upload document
        </button>
      </div>

      {confirmDelete !== null && (
        <ConfirmDialog
          message="Delete this document? This cannot be undone."
          onConfirm={() => { void handleDelete(); }}
          onCancel={() => setConfirmDelete(null)}
        />
      )}

      <div>
        <input
          ref={fileRef}
          type="file"
          accept=".pdf,.docx,.png,.jpg,.jpeg"
          onChange={(e) => { void handleFileChange(e); }}
          disabled={uploading}
          style={{ display: "none" }}
        />
        {uploading && (
          <>
            <div className="progress-bar">
              <div className="progress-fill" style={{ width: `${progress}%` }} />
            </div>
            <div className="progress-label">Uploading… {progress}%</div>
          </>
        )}
        {uploadError && <ErrorMessage message={uploadError} onDismiss={() => setUploadError(null)} />}
      </div>

      {actionError && <ErrorMessage message={actionError} onDismiss={() => setActionError(null)} />}
      {error && <ErrorMessage message={error} />}
      {(loading || searchLoading) && <LoadingSpinner />}

      <form onSubmit={(e) => { void handleSearch(e); }}
        style={{ display: "flex", gap: 6, marginBottom: 12 }}>
        <input
          className="tp-input"
          style={{ flex: 1 }}
          value={searchQuery}
          onChange={e => setSearchQuery(e.target.value)}
          placeholder="Search by filename…"
        />
        <button type="submit" className="btn btn-neutral" disabled={!searchQuery.trim() || searchLoading}>
          <i className="ti ti-search" /> Search
        </button>
        {searchResults !== null && (
          <button type="button" className="btn btn-neutral"
            onClick={() => { setSearchQuery(""); setSearchResults(null); }}>
            Clear
          </button>
        )}
      </form>

      <div className="card">
        {searchResults !== null && (
          <div style={{ fontSize: 12, color: "var(--tx2)", marginBottom: 8 }}>
            Showing {searchResults.length} result{searchResults.length !== 1 ? "s" : ""} for "{searchQuery}"
          </div>
        )}
        <table className="tp-table">
          <thead>
            <tr>
              <th style={{ textTransform: "none" }}>File</th>
              <th style={{ textTransform: "none" }}>Type</th>
              <th style={{ textTransform: "none" }}>Size</th>
              <th style={{ textTransform: "none" }}>Status</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {searchResults !== null
              ? searchResults.map(({ document: doc, currentVersion: ver }) => (
                <tr key={String(doc.id)} style={{ opacity: doc.status === DocumentStatus.Deleted ? 0.5 : 1 }}>
                  <td>
                    <i className={`ti ${fileIcon(ver.contentType)} file-icon`} />
                    {ver.filename}
                  </td>
                  <td style={{ color: "var(--tx2)", fontSize: 12 }}>{ver.contentType}</td>
                  <td>{formatBytes(ver.sizeBytes)}</td>
                  <td><span className={docStatusBadge(doc.status)}>{doc.status}</span></td>
                  <td>
                    {doc.status === DocumentStatus.Active && (
                      <div style={{ display: "flex", gap: 6 }}>
                        <button
                          className="btn btn-neutral btn-sm"
                          onClick={() => openViewer({
                            kind: "document", id: doc.id, versionId: ver!.versionId,
                            filename: ver!.filename, contentType: ver!.contentType, sizeBytes: ver!.sizeBytes,
                          })}
                          disabled={!ver}
                        >
                          View
                        </button>
                        <button
                          className="btn btn-neutral btn-sm"
                          onClick={() => { void handleDownload(doc); }}
                          disabled={downloading === doc.id}
                        >
                          {downloading === doc.id ? "…" : "Download"}
                        </button>
                        {role === Role.Partner && (
                          <button className="btn btn-danger btn-sm" onClick={() => setConfirmDelete(doc.id)}>
                            Delete
                          </button>
                        )}
                      </div>
                    )}
                  </td>
                </tr>
              ))
              : documents.map(doc => {
                const ver = versions.get(doc.id);
                return (
                  <tr key={String(doc.id)} style={{ opacity: doc.status === DocumentStatus.Deleted ? 0.5 : 1 }}>
                    <td>
                      <i className={`ti ${fileIcon(ver?.contentType)} file-icon`} />
                      {ver?.filename ?? "…"}
                    </td>
                    <td style={{ color: "var(--tx2)", fontSize: 12 }}>{ver?.contentType ?? "…"}</td>
                    <td>{ver ? formatBytes(ver.sizeBytes) : "…"}</td>
                    <td><span className={docStatusBadge(doc.status)}>{doc.status}</span></td>
                    <td>
                      {doc.status === DocumentStatus.Active && (
                        <div style={{ display: "flex", gap: 6 }}>
                          <button
                            className="btn btn-neutral btn-sm"
                            onClick={() => ver && openViewer({
                              kind: "document", id: doc.id, versionId: ver.versionId,
                              filename: ver.filename, contentType: ver.contentType, sizeBytes: ver.sizeBytes,
                            })}
                            disabled={!ver}
                          >
                            View
                          </button>
                          <button
                            className="btn btn-neutral btn-sm"
                            onClick={() => { void handleDownload(doc); }}
                            disabled={downloading === doc.id}
                          >
                            {downloading === doc.id ? "…" : "Download"}
                          </button>
                          {role === Role.Partner && (
                            <button className="btn btn-danger btn-sm" onClick={() => setConfirmDelete(doc.id)}>
                              Delete
                            </button>
                          )}
                        </div>
                      )}
                    </td>
                  </tr>
                );
              })
            }
            {!loading && !searchLoading && (searchResults ?? documents).length === 0 && (
              <tr><td colSpan={5} className="empty-state">
                {searchResults !== null ? "No results." : "No documents."}
              </td></tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function formatBytes(bytes: bigint) {
  const n = Number(bytes);
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  return `${(n / (1024 * 1024)).toFixed(1)} MB`;
}
