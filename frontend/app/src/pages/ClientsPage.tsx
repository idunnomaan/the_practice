import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { useClients } from "../hooks/useClients";
import { ClientType } from "../backend/api/backend";
import LoadingSpinner from "../components/LoadingSpinner";
import ErrorMessage from "../components/ErrorMessage";

export default function ClientsPage() {
  const { clients, loading, error, load, createClient } = useClients();

  const [showForm, setShowForm] = useState(false);
  const [name, setName] = useState("");
  const [clientType, setClientType] = useState<ClientType>(ClientType.Individual);
  const [email, setEmail] = useState("");
  const [phone, setPhone] = useState("");
  const [identifier, setIdentifier] = useState("");
  const [notes, setNotes] = useState("");
  const [formError, setFormError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => { void load(); }, [load]);

  async function handleCreate(e: React.FormEvent) {
    e.preventDefault();
    if (!name.trim()) { setFormError("Name is required."); return; }
    setSubmitting(true);
    setFormError(null);
    const result = await createClient(
      name.trim(), clientType,
      email.trim() || null, phone.trim() || null,
      identifier.trim() || null, notes.trim(),
    );
    setSubmitting(false);
    if (!result) return;
    if (result.__kind__ === "ok") {
      setShowForm(false);
      setName(""); setEmail(""); setPhone(""); setIdentifier(""); setNotes("");
      void load();
    } else {
      setFormError(result.err);
    }
  }

  return (
    <div>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "1rem" }}>
        <h1 style={{ margin: 0 }}>Clients</h1>
        <button onClick={() => setShowForm(!showForm)} style={btnStyle}>
          {showForm ? "Cancel" : "Create Client"}
        </button>
      </div>

      {showForm && (
        <form onSubmit={(e) => { void handleCreate(e); }} style={formStyle}>
          {formError && <ErrorMessage message={formError} onDismiss={() => setFormError(null)} />}
          <label>Name *<br />
            <input value={name} onChange={e => setName(e.target.value)} style={inputStyle} required />
          </label>
          <label>Type<br />
            <select value={clientType} onChange={e => setClientType(e.target.value as ClientType)} style={inputStyle}>
              <option value={ClientType.Individual}>Individual</option>
              <option value={ClientType.Company}>Company</option>
              <option value={ClientType.Other}>Other</option>
            </select>
          </label>
          <label>Email<br /><input value={email} onChange={e => setEmail(e.target.value)} style={inputStyle} type="email" /></label>
          <label>Phone<br /><input value={phone} onChange={e => setPhone(e.target.value)} style={inputStyle} /></label>
          <label>Identifier (NIC / Reg No)<br /><input value={identifier} onChange={e => setIdentifier(e.target.value)} style={inputStyle} /></label>
          <label>Notes<br /><textarea value={notes} onChange={e => setNotes(e.target.value)} style={{ ...inputStyle, height: 80 }} /></label>
          <button type="submit" disabled={submitting} style={btnStyle}>
            {submitting ? "Creating…" : "Create"}
          </button>
        </form>
      )}

      {error && <ErrorMessage message={error} />}
      {loading && <LoadingSpinner />}

      <table style={{ width: "100%", borderCollapse: "collapse", marginTop: "1rem" }}>
        <thead>
          <tr style={{ background: "#f0f0f0" }}>
            <th style={thStyle}>ID</th>
            <th style={thStyle}>Name</th>
            <th style={thStyle}>Type</th>
            <th style={thStyle}>Status</th>
            <th style={thStyle}>Email</th>
            <th style={thStyle}></th>
          </tr>
        </thead>
        <tbody>
          {clients.map(c => (
            <tr key={String(c.id)} style={{ borderBottom: "1px solid #eee" }}>
              <td style={tdStyle}>{String(c.id)}</td>
              <td style={tdStyle}>{c.name}</td>
              <td style={tdStyle}>{c.clientType}</td>
              <td style={tdStyle}>{c.status}</td>
              <td style={tdStyle}>{c.primaryEmail ?? "—"}</td>
              <td style={tdStyle}>
                <Link to={`/clients/${c.id}`}>View</Link>
              </td>
            </tr>
          ))}
          {!loading && clients.length === 0 && (
            <tr><td colSpan={6} style={{ padding: "1rem", color: "#888", textAlign: "center" }}>No clients.</td></tr>
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
