import { useEffect, useState } from "react";
import { useParams, Link } from "react-router-dom";
import { useMatters } from "../hooks/useMatters";
import { useDocuments } from "../hooks/useDocuments";
import { useAuth } from "../auth/useAuth";
import { useFileViewer } from "../state/fileViewerStore";
import type { Matter, Client, Document, DocumentVersion } from "../backend/api/backend";
import LoadingSpinner from "../components/LoadingSpinner";
import ErrorMessage from "../components/ErrorMessage";

// ── Helpers ──────────────────────────────────────────────────────────────────

const STATUS_COLOR: Record<string, string> = {
  Open: "#1976d2", OnHold: "#f9a825", Closed: "#78909c", Archived: "#c62828",
};
const STATUS_BADGE: Record<string, string> = {
  Open: "badge badge-open", OnHold: "badge badge-hold",
  Closed: "badge badge-closed", Archived: "badge badge-archived",
};

function statusLabel(s: string) { return s === "OnHold" ? "On hold" : s; }
function fmtClientId(id: bigint) { return "CLT-" + String(id).padStart(4, "0"); }
function daysOpen(ns: bigint) { return Math.floor((Date.now() - Number(ns / 1_000_000n)) / 86_400_000); }
function truncPrincipal(p?: { toText(): string }): string {
  if (!p) return "Unassigned";
  const t = p.toText();
  return t.slice(0, 8) + "…" + t.slice(-4);
}
function fmtDate(ns: bigint) {
  return new Date(Number(ns / 1_000_000n)).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" });
}
function docTypeIcon(ct: string) {
  if (ct === "application/pdf") return "ti-file-type-pdf";
  if (ct.startsWith("image/")) return "ti-photo";
  if (ct.includes("word")) return "ti-file-word";
  return "ti-file";
}

// ── Page ──────────────────────────────────────────────────────────────────────

export default function MatterDetailPage() {
  const { id } = useParams<{ id: string }>();
  const matterId = BigInt(id ?? "0");

  const { getMatter, updateMatter, closeMatter, putOnHold, resumeMatter, reopenMatter, archiveMatter } = useMatters();
  const { documents, loading: docsLoading, load: loadDocs, getVersion } = useDocuments(matterId);
  const { actor } = useAuth();
  const { openViewer } = useFileViewer();

  const [matter, setMatter] = useState<Matter | null>(null);
  const [client, setClient] = useState<Client | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  // log count for sidebar Activity section
  const [logCount, setLogCount] = useState<{ count: number; more: boolean } | null>(null);
  // document versions for sidebar chips
  const [docVersions, setDocVersions] = useState<Map<string, DocumentVersion>>(new Map());

  // edit form
  const [editing, setEditing] = useState(false);
  const [editTitle, setEditTitle] = useState("");
  const [editDescription, setEditDescription] = useState("");

  async function loadMatter() {
    if (!id || !actor) return;
    setLoading(true);
    setError(null);
    const m = await getMatter(BigInt(id));
    setLoading(false);
    if (!m) { setError("Matter not found."); return; }
    setMatter(m);
    setEditTitle(m.title);
    setEditDescription(m.description);
    // load client name
    actor.getClient(m.clientId).then(c => setClient(c ?? null)).catch(() => {});
    // load log count (limit 1 just for the count indicator)
    actor.getMatterLogs(m.id, null, 50n).then(r => {
      if (r.__kind__ === "ok") setLogCount({ count: r.ok.entries.length, more: r.ok.hasMore });
    }).catch(() => {});
  }

  useEffect(() => { void loadMatter(); void loadDocs(); }, [id]); // eslint-disable-line react-hooks/exhaustive-deps

  // Load current version per document for filename/contentType
  useEffect(() => {
    if (documents.length === 0) return;
    Promise.all(documents.map(async d => {
      const v = await getVersion(d.currentVersionId);
      return v ? [String(d.id), v] as const : null;
    })).then(results => {
      const map = new Map<string, DocumentVersion>();
      for (const r of results) { if (r) map.set(r[0], r[1]); }
      setDocVersions(map);
    }).catch(() => {});
  }, [documents, getVersion]);

  async function handleTransition(fn: (id: bigint) => Promise<{ __kind__: "ok"; ok: null } | { __kind__: "err"; err: string } | null>) {
    if (!matter) return;
    setSubmitting(true);
    setError(null);
    const result = await fn(matter.id);
    setSubmitting(false);
    if (!result) return;
    if (result.__kind__ === "err") setError(result.err);
    else void loadMatter();
  }

  async function handleUpdate(e: React.FormEvent) {
    e.preventDefault();
    if (!matter) return;
    setSubmitting(true);
    setError(null);
    const result = await updateMatter(matter.id, editTitle.trim() || null, editDescription.trim() || null);
    setSubmitting(false);
    if (!result) return;
    if (result.__kind__ === "ok") { setEditing(false); void loadMatter(); }
    else setError(result.err);
  }

  function openDocViewer(doc: Document) {
    const ver = docVersions.get(String(doc.id));
    if (!ver) return;
    openViewer({
      kind: "document",
      id: doc.id,
      versionId: ver.versionId,
      filename: ver.filename,
      contentType: ver.contentType,
      sizeBytes: ver.sizeBytes,
    });
  }

  if (loading) return <LoadingSpinner />;
  if (!matter) return <ErrorMessage message={error ?? "Matter not found."} />;

  const sc = STATUS_COLOR[matter.status] ?? "#78909c";
  const days = daysOpen(matter.createdAt);

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 0 }}>

      {/* ── Breadcrumb + action row ─────────────────────────────────────────── */}
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 12 }}>
        <div style={{ fontSize: 13, color: "var(--tx2)" }}>
          <Link to="/matters" style={{ color: "var(--tx2)" }}>← Matters</Link>
          <span style={{ margin: "0 6px" }}>·</span>
          <span style={{ color: "var(--tx)" }}>{matter.title}</span>
        </div>
        <div style={{ display: "flex", gap: 6 }}>
          {matter.status === "Open" && (
            <>
              <button className="btn btn-warning btn-sm" disabled={submitting} onClick={() => { void handleTransition(putOnHold); }}>Put on hold</button>
              <button className="btn btn-neutral btn-sm" disabled={submitting} onClick={() => { void handleTransition(closeMatter); }}>Close</button>
            </>
          )}
          {matter.status === "OnHold" && (
            <>
              <button className="btn btn-success btn-sm" disabled={submitting} onClick={() => { void handleTransition(resumeMatter); }}>Resume</button>
              <button className="btn btn-neutral btn-sm" disabled={submitting} onClick={() => { void handleTransition(closeMatter); }}>Close</button>
            </>
          )}
          {matter.status === "Closed" && (
            <>
              <button className="btn btn-success btn-sm" disabled={submitting} onClick={() => { void handleTransition(reopenMatter); }}>Reopen</button>
              <button className="btn btn-neutral btn-sm" disabled={submitting} onClick={() => { void handleTransition(archiveMatter); }}>Archive</button>
            </>
          )}
          {matter.status === "Archived" && (
            <span style={{ fontSize: 12, color: "var(--tx2)" }}>Archived — terminal state</span>
          )}
        </div>
      </div>

      {/* ── Header band ────────────────────────────────────────────────────── */}
      <div style={{
        borderLeft: `3px solid ${sc}`,
        paddingLeft: 14,
        marginBottom: 20,
        background: "var(--surf)",
        border: `1px solid var(--bd)`,
        borderLeftWidth: 3,
        borderLeftColor: sc,
        borderRadius: 8,
        padding: "14px 16px 14px 16px",
        borderLeftStyle: "solid",
      }}>
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 12 }}>
          {!editing ? (
            <div style={{ fontWeight: 700, fontSize: 20, lineHeight: 1.2 }}>{matter.title}</div>
          ) : (
            <form style={{ flex: 1 }} onSubmit={(e) => { void handleUpdate(e); }}>
              <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
                <input className="tp-input" style={{ flex: 1, minWidth: 200 }} value={editTitle} onChange={e => setEditTitle(e.target.value)} required />
                <button type="submit" className="btn btn-primary btn-sm" disabled={submitting}>{submitting ? "Saving…" : "Save"}</button>
                <button type="button" className="btn btn-neutral btn-sm" onClick={() => setEditing(false)}>Cancel</button>
              </div>
            </form>
          )}
          <div style={{ display: "flex", alignItems: "center", gap: 8, flexShrink: 0 }}>
            <span className={STATUS_BADGE[matter.status] ?? "badge badge-closed"} style={{ fontSize: 11 }}>
              {statusLabel(matter.status)}
            </span>
            <span style={{ fontSize: 12, color: "var(--tx2)" }}>{days}d open</span>
            {!editing && (
              <button className="btn btn-neutral btn-sm" onClick={() => setEditing(true)} title="Edit">
                <i className="ti ti-pencil" />
              </button>
            )}
          </div>
        </div>
        {/* Meta row */}
        {!editing && (
          <div style={{ display: "flex", gap: 12, marginTop: 6, fontSize: 12, color: "var(--tx2)", flexWrap: "wrap", alignItems: "center" }}>
            <Link to={`/clients/${matter.clientId}`} style={{ color: "var(--tx2)", fontFamily: "monospace" }}>
              {fmtClientId(matter.clientId)}
            </Link>
            {client && <span>{client.name}</span>}
            <span>·</span>
            <span>Assigned: {truncPrincipal(matter.assignedPartner)}</span>
            {matter.matterType && <><span>·</span><span>Type: {matter.matterType}</span></>}
            <span>·</span>
            <span>{docsLoading ? "—" : documents.length} doc{documents.length !== 1 ? "s" : ""}</span>
            {logCount !== null && (
              <><span>·</span><span>{logCount.more ? logCount.count + "+" : logCount.count} log entr{logCount.count !== 1 || logCount.more ? "ies" : "y"}</span></>
            )}
          </div>
        )}
        {editing && (
          <div style={{ marginTop: 8 }}>
            <label className="tp-label" style={{ fontSize: 12 }}>Description
              <textarea className="tp-input tp-textarea" style={{ fontSize: 13 }} value={editDescription} onChange={e => setEditDescription(e.target.value)} />
            </label>
          </div>
        )}
      </div>

      {error && <ErrorMessage message={error} onDismiss={() => setError(null)} />}

      {/* ── Two-column body ─────────────────────────────────────────────────── */}
      <div style={{ display: "flex", gap: 20, alignItems: "flex-start" }}>

        {/* Left — Case log (placeholder, wired in Commit 5) */}
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 12 }}>
            <div style={{ fontWeight: 600, fontSize: 15 }}>Case log</div>
          </div>
          {/* TIMELINE_SLOT — replaced in next commit with full MatterLog timeline */}
          <div style={{
            border: "1px dashed var(--bd)", borderRadius: 8, padding: 32,
            textAlign: "center", color: "var(--tx2)", fontSize: 13,
          }}>
            Case log timeline coming in next commit.
          </div>
        </div>

        {/* Right sidebar */}
        <div style={{ width: 240, flexShrink: 0, display: "flex", flexDirection: "column", gap: 0 }}>

          {/* Section 1: Matter details */}
          <div className="card" style={{ padding: "14px 16px", marginBottom: 12 }}>
            <div style={{ fontWeight: 600, fontSize: 13, marginBottom: 10 }}>Matter details</div>
            <div style={{ display: "flex", flexDirection: "column", gap: 7, fontSize: 12 }}>
              <div style={{ display: "flex", justifyContent: "space-between" }}>
                <span style={{ color: "var(--tx2)" }}>Opened</span>
                <span>{fmtDate(matter.createdAt)}</span>
              </div>
              <div style={{ display: "flex", justifyContent: "space-between", gap: 8 }}>
                <span style={{ color: "var(--tx2)", flexShrink: 0 }}>Partner</span>
                <span style={{ fontFamily: "monospace", fontSize: 11, textAlign: "right" }}>{truncPrincipal(matter.assignedPartner)}</span>
              </div>
              <div style={{ display: "flex", justifyContent: "space-between" }}>
                <span style={{ color: "var(--tx2)" }}>Client</span>
                <Link to={`/clients/${matter.clientId}`} style={{ fontFamily: "monospace", fontSize: 11 }}>
                  {fmtClientId(matter.clientId)}
                </Link>
              </div>
              {matter.matterType && (
                <div style={{ display: "flex", justifyContent: "space-between", gap: 8 }}>
                  <span style={{ color: "var(--tx2)", flexShrink: 0 }}>Type</span>
                  <span style={{ textAlign: "right", fontSize: 11 }}>{matter.matterType}</span>
                </div>
              )}
              {matter.description && (
                <div style={{ color: "var(--tx2)", fontSize: 11, marginTop: 4, lineHeight: 1.4 }}>
                  {matter.description}
                </div>
              )}
            </div>
          </div>

          {/* Section 2: Documents */}
          <div className="card" style={{ padding: "14px 16px", marginBottom: 12 }}>
            <div style={{ fontWeight: 600, fontSize: 13, marginBottom: 10 }}>
              Documents ({docsLoading ? "…" : documents.length})
            </div>
            {documents.length === 0 && !docsLoading && (
              <div style={{ fontSize: 12, color: "var(--tx2)", marginBottom: 8 }}>No documents yet.</div>
            )}
            <div style={{ display: "flex", flexDirection: "column", gap: 4, marginBottom: 10 }}>
              {documents.slice(0, 10).map(doc => {
                const ver = docVersions.get(String(doc.id));
                return (
                  <button
                    key={String(doc.id)}
                    onClick={() => openDocViewer(doc)}
                    disabled={!ver}
                    style={{
                      display: "flex", alignItems: "center", gap: 6,
                      padding: "5px 8px", borderRadius: 6, cursor: ver ? "pointer" : "default",
                      background: "var(--surf2)", border: "none",
                      textAlign: "left", width: "100%",
                    }}
                    title={ver?.filename ?? "Loading…"}
                  >
                    <i className={`ti ${docTypeIcon(ver?.contentType ?? "")}`} style={{ fontSize: 13, flexShrink: 0, color: "var(--tx2)" }} />
                    <span style={{ fontSize: 11, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", color: "var(--tx)" }}>
                      {ver?.filename ?? "…"}
                    </span>
                  </button>
                );
              })}
              {documents.length > 10 && (
                <Link to={`/matters/${matter.id}/documents`} style={{ fontSize: 11, color: "var(--tx2)", textAlign: "center", paddingTop: 4 }}>
                  +{documents.length - 10} more…
                </Link>
              )}
            </div>
            <Link to={`/matters/${matter.id}/documents`} className="btn btn-neutral btn-sm btn-full">
              <i className="ti ti-files" style={{ fontSize: 13 }} /> All documents
            </Link>
          </div>

          {/* Section 3: Activity */}
          <div className="card" style={{ padding: "14px 16px" }}>
            <div style={{ fontWeight: 600, fontSize: 13, marginBottom: 10 }}>Activity</div>
            <div style={{ display: "flex", flexDirection: "column", gap: 6, fontSize: 12 }}>
              <div style={{ display: "flex", justifyContent: "space-between" }}>
                <span style={{ color: "var(--tx2)" }}>Documents</span>
                <span>{docsLoading ? "—" : documents.length}</span>
              </div>
              <div style={{ display: "flex", justifyContent: "space-between" }}>
                <span style={{ color: "var(--tx2)" }}>Log entries</span>
                <span>{logCount === null ? "—" : logCount.more ? logCount.count + "+" : logCount.count}</span>
              </div>
              <div style={{ display: "flex", justifyContent: "space-between" }}>
                <span style={{ color: "var(--tx2)" }}>Last updated</span>
                <span style={{ fontSize: 11 }}>{fmtDate(matter.lastModifiedAt)}</span>
              </div>
            </div>
          </div>

        </div>
      </div>
    </div>
  );
}
