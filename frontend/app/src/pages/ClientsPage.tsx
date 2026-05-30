import { useEffect, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { useClients } from "../hooks/useClients";
import { useAuth } from "../auth/useAuth";
import { ClientType } from "../backend/api/backend";
import type { Client, Matter } from "../backend/api/backend";
import LoadingSpinner from "../components/LoadingSpinner";
import ErrorMessage from "../components/ErrorMessage";

// ── Helpers ──────────────────────────────────────────────────────────────────

const AVATAR_PALETTE = ["#4A90D9", "#7B68EE", "#20B2AA", "#F5A623", "#FF6B6B", "#5CB85C"];

function avatarColor(id: bigint): string {
  return AVATAR_PALETTE[Number(id % 6n)];
}
function initials(name: string): string {
  return name.split(/\s+/).slice(0, 2).map(w => w[0] ?? "").join("").toUpperCase();
}
function fmtClientId(id: bigint): string {
  return "CLT-" + String(id).padStart(4, "0");
}
function relativeDate(ns: bigint): string {
  const diff = Date.now() - Number(ns / 1_000_000n);
  const days = Math.floor(diff / 86_400_000);
  if (days === 0) return "today";
  if (days === 1) return "yesterday";
  return `${days} days ago`;
}

type FilterKey = "all" | "active" | "inactive";
type SortKey = "name-asc" | "name-desc" | "activity" | "matters";

// ── Sub-components ────────────────────────────────────────────────────────────

function ClientCard({ client, matterCount, lastActivityNs, onClick }: {
  client: Client;
  matterCount: number;
  lastActivityNs: bigint;
  onClick: () => void;
}) {
  const active = client.status === "Active";
  return (
    <div
      onClick={onClick}
      style={{
        background: "var(--surf)",
        border: "1px solid var(--bd)",
        borderRadius: 10,
        padding: "14px 16px",
        cursor: "pointer",
        opacity: active ? 1 : 0.75,
        display: "flex",
        flexDirection: "column",
        gap: 10,
        transition: "box-shadow 0.15s",
      }}
      onMouseEnter={e => (e.currentTarget.style.boxShadow = "0 2px 12px rgba(0,0,0,0.12)")}
      onMouseLeave={e => (e.currentTarget.style.boxShadow = "none")}
    >
      {/* Top row: avatar + name + status */}
      <div style={{ display: "flex", alignItems: "flex-start", gap: 10 }}>
        <div style={{
          width: 36, height: 36, borderRadius: "50%",
          background: avatarColor(client.id),
          color: "#fff",
          display: "flex", alignItems: "center", justifyContent: "center",
          fontSize: 13, fontWeight: 600, flexShrink: 0,
        }}>
          {initials(client.name)}
        </div>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontWeight: 600, fontSize: 14, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>
            {client.name}
          </div>
          <div style={{ display: "flex", alignItems: "center", gap: 6, marginTop: 3 }}>
            <span style={{ fontSize: 11, color: "var(--tx2)" }}>{fmtClientId(client.id)}</span>
            <span className={active ? "badge badge-active" : "badge badge-inactive"} style={{ fontSize: 10, padding: "1px 7px" }}>
              {active ? "Active" : "Inactive"}
            </span>
          </div>
        </div>
      </div>
      {/* Stats row */}
      <div style={{ borderTop: "1px solid var(--bd)", paddingTop: 8 }}>
        <div style={{ fontSize: 12, color: "var(--tx2)", marginBottom: 4 }}>
          <strong style={{ color: "var(--tx)" }}>{matterCount}</strong> matter{matterCount !== 1 ? "s" : ""}
        </div>
        <div style={{ fontSize: 11, color: "var(--tx2)" }}>
          {lastActivityNs > 0n ? relativeDate(lastActivityNs) : "No activity yet"}
        </div>
      </div>
    </div>
  );
}

// ── Page ──────────────────────────────────────────────────────────────────────

export default function ClientsPage() {
  const { clients, loading, error, load, createClient } = useClients();
  const { actor } = useAuth();
  const navigate = useNavigate();

  const [view, setView] = useState<"grid" | "list">("grid");
  const [filter, setFilter] = useState<FilterKey>("all");
  const [sort, setSort] = useState<SortKey>("name-asc");

  // matter data keyed by String(clientId)
  const [matterMap, setMatterMap] = useState<Map<string, Matter[]>>(new Map());

  // new client form
  const [showForm, setShowForm] = useState(false);
  const [name, setName] = useState("");
  const [clientType, setClientType] = useState<ClientType>(ClientType.Individual);
  const [email, setEmail] = useState("");
  const [phone, setPhone] = useState("");
  const [identifier, setIdentifier] = useState("");
  const [notes, setNotes] = useState("");
  const [formError, setFormError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => { void load(0n, 200n, true); }, [load]);

  useEffect(() => {
    if (!actor) return;
    actor.listMatters(0n, 500n, null).then(matters => {
      const map = new Map<string, Matter[]>();
      for (const m of matters) {
        const key = String(m.clientId);
        if (!map.has(key)) map.set(key, []);
        map.get(key)!.push(m);
      }
      setMatterMap(map);
    }).catch(() => {});
  }, [actor]);

  function matterCount(clientId: bigint): number {
    return matterMap.get(String(clientId))?.length ?? 0;
  }
  function latestActivity(clientId: bigint): bigint {
    const matters = matterMap.get(String(clientId));
    if (!matters || matters.length === 0) return 0n;
    return matters.reduce((max, m) => m.lastModifiedAt > max ? m.lastModifiedAt : max, 0n);
  }

  // filter
  const visible = clients.filter(c => {
    if (filter === "active") return c.status === "Active";
    if (filter === "inactive") return c.status === "Inactive";
    return true;
  });

  // sort
  const sorted = [...visible].sort((a, b) => {
    if (sort === "name-asc") return a.name.localeCompare(b.name);
    if (sort === "name-desc") return b.name.localeCompare(a.name);
    if (sort === "matters") return matterCount(b.id) - matterCount(a.id);
    // activity: most recent first
    const la = latestActivity(a.id);
    const lb = latestActivity(b.id);
    return lb > la ? 1 : lb < la ? -1 : 0;
  });

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
      void load(0n, 200n, true);
    } else {
      setFormError(result.err);
    }
  }

  const chipStyle = (active: boolean): React.CSSProperties => ({
    padding: "4px 12px", borderRadius: 20, fontSize: 12, fontWeight: 500,
    border: "1px solid var(--bd)", cursor: "pointer",
    background: active ? "var(--ac)" : "transparent",
    color: active ? "var(--ac-text)" : "var(--tx2)",
  });

  return (
    <div>
      {/* Top bar */}
      <div className="page-header">
        <div className="page-title">Clients</div>
        <div style={{ display: "flex", gap: 8, alignItems: "center" }}>
          {/* grid/list toggle */}
          <button
            style={{ ...chipStyle(view === "grid"), display: "flex", alignItems: "center", gap: 4 }}
            onClick={() => setView("grid")} title="Grid view"
          >
            <i className="ti ti-layout-grid" />
          </button>
          <button
            style={{ ...chipStyle(view === "list"), display: "flex", alignItems: "center", gap: 4 }}
            onClick={() => setView("list")} title="List view"
          >
            <i className="ti ti-list" />
          </button>
          <button className="add-btn" onClick={() => setShowForm(!showForm)}>
            <i className="ti ti-plus" />
            {showForm ? "Cancel" : "New client"}
          </button>
        </div>
      </div>

      {/* Toolbar */}
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 16 }}>
        <div style={{ display: "flex", gap: 6 }}>
          {(["all", "active", "inactive"] as FilterKey[]).map(f => (
            <button key={f} style={chipStyle(filter === f)} onClick={() => setFilter(f)}>
              {f.charAt(0).toUpperCase() + f.slice(1)}
            </button>
          ))}
        </div>
        <select
          className="tp-input"
          style={{ width: "auto", padding: "5px 10px", fontSize: 12 }}
          value={sort}
          onChange={e => setSort(e.target.value as SortKey)}
        >
          <option value="name-asc">Name A–Z</option>
          <option value="name-desc">Name Z–A</option>
          <option value="activity">Most recent activity</option>
          <option value="matters">Most matters</option>
        </select>
      </div>

      {/* New client form */}
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

      {/* Grid view */}
      {!loading && view === "grid" && (
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(200px, 1fr))", gap: 12, padding: "4px 0 16px" }}>
          {sorted.map(c => (
            <ClientCard
              key={String(c.id)}
              client={c}
              matterCount={matterCount(c.id)}
              lastActivityNs={latestActivity(c.id)}
              onClick={() => navigate(`/clients/${c.id}`)}
            />
          ))}
          {sorted.length === 0 && (
            <div style={{ gridColumn: "1/-1", textAlign: "center", color: "var(--tx2)", padding: 40, fontSize: 14 }}>
              No clients.
            </div>
          )}
        </div>
      )}

      {/* List view */}
      {!loading && view === "list" && (
        <div className="card">
          <table className="tp-table">
            <thead>
              <tr>
                <th>Client ID</th>
                <th>Name</th>
                <th>Type</th>
                <th>Status</th>
                <th>Matters</th>
                <th>Last activity</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              {sorted.map(c => (
                <tr key={String(c.id)}>
                  <td><span className="clt-id">{fmtClientId(c.id)}</span></td>
                  <td>{c.name}</td>
                  <td>{c.clientType}</td>
                  <td>
                    <span className={c.status === "Active" ? "badge badge-active" : "badge badge-inactive"}>
                      {c.status}
                    </span>
                  </td>
                  <td>{matterCount(c.id)}</td>
                  <td style={{ fontSize: 12, color: "var(--tx2)" }}>
                    {latestActivity(c.id) > 0n ? relativeDate(latestActivity(c.id)) : "No activity"}
                  </td>
                  <td><Link to={`/clients/${c.id}`} className="view-link">View</Link></td>
                </tr>
              ))}
              {sorted.length === 0 && (
                <tr><td colSpan={7} className="empty-state">No clients.</td></tr>
              )}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
