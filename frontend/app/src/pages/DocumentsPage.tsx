import { useEffect, useRef, useState } from "react";
import { useParams } from "react-router-dom";
import { useDocuments } from "../hooks/useDocuments";
import { useAuth } from "../auth/useAuth";
import { Role, DocumentStatus } from "../backend/api/backend";
import type { Document, DocumentVersion } from "../backend/api/backend";
import LoadingSpinner from "../components/LoadingSpinner";
import ErrorMessage from "../components/ErrorMessage";
import ConfirmDialog from "../components/ConfirmDialog";

const ALLOWED_TYPES = ["application/pdf", "application/vnd.openxmlformats-officedocument.wordprocessingml.document", "image/png", "image/jpeg"];
const MAX_SIZE = 100 * 1024 * 1024; // 100 MB

export default function DocumentsPage() {
  const { id } = useParams<{ id: string }>();
  const matterId = BigInt(id ?? "0");
  const { role } = useAuth();
  const { documents, loading, error, load, upload, download, deleteDocument, getVersion } = useDocuments(matterId);

  const fileRef = useRef<HTMLInputElement>(null);
  const [uploadError, setUploadError] = useState<string | null>(null);
  const [uploading, setUploading] = useState(false);
  const [progress, setProgress] = useState(0);
  const [actionError, setActionError] = useState<string | null>(null);
  const [confirmDelete, setConfirmDelete] = useState<bigint | null>(null);
  const [versions, setVersions] = useState<Map<bigint, DocumentVersion>>(new Map());
  const [downloading, setDownloading] = useState<bigint | null>(null);

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
      <h1 style={{ marginTop: 0 }}>Documents — Matter {id}</h1>

      {confirmDelete !== null && (
        <ConfirmDialog
          message="Delete this document? This cannot be undone."
          onConfirm={() => { void handleDelete(); }}
          onCancel={() => setConfirmDelete(null)}
        />
      )}

      {/* Upload area */}
      <div style={{ background: "#f9f9f9", padding: "1rem", borderRadius: 8, marginBottom: "1rem" }}>
        <input
          ref={fileRef}
          type="file"
          accept=".pdf,.docx,.png,.jpg,.jpeg"
          onChange={(e) => { void handleFileChange(e); }}
          disabled={uploading}
        />
        {uploading && (
          <div style={{ marginTop: "0.5rem" }}>
            <div style={{ background: "#ddd", borderRadius: 4, height: 8 }}>
              <div style={{ background: "#1a1a2e", height: 8, borderRadius: 4, width: `${progress}%`, transition: "width 0.2s" }} />
            </div>
            <div style={{ fontSize: "0.8rem", color: "#555", marginTop: 4 }}>Uploading… {progress}%</div>
          </div>
        )}
        {uploadError && <ErrorMessage message={uploadError} onDismiss={() => setUploadError(null)} />}
      </div>

      {actionError && <ErrorMessage message={actionError} onDismiss={() => setActionError(null)} />}
      {error && <ErrorMessage message={error} />}
      {loading && <LoadingSpinner />}

      <table style={{ width: "100%", borderCollapse: "collapse" }}>
        <thead>
          <tr style={{ background: "#f0f0f0" }}>
            <th style={thStyle}>ID</th>
            <th style={thStyle}>Filename</th>
            <th style={thStyle}>Type</th>
            <th style={thStyle}>Size</th>
            <th style={thStyle}>Status</th>
            <th style={thStyle}>Actions</th>
          </tr>
        </thead>
        <tbody>
          {documents.map(doc => {
            const ver = versions.get(doc.id);
            return (
              <tr key={String(doc.id)} style={{ borderBottom: "1px solid #eee", opacity: doc.status === DocumentStatus.Deleted ? 0.5 : 1 }}>
                <td style={tdStyle}>{String(doc.id)}</td>
                <td style={tdStyle}>{ver?.filename ?? "…"}</td>
                <td style={tdStyle}>{ver?.contentType ?? "…"}</td>
                <td style={tdStyle}>{ver ? formatBytes(ver.sizeBytes) : "…"}</td>
                <td style={tdStyle}>{doc.status}</td>
                <td style={tdStyle}>
                  {doc.status === DocumentStatus.Active && (
                    <>
                      <button
                        onClick={() => { void handleDownload(doc); }}
                        disabled={downloading === doc.id}
                        style={smallBtn}
                      >
                        {downloading === doc.id ? "…" : "Download"}
                      </button>
                      {role === Role.Partner && (
                        <button onClick={() => setConfirmDelete(doc.id)} style={{ ...smallBtn, background: "#c00", marginLeft: 4 }}>
                          Delete
                        </button>
                      )}
                    </>
                  )}
                </td>
              </tr>
            );
          })}
          {!loading && documents.length === 0 && (
            <tr><td colSpan={6} style={{ padding: "1rem", color: "#888", textAlign: "center" }}>No documents.</td></tr>
          )}
        </tbody>
      </table>
    </div>
  );
}

function formatBytes(bytes: bigint) {
  const n = Number(bytes);
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  return `${(n / (1024 * 1024)).toFixed(1)} MB`;
}

const thStyle: React.CSSProperties = { padding: "0.5rem", textAlign: "left", fontWeight: 600 };
const tdStyle: React.CSSProperties = { padding: "0.5rem" };
const smallBtn: React.CSSProperties = { padding: "0.3rem 0.6rem", background: "#1a1a2e", color: "#fff", border: "none", borderRadius: 4, cursor: "pointer", fontSize: "0.85rem" };
