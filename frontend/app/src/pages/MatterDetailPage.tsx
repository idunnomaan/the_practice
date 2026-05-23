import { useEffect, useState } from "react";
import { useParams, Link } from "react-router-dom";
import { useMatters } from "../hooks/useMatters";
import { MatterStatus } from "../backend/api/backend";
import type { Matter } from "../backend/api/backend";
import LoadingSpinner from "../components/LoadingSpinner";
import ErrorMessage from "../components/ErrorMessage";

function statusBadge(status: string) {
  const cls =
    status === "Open"     ? "badge badge-open"     :
    status === "OnHold"   ? "badge badge-hold"     :
    status === "Closed"   ? "badge badge-closed"   :
                            "badge badge-archived";
  const label = status === "OnHold" ? "On Hold" : status;
  return <span className={cls}>{label}</span>;
}

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
    <div className="detail-page">
      <div className="page-header">
        <div>
          <div className="page-title">{matter.title}</div>
          <div className="detail-meta">
            <span className="mono">{String(matter.id).padStart(3, "0")}</span>
            &nbsp;·&nbsp;{statusBadge(matter.status)}
            {matter.matterType && <>&nbsp;·&nbsp;{matter.matterType}</>}
            &nbsp;·&nbsp;<Link to={`/clients/${matter.clientId}`} className="clt-id">
              CLT-{String(matter.clientId).padStart(4, "0")}
            </Link>
          </div>
        </div>
        <Link to={`/matters/${matter.id}/documents`} className="btn btn-neutral btn-sm">
          <i className="ti ti-files" /> Documents
        </Link>
      </div>

      {error && <ErrorMessage message={error} onDismiss={() => setError(null)} />}

      <div className="transition-btns">
        {matter.status === MatterStatus.Open && (
          <>
            <button className="btn btn-warning btn-sm" onClick={() => { void handleTransition(putOnHold); }} disabled={submitting}>Put On Hold</button>
            <button className="btn btn-danger btn-sm" onClick={() => { void handleTransition(closeMatter); }} disabled={submitting}>Close</button>
          </>
        )}
        {matter.status === MatterStatus.OnHold && (
          <>
            <button className="btn btn-success btn-sm" onClick={() => { void handleTransition(resumeMatter); }} disabled={submitting}>Resume</button>
            <button className="btn btn-danger btn-sm" onClick={() => { void handleTransition(closeMatter); }} disabled={submitting}>Close</button>
          </>
        )}
        {matter.status === MatterStatus.Closed && (
          <>
            <button className="btn btn-success btn-sm" onClick={() => { void handleTransition(reopenMatter); }} disabled={submitting}>Reopen</button>
            <button className="btn btn-neutral btn-sm" onClick={() => { void handleTransition(archiveMatter); }} disabled={submitting}>Archive</button>
          </>
        )}
        {matter.status === MatterStatus.Archived && (
          <span style={{ fontSize: 12, color: "var(--tx2)" }}>Archived — terminal state</span>
        )}
      </div>

      {!editing ? (
        <>
          <div className="card" style={{ padding: "16px 20px", marginBottom: 18 }}>
            <div className="detail-field"><strong>Description</strong>{matter.description || "—"}</div>
            {matter.assignedPartner && (
              <div className="detail-field">
                <strong>Partner</strong>
                <span className="mono">{matter.assignedPartner.toText()}</span>
              </div>
            )}
          </div>
          <button className="btn btn-primary btn-sm" onClick={() => setEditing(true)}>
            <i className="ti ti-pencil" /> Edit
          </button>
        </>
      ) : (
        <form className="tp-form" onSubmit={(e) => { void handleUpdate(e); }}>
          <label className="tp-label">Title *
            <input className="tp-input" value={title} onChange={e => setTitle(e.target.value)} required />
          </label>
          <label className="tp-label">Description
            <textarea className="tp-input tp-textarea" value={description} onChange={e => setDescription(e.target.value)} />
          </label>
          <div className="transition-btns">
            <button type="submit" className="btn btn-primary btn-sm" disabled={submitting}>
              {submitting ? "Saving…" : "Save"}
            </button>
            <button type="button" className="btn btn-neutral btn-sm" onClick={() => setEditing(false)}>
              Cancel
            </button>
          </div>
        </form>
      )}
    </div>
  );
}
