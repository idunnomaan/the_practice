import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { useMatters } from "../hooks/useMatters";
import { MatterStatus } from "../backend/api/backend";
import LoadingSpinner from "../components/LoadingSpinner";
import ErrorMessage from "../components/ErrorMessage";

function fmtClientId(id: bigint): string {
  return "CLT-" + String(id).padStart(4, "0");
}

function statusBadge(status: string) {
  const cls =
    status === "Open"     ? "badge badge-open"   :
    status === "OnHold"   ? "badge badge-hold"   :
    status === "Closed"   ? "badge badge-closed" :
                            "badge badge-archived";
  const label =
    status === "OnHold" ? "On hold" : status;
  return <span className={cls}>{label}</span>;
}

export default function MattersPage() {
  const { matters, loading, error, load, createMatter } = useMatters();

  const [statusFilter, setStatusFilter] = useState<MatterStatus | null>(null);
  const [showForm, setShowForm] = useState(false);
  const [title, setTitle] = useState("");
  const [matterType, setMatterType] = useState("");
  const [clientId, setClientId] = useState("");
  const [partner, setPartner] = useState("");
  const [description, setDescription] = useState("");
  const [formError, setFormError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => { void load(0n, 50n, statusFilter); }, [load, statusFilter]);

  async function handleCreate(e: React.FormEvent) {
    e.preventDefault();
    if (!title.trim()) { setFormError("Title is required."); return; }
    if (!clientId.trim()) { setFormError("Client ID is required."); return; }
    setSubmitting(true);
    setFormError(null);
    try {
      const result = await createMatter(
        title.trim(), matterType.trim(), BigInt(clientId),
        partner.trim() || null, description.trim(),
      );
      if (!result) return;
      if (result.__kind__ === "ok") {
        setShowForm(false);
        setTitle(""); setMatterType(""); setClientId(""); setPartner(""); setDescription("");
        void load(0n, 50n, statusFilter);
      } else {
        setFormError(result.err);
      }
    } catch (e) {
      setFormError(String(e));
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div>
      <div className="page-header">
        <div className="page-title">Matters</div>
        <button className="add-btn" onClick={() => setShowForm(!showForm)}>
          <i className="ti ti-plus" />
          {showForm ? "Cancel" : "New matter"}
        </button>
      </div>

      <div className="filter-bar">
        <span>Status:</span>
        <select
          className="tp-input"
          style={{ width: "auto", padding: "5px 10px" }}
          value={statusFilter ?? ""}
          onChange={e => setStatusFilter(e.target.value ? e.target.value as MatterStatus : null)}
        >
          <option value="">All</option>
          <option value={MatterStatus.Open}>Open</option>
          <option value={MatterStatus.OnHold}>On Hold</option>
          <option value={MatterStatus.Closed}>Closed</option>
          <option value={MatterStatus.Archived}>Archived</option>
        </select>
      </div>

      {showForm && (
        <form className="tp-form" onSubmit={(e) => { void handleCreate(e); }}>
          {formError && <ErrorMessage message={formError} onDismiss={() => setFormError(null)} />}
          <label className="tp-label">Title *
            <input className="tp-input" value={title} onChange={e => setTitle(e.target.value)} required />
          </label>
          <label className="tp-label">Matter Type
            <input className="tp-input" value={matterType} onChange={e => setMatterType(e.target.value)} placeholder="e.g. Commercial Litigation" />
          </label>
          <label className="tp-label">Client ID *
            <input className="tp-input" value={clientId} onChange={e => setClientId(e.target.value)} type="number" required />
          </label>
          <label className="tp-label">Assigned Partner (Principal)
            <input className="tp-input" value={partner} onChange={e => setPartner(e.target.value)} placeholder="optional" />
          </label>
          <label className="tp-label">Description
            <textarea className="tp-input tp-textarea" value={description} onChange={e => setDescription(e.target.value)} />
          </label>
          <div>
            <button type="submit" className="btn btn-primary" disabled={submitting}>
              {submitting ? "Creating…" : "Create"}
            </button>
          </div>
        </form>
      )}

      {error && <ErrorMessage message={error} />}
      {loading && <LoadingSpinner />}

      <div className="card">
        <table className="tp-table">
          <thead>
            <tr>
              <th>ID</th>
              <th>Title</th>
              <th>Type</th>
              <th>Client</th>
              <th>Status</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {matters.map(m => (
              <tr key={String(m.id)}>
                <td><span className="mono">{String(m.id).padStart(3, "0")}</span></td>
                <td>{m.title}</td>
                <td>{m.matterType || "—"}</td>
                <td><span className="clt-id">{fmtClientId(m.clientId)}</span></td>
                <td>{statusBadge(m.status)}</td>
                <td>
                  <Link to={`/matters/${m.id}`} className="view-link">View</Link>
                  {" · "}
                  <Link to={`/matters/${m.id}/documents`} className="view-link">Docs</Link>
                </td>
              </tr>
            ))}
            {!loading && matters.length === 0 && (
              <tr><td colSpan={6} className="empty-state">No matters.</td></tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
