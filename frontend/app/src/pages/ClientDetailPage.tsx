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

  return (
    <div style={{ maxWidth: 640 }}>
      <h1 style={{ marginTop: 0 }}>{client.name}</h1>
      <p style={{ color: "#666", fontSize: "0.85rem", marginTop: "-0.5rem" }}>{"CLT-" + String(client.id).padStart(4, "0")}</p>
      <p><strong>Status:</strong> {client.status} &nbsp;|&nbsp; <strong>Type:</strong> {client.clientType}</p>

      {error && <ErrorMessage message={error} onDismiss={() => setError(null)} />}

      {!editing ? (
        <div style={{ display: "flex", flexDirection: "column", gap: "0.5rem" }}>
          <Row label="Email" value={client.primaryEmail ?? "—"} />
          <Row label="Phone" value={client.primaryPhone ?? "—"} />
          <Row label="Identifier" value={client.identifier ?? "—"} />
          <Row label="Notes" value={client.notes || "—"} />
          <div style={{ display: "flex", gap: "0.5rem", marginTop: "1rem" }}>
            <button onClick={() => setEditing(true)} style={btnStyle}>Edit</button>
            {role === Role.Partner && client.status === ClientStatus.Active && (
              <button onClick={() => { void handleDeactivate(); }} disabled={submitting} style={{ ...btnStyle, background: "#c00" }}>
                Deactivate
              </button>
            )}
            {role === Role.Partner && client.status === ClientStatus.Inactive && (
              <button onClick={() => { void handleReactivate(); }} disabled={submitting} style={{ ...btnStyle, background: "#060" }}>
                Reactivate
              </button>
            )}
          </div>
        </div>
      ) : (
        <form onSubmit={(e) => { void handleUpdate(e); }} style={{ display: "flex", flexDirection: "column", gap: "0.75rem" }}>
          <label>Name *<br /><input value={name} onChange={e => setName(e.target.value)} style={inputStyle} required /></label>
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
          <div style={{ display: "flex", gap: "0.5rem" }}>
            <button type="submit" disabled={submitting} style={btnStyle}>{submitting ? "Saving…" : "Save"}</button>
            <button type="button" onClick={() => setEditing(false)} style={{ ...btnStyle, background: "#888" }}>Cancel</button>
          </div>
        </form>
      )}
    </div>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div><strong>{label}:</strong> {value}</div>
  );
}

const btnStyle: React.CSSProperties = { padding: "0.5rem 1rem", background: "#1a1a2e", color: "#fff", border: "none", borderRadius: 4, cursor: "pointer" };
const inputStyle: React.CSSProperties = { width: "100%", padding: "0.4rem", boxSizing: "border-box", marginTop: 4 };
