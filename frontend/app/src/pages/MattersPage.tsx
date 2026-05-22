import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { useMatters } from "../hooks/useMatters";
import { MatterStatus } from "../backend/api/backend";
import LoadingSpinner from "../components/LoadingSpinner";
import ErrorMessage from "../components/ErrorMessage";

function fmtClientId(id: bigint): string {
  return "CLT-" + String(id).padStart(4, "0");
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
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "1rem" }}>
        <h1 style={{ margin: 0 }}>Matters</h1>
        <button onClick={() => setShowForm(!showForm)} style={btnStyle}>
          {showForm ? "Cancel" : "Create Matter"}
        </button>
      </div>

      <div style={{ marginBottom: "1rem" }}>
        <label>Filter by status: </label>
        <select value={statusFilter ?? ""} onChange={e => setStatusFilter(e.target.value ? e.target.value as MatterStatus : null)} style={{ padding: "0.3rem" }}>
          <option value="">All</option>
          <option value={MatterStatus.Open}>Open</option>
          <option value={MatterStatus.OnHold}>On Hold</option>
          <option value={MatterStatus.Closed}>Closed</option>
          <option value={MatterStatus.Archived}>Archived</option>
        </select>
      </div>

      {showForm && (
        <form onSubmit={(e) => { void handleCreate(e); }} style={formStyle}>
          {formError && <ErrorMessage message={formError} onDismiss={() => setFormError(null)} />}
          <label>Title *<br /><input value={title} onChange={e => setTitle(e.target.value)} style={inputStyle} required /></label>
          <label>Matter Type<br /><input value={matterType} onChange={e => setMatterType(e.target.value)} style={inputStyle} placeholder="e.g. Commercial Litigation" /></label>
          <label>Client ID *<br /><input value={clientId} onChange={e => setClientId(e.target.value)} style={inputStyle} type="number" required /></label>
          <label>Assigned Partner (Principal)<br /><input value={partner} onChange={e => setPartner(e.target.value)} style={inputStyle} placeholder="optional" /></label>
          <label>Description<br /><textarea value={description} onChange={e => setDescription(e.target.value)} style={{ ...inputStyle, height: 80 }} /></label>
          <button type="submit" disabled={submitting} style={btnStyle}>
            {submitting ? "Creating…" : "Create"}
          </button>
        </form>
      )}

      {error && <ErrorMessage message={error} />}
      {loading && <LoadingSpinner />}

      <table style={{ width: "100%", borderCollapse: "collapse" }}>
        <thead>
          <tr style={{ background: "#f0f0f0" }}>
            <th style={thStyle}>ID</th>
            <th style={thStyle}>Title</th>
            <th style={thStyle}>Type</th>
            <th style={thStyle}>Status</th>
            <th style={thStyle}>Client ID</th>
            <th style={thStyle}></th>
          </tr>
        </thead>
        <tbody>
          {matters.map(m => (
            <tr key={String(m.id)} style={{ borderBottom: "1px solid #eee" }}>
              <td style={tdStyle}>{String(m.id)}</td>
              <td style={tdStyle}>{m.title}</td>
              <td style={tdStyle}>{m.matterType || "—"}</td>
              <td style={tdStyle}>{m.status}</td>
              <td style={tdStyle}>{fmtClientId(m.clientId)}</td>
              <td style={tdStyle}>
                <Link to={`/matters/${m.id}`}>View</Link>
                {" · "}
                <Link to={`/matters/${m.id}/documents`}>Docs</Link>
              </td>
            </tr>
          ))}
          {!loading && matters.length === 0 && (
            <tr><td colSpan={6} style={{ padding: "1rem", color: "#888", textAlign: "center" }}>No matters.</td></tr>
          )}
        </tbody>
      </table>
    </div>
  );
}

const btnStyle: React.CSSProperties = { padding: "0.5rem 1rem", background: "#1a1a2e", color: "#fff", border: "none", borderRadius: 4, cursor: "pointer" };
const formStyle: React.CSSProperties = { background: "#f9f9f9", padding: "1rem", borderRadius: 8, marginBottom: "1rem", display: "flex", flexDirection: "column", gap: "0.75rem" };
const inputStyle: React.CSSProperties = { width: "100%", padding: "0.4rem", boxSizing: "border-box", marginTop: 4 };
const thStyle: React.CSSProperties = { padding: "0.5rem", textAlign: "left", fontWeight: 600 };
const tdStyle: React.CSSProperties = { padding: "0.5rem" };
