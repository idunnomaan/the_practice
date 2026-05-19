import { useEffect, useState } from "react";
import { useParams, Link } from "react-router-dom";
import { useMatters } from "../hooks/useMatters";
import { MatterStatus } from "../backend/api/backend";
import type { Matter } from "../backend/api/backend";
import LoadingSpinner from "../components/LoadingSpinner";
import ErrorMessage from "../components/ErrorMessage";

export default function MatterDetailPage() {
  const { id } = useParams<{ id: string }>();
  const { getMatter, updateMatter, closeMatter, putOnHold, resumeMatter, reopenMatter, archiveMatter } = useMatters();

  const [matter, setMatter] = useState<Matter | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [editing, setEditing] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");

  async function load() {
    if (!id) return;
    setLoading(true);
    setError(null);
    const m = await getMatter(BigInt(id));
    setLoading(false);
    if (!m) { setError("Matter not found."); return; }
    setMatter(m);
    setTitle(m.title);
    setDescription(m.description);
  }

  useEffect(() => { void load(); }, [id]); // eslint-disable-line react-hooks/exhaustive-deps

  async function handleUpdate(e: React.FormEvent) {
    e.preventDefault();
    if (!matter) return;
    setSubmitting(true);
    setError(null);
    const result = await updateMatter(matter.id, title.trim() || null, description.trim() || null);
    setSubmitting(false);
    if (!result) return;
    if (result.__kind__ === "ok") { setEditing(false); void load(); }
    else setError(result.err);
  }

  async function handleTransition(fn: (id: bigint) => Promise<{ __kind__: "ok"; ok: null } | { __kind__: "err"; err: string } | null>) {
    if (!matter) return;
    setSubmitting(true);
    setError(null);
    const result = await fn(matter.id);
    setSubmitting(false);
    if (!result) return;
    if (result.__kind__ === "err") setError(result.err);
    else void load();
  }

  if (loading) return <LoadingSpinner />;
  if (!matter) return <ErrorMessage message={error ?? "Matter not found."} />;

  return (
    <div style={{ maxWidth: 680 }}>
      <h1 style={{ marginTop: 0 }}>{matter.title}</h1>
      <p>
        <strong>Status:</strong> {matter.status} &nbsp;|&nbsp;
        <strong>Type:</strong> {matter.matterType || "—"} &nbsp;|&nbsp;
        <strong>Client:</strong> <Link to={`/clients/${matter.clientId}`}>{String(matter.clientId)}</Link>
      </p>
      <p><Link to={`/matters/${matter.id}/documents`}>View Documents →</Link></p>

      {error && <ErrorMessage message={error} onDismiss={() => setError(null)} />}

      {/* Status transition buttons */}
      <div style={{ display: "flex", gap: "0.5rem", marginBottom: "1rem", flexWrap: "wrap" }}>
        {matter.status === MatterStatus.Open && (
          <>
            <button onClick={() => { void handleTransition(putOnHold); }} disabled={submitting} style={{ ...btnStyle, background: "#886600" }}>Put On Hold</button>
            <button onClick={() => { void handleTransition(closeMatter); }} disabled={submitting} style={{ ...btnStyle, background: "#c00" }}>Close</button>
          </>
        )}
        {matter.status === MatterStatus.OnHold && (
          <>
            <button onClick={() => { void handleTransition(resumeMatter); }} disabled={submitting} style={{ ...btnStyle, background: "#060" }}>Resume</button>
            <button onClick={() => { void handleTransition(closeMatter); }} disabled={submitting} style={{ ...btnStyle, background: "#c00" }}>Close</button>
          </>
        )}
        {matter.status === MatterStatus.Closed && (
          <>
            <button onClick={() => { void handleTransition(reopenMatter); }} disabled={submitting} style={{ ...btnStyle, background: "#060" }}>Reopen</button>
            <button onClick={() => { void handleTransition(archiveMatter); }} disabled={submitting} style={{ ...btnStyle, background: "#555" }}>Archive</button>
          </>
        )}
        {matter.status === MatterStatus.Archived && (
          <span style={{ color: "#888" }}>Archived — terminal state</span>
        )}
      </div>

      {!editing ? (
        <div style={{ display: "flex", flexDirection: "column", gap: "0.5rem" }}>
          <div><strong>Description:</strong> {matter.description || "—"}</div>
          {matter.assignedPartner && <div><strong>Partner:</strong> <code>{matter.assignedPartner.toText()}</code></div>}
          <button onClick={() => setEditing(true)} style={{ ...btnStyle, alignSelf: "flex-start", marginTop: "0.5rem" }}>Edit</button>
        </div>
      ) : (
        <form onSubmit={(e) => { void handleUpdate(e); }} style={{ display: "flex", flexDirection: "column", gap: "0.75rem" }}>
          <label>Title *<br /><input value={title} onChange={e => setTitle(e.target.value)} style={inputStyle} required /></label>
          <label>Description<br /><textarea value={description} onChange={e => setDescription(e.target.value)} style={{ ...inputStyle, height: 100 }} /></label>
          <div style={{ display: "flex", gap: "0.5rem" }}>
            <button type="submit" disabled={submitting} style={btnStyle}>{submitting ? "Saving…" : "Save"}</button>
            <button type="button" onClick={() => setEditing(false)} style={{ ...btnStyle, background: "#888" }}>Cancel</button>
          </div>
        </form>
      )}
    </div>
  );
}

const btnStyle: React.CSSProperties = { padding: "0.5rem 1rem", background: "#1a1a2e", color: "#fff", border: "none", borderRadius: 4, cursor: "pointer" };
const inputStyle: React.CSSProperties = { width: "100%", padding: "0.4rem", boxSizing: "border-box", marginTop: 4 };
