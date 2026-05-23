import { useEffect, useState } from "react";
import { useParams } from "react-router-dom";
import { useClients } from "../hooks/useClients";
import { useAuth } from "../auth/useAuth";
import { Role, ClientType, ClientStatus } from "../backend/api/backend";
import type { Client } from "../backend/api/backend";
import LoadingSpinner from "../components/LoadingSpinner";
import ErrorMessage from "../components/ErrorMessage";

export default function ClientDetailPage() {
  const { id } = useParams<{ id: string }>();
  const { role } = useAuth();
  const { getClient, updateClient, deactivateClient, reactivateClient } = useClients();

  const [client, setClient] = useState<Client | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [editing, setEditing] = useState(false);
  const [submitting, setSubmitting] = useState(false);

  const [name, setName] = useState("");
  const [clientType, setClientType] = useState<ClientType>(ClientType.Individual);
  const [email, setEmail] = useState("");
  const [phone, setPhone] = useState("");
  const [identifier, setIdentifier] = useState("");
  const [notes, setNotes] = useState("");

  async function load() {
    if (!id) return;
    setLoading(true);
    setError(null);
    const c = await getClient(BigInt(id));
    setLoading(false);
    if (!c) { setError("Client not found."); return; }
    setClient(c);
    setName(c.name);
    setClientType(c.clientType);
    setEmail(c.primaryEmail ?? "");
    setPhone(c.primaryPhone ?? "");
    setIdentifier(c.identifier ?? "");
    setNotes(c.notes);
  }

  useEffect(() => { void load(); }, [id]); // eslint-disable-line react-hooks/exhaustive-deps

  async function handleUpdate(e: React.FormEvent) {
    e.preventDefault();
    if (!client) return;
    setSubmitting(true);
    setError(null);
    const result = await updateClient(
      client.id, name.trim() || null, clientType,
      email.trim() || null, phone.trim() || null, identifier.trim() || null, notes.trim() || null,
    );
    setSubmitting(false);
    if (!result) return;
    if (result.__kind__ === "ok") {
      setEditing(false);
      void load();
    } else {
      setError(result.err);
    }
  }

  async function handleDeactivate() {
    if (!client) return;
    setSubmitting(true);
    setError(null);
    const result = await deactivateClient(client.id);
    setSubmitting(false);
    if (!result) return;
    if (result.__kind__ === "err") setError(result.err);
    else void load();
  }

  async function handleReactivate() {
    if (!client) return;
    setSubmitting(true);
    setError(null);
    const result = await reactivateClient(client.id);
    setSubmitting(false);
    if (!result) return;
    if (result.__kind__ === "err") setError(result.err);
    else void load();
  }

  if (loading) return <LoadingSpinner />;
  if (!client) return <ErrorMessage message={error ?? "Client not found."} />;

  const statusCls = client.status === ClientStatus.Active ? "badge badge-active" : "badge badge-inactive";

  return (
    <div className="detail-page">
      <div className="page-header">
        <div>
          <div className="page-title">{client.name}</div>
          <div className="detail-meta">
            <span className="clt-id">{"CLT-" + String(client.id).padStart(4, "0")}</span>
            &nbsp;·&nbsp;<span className={statusCls}>{client.status}</span>
            &nbsp;·&nbsp;{client.clientType}
          </div>
        </div>
      </div>

      {error && <ErrorMessage message={error} onDismiss={() => setError(null)} />}

      {!editing ? (
        <>
          <div className="card" style={{ padding: "16px 20px", marginBottom: 18 }}>
            <div className="detail-field"><strong>Email</strong>{client.primaryEmail ?? "—"}</div>
            <div className="detail-field"><strong>Phone</strong>{client.primaryPhone ?? "—"}</div>
            <div className="detail-field"><strong>Identifier</strong>{client.identifier ?? "—"}</div>
            <div className="detail-field"><strong>Notes</strong>{client.notes || "—"}</div>
          </div>
          <div className="transition-btns">
            <button className="btn btn-primary btn-sm" onClick={() => setEditing(true)}>
              <i className="ti ti-pencil" /> Edit
            </button>
            {role === Role.Partner && client.status === ClientStatus.Active && (
              <button className="btn btn-danger btn-sm" onClick={() => { void handleDeactivate(); }} disabled={submitting}>
                Deactivate
              </button>
            )}
            {role === Role.Partner && client.status === ClientStatus.Inactive && (
              <button className="btn btn-success btn-sm" onClick={() => { void handleReactivate(); }} disabled={submitting}>
                Reactivate
              </button>
            )}
          </div>
        </>
      ) : (
        <form className="tp-form" onSubmit={(e) => { void handleUpdate(e); }}>
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
