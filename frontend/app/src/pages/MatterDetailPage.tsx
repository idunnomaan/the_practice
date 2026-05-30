import { useEffect, useRef, useState } from "react";
import { useParams, Link } from "react-router-dom";
import { useMatters } from "../hooks/useMatters";
import { useDocuments } from "../hooks/useDocuments";
import { useAuth } from "../auth/useAuth";
import { useFileViewer } from "../state/fileViewerStore";
import { Role, SystemEventKind } from "../backend/api/backend";
import type { Matter, Client, Document, DocumentVersion, MatterLogEntry } from "../backend/api/backend";
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
function fmtDateTime(ns: bigint) {
  const d = new Date(Number(ns / 1_000_000n));
  return d.toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) + ", "
    + d.toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" });
}
function docTypeIcon(ct: string) {
  if (ct === "application/pdf") return "ti-file-type-pdf";
  if (ct.startsWith("image/")) return "ti-photo";
  if (ct.includes("word")) return "ti-file-word";
  return "ti-file";
}

const SYSTEM_EVENT_META: Record<string, { icon: string; label: string }> = {
  [SystemEventKind.MatterOpened]:    { icon: "ti-circle",       label: "Matter opened" },
  [SystemEventKind.MatterPutOnHold]: { icon: "ti-player-pause", label: "Matter put on hold" },
  [SystemEventKind.MatterResumed]:   { icon: "ti-player-play",  label: "Matter resumed" },
  [SystemEventKind.MatterClosed]:    { icon: "ti-circle-check", label: "Matter closed" },
  [SystemEventKind.MatterArchived]:  { icon: "ti-archive",      label: "Matter archived" },
};

const MAX_NOTE = 4096;
const MAX_ATTACHMENTS = 50;
const PAGE_LIMIT = 50n;

// ── Timeline entry components ─────────────────────────────────────────────────

function SessionNoteEntry({ entry, docMeta }: {
  entry: MatterLogEntry;
  docMeta: Map<string, { filename: string; contentType: string }>;
}) {
  return (
    <div style={{ display: "flex", gap: 12, paddingBottom: 16 }}>
      <div style={{ display: "flex", flexDirection: "column", alignItems: "center" }}>
        <div style={{
          width: 10, height: 10, borderRadius: "50%",
          background: "var(--ac)", marginTop: 4, flexShrink: 0,
        }} />
        <div style={{ width: 1, flex: 1, background: "var(--bd)", marginTop: 4 }} />
      </div>
      <div style={{ flex: 1, minWidth: 0, paddingBottom: 4 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 6 }}>
          <span style={{ fontWeight: 600, fontSize: 13 }}>{truncPrincipal(entry.author)}</span>
          <span style={{ fontSize: 11, color: "var(--tx2)" }}>·</span>
          <span style={{ fontSize: 11, color: "var(--tx2)" }}>{fmtDateTime(entry.createdAt)}</span>
          <span className="badge" style={{ fontSize: 10, padding: "1px 7px", background: "var(--surf2)", color: "var(--tx2)" }}>
            Session note
          </span>
        </div>
        <div style={{
          background: "var(--surf)", border: "1px solid var(--bd)", borderRadius: 8,
          padding: "10px 14px", fontSize: 13, lineHeight: 1.5,
          whiteSpace: "pre-wrap", wordBreak: "break-word",
        }}>
          {entry.note}
        </div>
        {entry.attachedDocumentIds.length > 0 && (
          <div style={{ display: "flex", gap: 6, flexWrap: "wrap", marginTop: 8 }}>
            {entry.attachedDocumentIds.map(docId => {
              const meta = docMeta.get(String(docId));
              return (
                <span key={String(docId)} style={{
                  display: "inline-flex", alignItems: "center", gap: 4,
                  background: "var(--surf2)", borderRadius: 6,
                  padding: "3px 8px", fontSize: 11, color: "var(--tx2)",
                }}>
                  <i className={`ti ${docTypeIcon(meta?.contentType ?? "")}`} style={{ fontSize: 12 }} />
                  {meta?.filename ?? String(docId)}
                </span>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}

function SystemEventEntry({ entry }: { entry: MatterLogEntry }) {
  if (entry.kind.__kind__ !== "SystemEvent") return null;
  const kind = entry.kind.SystemEvent;
  const meta = SYSTEM_EVENT_META[kind] ?? { icon: "ti-point", label: kind };
  return (
    <div style={{ display: "flex", gap: 12, paddingBottom: 12 }}>
      <div style={{ display: "flex", flexDirection: "column", alignItems: "center" }}>
        <div style={{
          width: 10, height: 10, borderRadius: "50%",
          border: "2px solid var(--bd)", background: "var(--surf)", marginTop: 4, flexShrink: 0,
        }} />
        <div style={{ width: 1, flex: 1, background: "var(--bd)", marginTop: 4 }} />
      </div>
      <div style={{ flex: 1, display: "flex", alignItems: "center", gap: 8, paddingTop: 2, paddingBottom: 4 }}>
        <i className={`ti ${meta.icon}`} style={{ fontSize: 13, color: "var(--tx2)" }} />
        <span style={{ fontSize: 12, fontWeight: 500, color: "var(--tx2)" }}>{meta.label}</span>
        <span style={{ fontSize: 11, color: "var(--tx2)" }}>·</span>
        <span style={{ fontSize: 11, color: "var(--tx2)" }}>{truncPrincipal(entry.author)}</span>
        <span style={{ fontSize: 11, color: "var(--tx2)" }}>·</span>
        <span style={{ fontSize: 11, color: "var(--tx2)" }}>{fmtDateTime(entry.createdAt)}</span>
      </div>
    </div>
  );
}

// ── Page ──────────────────────────────────────────────────────────────────────

export default function MatterDetailPage() {
  const { id } = useParams<{ id: string }>();
  const matterId = BigInt(id ?? "0");

  const { getMatter, updateMatter, closeMatter, putOnHold, resumeMatter, reopenMatter, archiveMatter } = useMatters();
  const { documents, loading: docsLoading, load: loadDocs, getVersion, upload } = useDocuments(matterId);
  const { actor, role } = useAuth();
  const { openViewer } = useFileViewer();

  // core matter state
  const [matter, setMatter] = useState<Matter | null>(null);
  const [client, setClient] = useState<Client | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  // document version metadata
  const [docVersions, setDocVersions] = useState<Map<string, DocumentVersion>>(new Map());

  // timeline
  const [entries, setEntries] = useState<MatterLogEntry[]>([]);
  const [entriesLoading, setEntriesLoading] = useState(false);
  const [hasMore, setHasMore] = useState(false);
  const [loadingMore, setLoadingMore] = useState(false);

  // add entry form
  const [noteText, setNoteText] = useState("");
  const [attachedDocIds, setAttachedDocIds] = useState<Set<string>>(new Set());
  const [attachedDocMeta, setAttachedDocMeta] = useState<Map<string, { filename: string; contentType: string }>>(new Map());
  const [addError, setAddError] = useState<string | null>(null);
  const [addSubmitting, setAddSubmitting] = useState(false);
  const [saveToast, setSaveToast] = useState(false);

  // attach docs modal
  const [showAttachModal, setShowAttachModal] = useState(false);
  const [attachTab, setAttachTab] = useState<"existing" | "upload">("existing");
  const [modalSelected, setModalSelected] = useState<Set<string>>(new Set());
  const [uploadFile, setUploadFile] = useState<File | null>(null);
  const [uploadProgress, setUploadProgress] = useState(0);
  const [uploading, setUploading] = useState(false);
  const [uploadError, setUploadError] = useState<string | null>(null);

  // inline edit
  const [editing, setEditing] = useState(false);
  const [editTitle, setEditTitle] = useState("");
  const [editDescription, setEditDescription] = useState("");

  const textareaRef = useRef<HTMLTextAreaElement>(null);

  // ── Loaders ────────────────────────────────────────────────────────────────

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
    actor.getClient(m.clientId).then(c => setClient(c ?? null)).catch(() => {});
  }

  async function loadTimeline(replace = true) {
    if (!actor) return;
    if (replace) setEntriesLoading(true);
    const r = await actor.getMatterLogs(matterId, null, PAGE_LIMIT);
    if (replace) setEntriesLoading(false);
    if (r.__kind__ === "ok") {
      setEntries(r.ok.entries);
      setHasMore(r.ok.hasMore);
    }
  }

  async function loadMore() {
    if (!actor || entries.length === 0 || loadingMore) return;
    setLoadingMore(true);
    const cursor = entries[entries.length - 1].id;
    const r = await actor.getMatterLogs(matterId, cursor, PAGE_LIMIT);
    setLoadingMore(false);
    if (r.__kind__ === "ok") {
      setEntries(prev => [...prev, ...r.ok.entries]);
      setHasMore(r.ok.hasMore);
    }
  }

  useEffect(() => {
    void loadMatter();
    void loadDocs();
    void loadTimeline();
  }, [id]); // eslint-disable-line react-hooks/exhaustive-deps

  // Load document versions for sidebar + attachment chips
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

  // Build docMeta map for timeline entry chips
  const docMetaForTimeline = new Map<string, { filename: string; contentType: string }>();
  for (const [k, v] of docVersions) {
    docMetaForTimeline.set(k, { filename: v.filename, contentType: v.contentType });
  }
  // merge in attachedDocMeta (may have recently uploaded docs not yet in docVersions)
  for (const [k, v] of attachedDocMeta) {
    if (!docMetaForTimeline.has(k)) docMetaForTimeline.set(k, v);
  }

  // ── Transitions ────────────────────────────────────────────────────────────

  async function handleTransition(fn: (id: bigint) => Promise<{ __kind__: "ok"; ok: null } | { __kind__: "err"; err: string } | null>) {
    if (!matter) return;
    setSubmitting(true);
    setError(null);
    const result = await fn(matter.id);
    setSubmitting(false);
    if (!result) return;
    if (result.__kind__ === "err") setError(result.err);
    else { void loadMatter(); void loadTimeline(); }
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

  // ── Add entry ──────────────────────────────────────────────────────────────

  async function handleAddEntry() {
    if (!actor || !matter) return;
    const trimmed = noteText.trim();
    if (!trimmed) { setAddError("Note cannot be empty."); return; }
    if (noteText.length > MAX_NOTE) { setAddError(`Note exceeds ${MAX_NOTE} characters.`); return; }
    setAddSubmitting(true);
    setAddError(null);
    const docIds = [...attachedDocIds].map(s => BigInt(s));
    const r = await actor.addMatterLog(matterId, trimmed, docIds);
    setAddSubmitting(false);
    if (r.__kind__ === "ok") {
      setNoteText("");
      setAttachedDocIds(new Set());
      setAttachedDocMeta(new Map());
      setSaveToast(true);
      setTimeout(() => setSaveToast(false), 2500);
      void loadTimeline();
    } else {
      setAddError(r.err);
    }
  }

  // ── Attach docs modal ──────────────────────────────────────────────────────

  function openAttachModal() {
    // pre-populate modal selection with already-attached docs
    setModalSelected(new Set(attachedDocIds));
    setAttachTab("existing");
    setUploadFile(null);
    setUploadProgress(0);
    setUploadError(null);
    setShowAttachModal(true);
  }

  function confirmModalSelection() {
    // merge modal selection into attachedDocIds
    const next = new Set(attachedDocIds);
    const nextMeta = new Map(attachedDocMeta);
    for (const id of modalSelected) {
      next.add(id);
      const ver = docVersions.get(id);
      if (ver) nextMeta.set(id, { filename: ver.filename, contentType: ver.contentType });
    }
    // remove unselected
    for (const id of attachedDocIds) {
      if (!modalSelected.has(id)) { next.delete(id); nextMeta.delete(id); }
    }
    setAttachedDocIds(next);
    setAttachedDocMeta(nextMeta);
    setShowAttachModal(false);
  }

  async function handleUploadInModal() {
    if (!uploadFile) return;
    setUploading(true);
    setUploadError(null);
    setUploadProgress(0);
    const r = await upload(uploadFile, pct => setUploadProgress(pct));
    setUploading(false);
    if (r.__kind__ === "err") { setUploadError(r.err); return; }
    const { documentId: newDocId, versionId: newVersionId } = r.ok;
    void loadDocs();
    const next = new Set(attachedDocIds);
    next.add(String(newDocId));
    setAttachedDocIds(next);
    try {
      const ver = await getVersion(newVersionId);
      if (ver) {
        setAttachedDocMeta(prev => new Map(prev).set(String(newDocId), { filename: ver.filename, contentType: ver.contentType }));
        setDocVersions(prev => new Map(prev).set(String(newDocId), ver));
      }
    } catch {}
    setShowAttachModal(false);
    setUploadFile(null);
  }

  // ── Document viewer ────────────────────────────────────────────────────────

  function openDocViewer(doc: Document) {
    const ver = docVersions.get(String(doc.id));
    if (!ver) return;
    openViewer({ kind: "document", id: doc.id, versionId: ver.versionId, filename: ver.filename, contentType: ver.contentType, sizeBytes: ver.sizeBytes });
  }

  // ── Render ─────────────────────────────────────────────────────────────────

  if (loading) return <LoadingSpinner />;
  if (!matter) return <ErrorMessage message={error ?? "Matter not found."} />;

  const sc = STATUS_COLOR[matter.status] ?? "#78909c";
  const days = daysOpen(matter.createdAt);
  const canAddEntry = role === Role.Partner || role === Role.Associate;
  const noteOver = noteText.length > MAX_NOTE;
  const attachCount = attachedDocIds.size;

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
        background: "var(--surf)", border: `1px solid var(--bd)`,
        borderLeftWidth: 3, borderLeftColor: sc, borderLeftStyle: "solid",
        borderRadius: 8, padding: "14px 16px", marginBottom: 20,
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
            <span>·</span>
            <span>{entries.length}{hasMore ? "+" : ""} log entr{entries.length !== 1 || hasMore ? "ies" : "y"}</span>
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

        {/* Left — Case log timeline */}
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontWeight: 600, fontSize: 15, marginBottom: 16 }}>Case log</div>

          {entriesLoading && <LoadingSpinner />}

          {/* Timeline entries */}
          {!entriesLoading && (
            <div>
              {entries.map(entry => (
                entry.kind.__kind__ === "SessionNote"
                  ? <SessionNoteEntry key={String(entry.id)} entry={entry} docMeta={docMetaForTimeline} />
                  : <SystemEventEntry key={String(entry.id)} entry={entry} />
              ))}

              {/* Pagination */}
              {hasMore && (
                <button className="btn btn-neutral btn-sm" style={{ marginBottom: 16 }} onClick={() => { void loadMore(); }} disabled={loadingMore}>
                  {loadingMore ? "Loading…" : "Load older entries"}
                </button>
              )}
              {!hasMore && entries.length > 0 && (
                <div style={{ fontSize: 11, color: "var(--tx2)", textAlign: "center", padding: "8px 0 16px", borderTop: "1px solid var(--bd)" }}>
                  End of case log
                </div>
              )}
              {entries.length === 0 && (
                <div style={{ fontSize: 13, color: "var(--tx2)", textAlign: "center", padding: "32px 0" }}>
                  No log entries yet.
                </div>
              )}
            </div>
          )}

          {/* Add entry box */}
          {canAddEntry ? (
            <div style={{
              background: "var(--surf)", border: "1px solid var(--bd)",
              borderRadius: 10, padding: "16px", marginTop: 8,
            }}>
              <div style={{ fontWeight: 600, fontSize: 13, marginBottom: 10 }}>Add log entry</div>
              <textarea
                ref={textareaRef}
                className="tp-input"
                style={{ width: "100%", minHeight: 80, resize: "vertical", fontSize: 13, fontFamily: "inherit", boxSizing: "border-box" }}
                placeholder="What happened in this session?"
                value={noteText}
                onChange={e => setNoteText(e.target.value)}
                rows={4}
              />
              <div style={{ fontSize: 11, color: noteOver ? "#dc2626" : "var(--tx2)", textAlign: "right", marginTop: 3 }}>
                {noteText.length} / {MAX_NOTE}
              </div>

              {/* Attached doc chips */}
              {attachCount > 0 && (
                <div style={{ display: "flex", flexWrap: "wrap", gap: 6, marginTop: 8 }}>
                  {[...attachedDocIds].map(docId => {
                    const meta = docMetaForTimeline.get(docId) ?? attachedDocMeta.get(docId);
                    return (
                      <span key={docId} style={{
                        display: "inline-flex", alignItems: "center", gap: 4,
                        background: "var(--surf2)", borderRadius: 6, padding: "3px 8px",
                        fontSize: 11, color: "var(--tx2)",
                      }}>
                        <i className={`ti ${docTypeIcon(meta?.contentType ?? "")}`} style={{ fontSize: 12 }} />
                        {meta?.filename ?? `Doc #${docId}`}
                        <button onClick={() => {
                          const next = new Set(attachedDocIds);
                          next.delete(docId);
                          setAttachedDocIds(next);
                          const nm = new Map(attachedDocMeta);
                          nm.delete(docId);
                          setAttachedDocMeta(nm);
                        }} style={{ background: "none", border: "none", cursor: "pointer", padding: 0, fontSize: 11, color: "var(--tx2)", lineHeight: 1 }}>
                          ×
                        </button>
                      </span>
                    );
                  })}
                </div>
              )}

              {addError && (
                <div style={{ color: "#dc2626", fontSize: 12, marginTop: 8 }}>{addError}</div>
              )}

              <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginTop: 10 }}>
                <button
                  className="btn btn-neutral btn-sm"
                  disabled={attachCount >= MAX_ATTACHMENTS}
                  onClick={openAttachModal}
                >
                  <i className="ti ti-paperclip" /> Attach documents
                  {attachCount > 0 && <span style={{ marginLeft: 4, fontWeight: 600 }}>({attachCount})</span>}
                </button>
                <button
                  className="btn btn-primary btn-sm"
                  disabled={addSubmitting || !noteText.trim() || noteOver}
                  onClick={() => { void handleAddEntry(); }}
                >
                  {addSubmitting ? "Saving…" : "Save entry →"}
                </button>
              </div>
            </div>
          ) : (
            <div style={{ fontSize: 12, color: "var(--tx2)", fontStyle: "italic", marginTop: 12, textAlign: "center" }}>
              You can view but not add log entries.
            </div>
          )}
        </div>

        {/* Right sidebar */}
        <div style={{ width: 240, flexShrink: 0, display: "flex", flexDirection: "column", gap: 0 }}>

          {/* Matter details */}
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

          {/* Documents */}
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
                  <button key={String(doc.id)} onClick={() => openDocViewer(doc)} disabled={!ver}
                    style={{
                      display: "flex", alignItems: "center", gap: 6, padding: "5px 8px",
                      borderRadius: 6, cursor: ver ? "pointer" : "default",
                      background: "var(--surf2)", border: "none", textAlign: "left", width: "100%",
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

          {/* Activity */}
          <div className="card" style={{ padding: "14px 16px" }}>
            <div style={{ fontWeight: 600, fontSize: 13, marginBottom: 10 }}>Activity</div>
            <div style={{ display: "flex", flexDirection: "column", gap: 6, fontSize: 12 }}>
              <div style={{ display: "flex", justifyContent: "space-between" }}>
                <span style={{ color: "var(--tx2)" }}>Documents</span>
                <span>{docsLoading ? "—" : documents.length}</span>
              </div>
              <div style={{ display: "flex", justifyContent: "space-between" }}>
                <span style={{ color: "var(--tx2)" }}>Log entries</span>
                <span>{entries.length}{hasMore ? "+" : ""}</span>
              </div>
              <div style={{ display: "flex", justifyContent: "space-between" }}>
                <span style={{ color: "var(--tx2)" }}>Last updated</span>
                <span style={{ fontSize: 11 }}>{fmtDate(matter.lastModifiedAt)}</span>
              </div>
            </div>
          </div>

        </div>
      </div>

      {/* ── Attach docs modal ───────────────────────────────────────────────── */}
      {showAttachModal && (
        <div style={{
          position: "fixed", inset: 0, background: "rgba(0,0,0,0.5)",
          display: "flex", alignItems: "center", justifyContent: "center", zIndex: 1000,
        }} onClick={e => { if (e.target === e.currentTarget) setShowAttachModal(false); }}>
          <div style={{
            background: "var(--bg)", border: "1px solid var(--bd)", borderRadius: 12,
            padding: 20, width: 480, maxHeight: "80vh", overflow: "auto",
          }}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 14 }}>
              <div style={{ fontWeight: 600, fontSize: 15 }}>Attach documents</div>
              <button onClick={() => setShowAttachModal(false)} style={{ background: "none", border: "none", cursor: "pointer", fontSize: 18, color: "var(--tx2)" }}>×</button>
            </div>

            {/* Tabs */}
            <div style={{ display: "flex", gap: 2, marginBottom: 14, borderBottom: "1px solid var(--bd)" }}>
              {(["existing", "upload"] as const).map(tab => (
                <button key={tab} onClick={() => setAttachTab(tab)} style={{
                  padding: "6px 14px", background: "none", border: "none", cursor: "pointer",
                  fontWeight: attachTab === tab ? 600 : 400,
                  borderBottom: attachTab === tab ? "2px solid var(--ac)" : "2px solid transparent",
                  color: attachTab === tab ? "var(--ac)" : "var(--tx2)", fontSize: 13,
                }}>
                  {tab === "existing" ? "Existing documents" : "Upload new"}
                </button>
              ))}
            </div>

            {/* Existing tab */}
            {attachTab === "existing" && (
              <div>
                {documents.length === 0 && (
                  <div style={{ color: "var(--tx2)", fontSize: 13, textAlign: "center", padding: 20 }}>
                    No documents in this matter yet.
                  </div>
                )}
                {documents.map(doc => {
                  const ver = docVersions.get(String(doc.id));
                  const docId = String(doc.id);
                  return (
                    <label key={docId} style={{
                      display: "flex", alignItems: "center", gap: 8, padding: "8px 4px",
                      cursor: "pointer", borderBottom: "1px solid var(--bd)",
                    }}>
                      <input
                        type="checkbox"
                        checked={modalSelected.has(docId)}
                        onChange={e => {
                          const next = new Set(modalSelected);
                          if (e.target.checked) next.add(docId); else next.delete(docId);
                          setModalSelected(next);
                        }}
                      />
                      <i className={`ti ${docTypeIcon(ver?.contentType ?? "")}`} style={{ fontSize: 14, color: "var(--tx2)" }} />
                      <span style={{ fontSize: 13 }}>{ver?.filename ?? "…"}</span>
                    </label>
                  );
                })}
                {documents.length > 0 && (
                  <div style={{ marginTop: 14, display: "flex", justifyContent: "flex-end" }}>
                    <button className="btn btn-primary btn-sm" onClick={confirmModalSelection}>
                      Add selected ({modalSelected.size})
                    </button>
                  </div>
                )}
              </div>
            )}

            {/* Upload tab */}
            {attachTab === "upload" && (
              <div>
                <input type="file" onChange={e => { setUploadFile(e.target.files?.[0] ?? null); setUploadError(null); }} style={{ marginBottom: 12 }} />
                {uploadError && <div style={{ color: "#dc2626", fontSize: 12, marginBottom: 8 }}>{uploadError}</div>}
                {uploading && (
                  <div style={{ marginBottom: 8 }}>
                    <div style={{ height: 6, background: "var(--bd)", borderRadius: 3, overflow: "hidden" }}>
                      <div style={{ height: "100%", width: `${uploadProgress}%`, background: "var(--ac)", transition: "width 0.2s" }} />
                    </div>
                    <div style={{ fontSize: 11, color: "var(--tx2)", marginTop: 4 }}>{uploadProgress}%</div>
                  </div>
                )}
                <button className="btn btn-primary btn-sm" disabled={!uploadFile || uploading} onClick={() => { void handleUploadInModal(); }}>
                  {uploading ? "Uploading…" : "Upload & attach"}
                </button>
              </div>
            )}
          </div>
        </div>
      )}

      {saveToast && (
        <div style={{
          position: "fixed", bottom: 24, right: 24,
          background: "#16a34a", color: "#fff",
          padding: "10px 18px", borderRadius: 6,
          fontSize: 13, fontWeight: 500, zIndex: 1001,
          boxShadow: "0 2px 8px rgba(0,0,0,0.2)",
        }}>
          Log entry added.
        </div>
      )}
    </div>
  );
}
