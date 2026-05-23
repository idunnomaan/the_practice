import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { useClients } from "../hooks/useClients";
import { ClientType } from "../backend/api/backend";
import LoadingSpinner from "../components/LoadingSpinner";
import ErrorMessage from "../components/ErrorMessage";

function fmtClientId(id: bigint): string {
  return "CLT-" + String(id).padStart(4, "0");
}

function statusBadge(status: string) {
  const cls = status === "Active" ? "badge badge-active" : "badge badge-inactive";
  return <span className={cls}>{status}</span>;
}

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
      <div className="page-header">
        <div className="page-title">Clients</div>
        <button className="add-btn" onClick={() => setShowForm(!showForm)}>
          <i className="ti ti-plus" />
          {showForm ? "Cancel" : "New client"}
        </button>
      </div>

      {showForm && (
        <form className="tp-form" onSubmit={(e) => { void handleCreate(e); }}>
          {formError && <ErrorMessage message={formError} onDismiss={() => setFormError(null)} />}
          <label className="tp-label">Name *
            <input className="tp-input" value={name} onChange={e => setName(e.target.value)} required />
          </label>
          <label className="tp-label">Type
            <select className="tp-input" value={clientType} onChange={e => setClientType(e.target.value as ClientType)}>
              <option value={ClientType.Individual}>Individual</option>
              <option value={ClientType.Company}>Company</option>
              <option value={ClientType.Other}>Other</option>
            </select>
          </label>
          <label className="tp-label">Email
            <input className="tp-input" value={email} onChange={e => setEmail(e.target.value)} type="email" />
          </label>
          <label className="tp-label">Phone
            <input className="tp-input" value={phone} onChange={e => setPhone(e.target.value)} />
          </label>
          <label className="tp-label">Identifier (NIC / Reg No)
            <input className="tp-input" value={identifier} onChange={e => setIdentifier(e.target.value)} />
          </label>
          <label className="tp-label">Notes
            <textarea className="tp-input tp-textarea" value={notes} onChange={e => setNotes(e.target.value)} />
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
              <th>Client ID</th>
              <th>Name</th>
              <th>Type</th>
              <th>Email</th>
              <th>Status</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {clients.map(c => (
              <tr key={String(c.id)}>
                <td><span className="clt-id">{fmtClientId(c.id)}</span></td>
                <td>{c.name}</td>
                <td>{c.clientType}</td>
                <td>{c.primaryEmail ?? "—"}</td>
                <td>{statusBadge(c.status)}</td>
                <td><Link to={`/clients/${c.id}`} className="view-link">View</Link></td>
              </tr>
            ))}
            {!loading && clients.length === 0 && (
              <tr><td colSpan={6} className="empty-state">No clients.</td></tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
