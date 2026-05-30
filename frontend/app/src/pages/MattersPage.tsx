import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { useMatters } from "../hooks/useMatters";
import { useAuth } from "../auth/useAuth";
import type { Client, Matter } from "../backend/api/backend";
import LoadingSpinner from "../components/LoadingSpinner";
import ErrorMessage from "../components/ErrorMessage";
import { MATTER_TYPES } from "../constants/matterTypes";

// ── Helpers ──────────────────────────────────────────────────────────────────

const STATUS_COLORS: Record<string, { border: string; badge: string }> = {
  Open:     { border: "#1976d2", badge: "badge badge-open" },
  OnHold:   { border: "#f9a825", badge: "badge badge-hold" },
  Closed:   { border: "#78909c", badge: "badge badge-closed" },
  Archived: { border: "#c62828", badge: "badge badge-archived" },
};

function fmtClientId(id: bigint): string {
  return "CLT-" + String(id).padStart(4, "0");
}
function daysOpen(ns: bigint): number {
  return Math.floor((Date.now() - Number(ns / 1_000_000n)) / 86_400_000);
}
function truncPrincipal(p: { toText(): string } | undefined): string {
  if (!p) return "Unassigned";
  const t = p.toText();
  return t.slice(0, 8) + "…" + t.slice(-4);
}
type FilterKey = "all" | "Open" | "OnHold" | "Closed" | "Archived";
type SortKey = "newest" | "oldest" | "days" | "client";

const FILTER_LABELS: Record<FilterKey, string> = {
  all: "All", Open: "Open", OnHold: "On hold", Closed: "Closed", Archived: "Archived",
};

// ── Matter card ───────────────────────────────────────────────────────────────

function MatterCard({ matter, clientName, logCount, logMore, docCount, docMore, onClick }: {
  matter: Matter;
  clientName: string;
  logCount: number;
  logMore: boolean;
  docCount: number;
  docMore: boolean;
  onClick: () => void;
}) {
  const sc = STATUS_COLORS[matter.status] ?? STATUS_COLORS.Closed;
  const days = daysOpen(matter.createdAt);
  return (
    <div
      onClick={onClick}
      style={{
        background: "var(--surf)",
        border: "1px solid var(--bd)",
        borderTop: `3px solid ${sc.border}`,
        borderRadius: 10,
        padding: "12px 14px",
        cursor: "pointer",
        display: "flex",
        flexDirection: "column",
        gap: 8,
        transition: "box-shadow 0.15s",
      }}
      onMouseEnter={e => (e.currentTarget.style.boxShadow = "0 2px 12px rgba(0,0,0,0.12)")}
      onMouseLeave={e => (e.currentTarget.style.boxShadow = "none")}
    >
      {/* Status row */}
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
        <span className={sc.badge} style={{ fontSize: 10, padding: "2px 8px" }}>
          {matter.status === "OnHold" ? "On hold" : matter.status}
        </span>
        <span style={{ fontSize: 11, color: "var(--tx2)" }}>{days}d</span>
      </div>
      {/* Title */}
      <div style={{ fontWeight: 600, fontSize: 14, lineHeight: 1.3 }}>
        {matter.title}
      </div>
      {/* Client */}
      <div style={{ fontSize: 12, color: "var(--tx2)" }}>
        <span style={{ fontFamily: "monospace" }}>{fmtClientId(matter.clientId)}</span>
        {clientName && <span> · {clientName}</span>}
      </div>
      {/* Stats */}
      <div style={{ borderTop: "1px solid var(--bd)", paddingTop: 8, fontSize: 12, color: "var(--tx2)" }}>
        <div style={{ display: "flex", gap: 10, marginBottom: 3 }}>
          <span><strong style={{ color: "var(--tx)" }}>{docMore ? docCount + "+" : docCount}</strong> docs</span>
          <span>·</span>
          <span><strong style={{ color: "var(--tx)" }}>{logMore ? logCount + "+" : logCount}</strong> log{logCount !== 1 || logMore ? "s" : ""}</span>
        </div>
        <div>{matter.assignedPartner ? truncPrincipal(matter.assignedPartner) : "Unassigned"}</div>
      </div>
    </div>
  );
}

// ── Page ──────────────────────────────────────────────────────────────────────

export default function MattersPage() {
  const { matters, loading, error, load, createMatter } = useMatters();
  const { actor } = useAuth();
  const navigate = useNavigate();

  const [view, setView] = useState<"grid" | "list">("grid");
  const [filter, setFilter] = useState<FilterKey>("all");
  const [sort, setSort] = useState<SortKey>("newest");

  // client name map
  const [clientMap, setClientMap] = useState<Map<string, string>>(new Map());
  // log counts: matterId → { count, more }
  const [logCounts, setLogCounts] = useState<Map<string, { count: number; more: boolean }>>(new Map());
  // doc counts: matterId → { count, more }
  const [docCounts, setDocCounts] = useState<Map<string, { count: number; more: boolean }>>(new Map());

  // new matter form
  const [showForm, setShowForm] = useState(false);
  const [title, setTitle] = useState("");
  const [matterType, setMatterType] = useState("");
  const [clientId, setClientId] = useState("");
  const [partner, setPartner] = useState("");
  const [description, setDescription] = useState("");
  const [formError, setFormError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => { void load(0n, 200n, null); }, [load]);

  // Load clients for name resolution
  useEffect(() => {
    if (!actor) return;
    actor.listClients(0n, 200n, true).then((clients: Client[]) => {
      const map = new Map<string, string>();
      for (const c of clients) map.set(String(c.id), c.name);
      setClientMap(map);
    }).catch(() => {});
  }, [actor]);

  // Load log + doc counts per matter once matters are available
  useEffect(() => {
    if (!actor || matters.length === 0) return;
    const PAGE = 50n;
    const logPromises = matters.map(async m => {
      try {
        const r = await actor.getMatterLogs(m.id, null, PAGE);
        if (r.__kind__ === "ok") return [String(m.id), { count: r.ok.entries.length, more: r.ok.hasMore }] as const;
      } catch {}
      return [String(m.id), { count: 0, more: false }] as const;
    });
    const docPromises = matters.map(async m => {
      try {
        const docs = await actor.listDocumentsByMatter(m.id, 0n, PAGE, false);
        return [String(m.id), { count: docs.length, more: docs.length === Number(PAGE) }] as const;
      } catch {}
      return [String(m.id), { count: 0, more: false }] as const;
    });
    Promise.all(logPromises).then(entries => setLogCounts(new Map(entries)));
    Promise.all(docPromises).then(entries => setDocCounts(new Map(entries)));
  }, [actor, matters]);

  // filter + sort
  const visible = matters.filter(m => {
    if (filter === "all") return true;
    return m.status === filter;
  });
  const sorted = [...visible].sort((a, b) => {
    if (sort === "newest") return Number(b.createdAt - a.createdAt > 0n ? 1n : -1n);
    if (sort === "oldest") return Number(a.createdAt - b.createdAt > 0n ? 1n : -1n);
    if (sort === "days") return daysOpen(a.createdAt) - daysOpen(b.createdAt); // oldest open first
    if (sort === "client") return (clientMap.get(String(a.clientId)) ?? "").localeCompare(clientMap.get(String(b.clientId)) ?? "");
    return 0;
  });

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
        void load(0n, 200n, null);
      } else {
        setFormError(result.err);
      }
    } catch (e) {
      setFormError(String(e));
    } finally {
      setSubmitting(false);
    }
  }

  const chipStyle = (active: boolean, borderColor?: string): React.CSSProperties => ({
    padding: "4px 12px", borderRadius: 20, fontSize: 12, fontWeight: 500,
    border: active && borderColor ? `1.5px solid ${borderColor}` : "1px solid var(--bd)",
    cursor: "pointer",
    background: active ? "var(--ac)" : "transparent",
    color: active ? "var(--ac-text)" : "var(--tx2)",
  });

  const filterChips: { key: FilterKey; color?: string }[] = [
    { key: "all" },
    { key: "Open",     color: "#1976d2" },
    { key: "OnHold",   color: "#f9a825" },
    { key: "Closed",   color: "#78909c" },
    { key: "Archived", color: "#c62828" },
  ];

  return (
    <div>
      {/* Top bar */}
      <div className="page-header">
        <div className="page-title">Matters</div>
        <div style={{ display: "flex", gap: 8, alignItems: "center" }}>
          <button style={{ ...chipStyle(view === "grid"), display: "flex", alignItems: "center", gap: 4 }}
            onClick={() => setView("grid")} title="Grid view">
            <i className="ti ti-layout-grid" />
          </button>
          <button style={{ ...chipStyle(view === "list"), display: "flex", alignItems: "center", gap: 4 }}
            onClick={() => setView("list")} title="List view">
            <i className="ti ti-list" />
          </button>
          <button className="add-btn" onClick={() => setShowForm(!showForm)}>
            <i className="ti ti-plus" />
            {showForm ? "Cancel" : "New matter"}
          </button>
        </div>
      </div>

      {/* Toolbar */}
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 16, flexWrap: "wrap", gap: 8 }}>
        <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
          {filterChips.map(({ key, color }) => (
            <button key={key} style={chipStyle(filter === key, color)} onClick={() => setFilter(key)}>
              {FILTER_LABELS[key]}
            </button>
          ))}
        </div>
        <select className="tp-input" style={{ width: "auto", padding: "5px 10px", fontSize: 12 }}
          value={sort} onChange={e => setSort(e.target.value as SortKey)}>
          <option value="newest">Newest</option>
          <option value="oldest">Oldest</option>
          <option value="days">Days open</option>
          <option value="client">Client name</option>
        </select>
      </div>

      {/* New matter form */}
      {showForm && (
        <form className="tp-form" onSubmit={(e) => { void handleCreate(e); }}>
          {formError && <ErrorMessage message={formError} onDismiss={() => setFormError(null)} />}
          <label className="tp-label">Title *
            <input className="tp-input" value={title} onChange={e => setTitle(e.target.value)} required />
          </label>
          <label className="tp-label">Matter Type
            <select className="tp-input" value={matterType} onChange={e => setMatterType(e.target.value)}>
              <option value="">— Select type —</option>
              {MATTER_TYPES.map(t => <option key={t} value={t}>{t}</option>)}
            </select>
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

      {/* Grid view */}
      {!loading && view === "grid" && (
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(200px, 1fr))", gap: 12, padding: "4px 0 16px" }}>
          {sorted.map(m => (
            <MatterCard
              key={String(m.id)}
              matter={m}
              clientName={clientMap.get(String(m.clientId)) ?? ""}
              logCount={logCounts.get(String(m.id))?.count ?? 0}
              logMore={logCounts.get(String(m.id))?.more ?? false}
              docCount={docCounts.get(String(m.id))?.count ?? 0}
              docMore={docCounts.get(String(m.id))?.more ?? false}
              onClick={() => navigate(`/matters/${m.id}`)}
            />
          ))}
          {sorted.length === 0 && (
            <div style={{ gridColumn: "1/-1", textAlign: "center", color: "var(--tx2)", padding: 40, fontSize: 14 }}>
              No matters.
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
                <th>ID</th>
                <th>Title</th>
                <th>Type</th>
                <th>Client</th>
                <th>Status</th>
                <th>Days</th>
                <th>Docs</th>
                <th>Logs</th>
              </tr>
            </thead>
            <tbody>
              {sorted.map(m => {
                const sc = STATUS_COLORS[m.status] ?? STATUS_COLORS.Closed;
                const lc = logCounts.get(String(m.id));
                const dc = docCounts.get(String(m.id));
                return (
                  <tr key={String(m.id)} style={{ cursor: "pointer" }} onClick={() => navigate(`/matters/${m.id}`)}>
                    <td><span className="mono">{String(m.id).padStart(3, "0")}</span></td>
                    <td>{m.title}</td>
                    <td style={{ fontSize: 12, color: "var(--tx2)" }}>{m.matterType || "—"}</td>
                    <td>
                      <span className="clt-id">{fmtClientId(m.clientId)}</span>
                      <span style={{ fontSize: 11, color: "var(--tx2)", marginLeft: 4 }}>{clientMap.get(String(m.clientId)) ?? ""}</span>
                    </td>
                    <td><span className={sc.badge} style={{ fontSize: 10 }}>{m.status === "OnHold" ? "On hold" : m.status}</span></td>
                    <td style={{ fontSize: 12, color: "var(--tx2)" }}>{daysOpen(m.createdAt)}d</td>
                    <td style={{ fontSize: 12 }}>{dc ? (dc.more ? dc.count + "+" : dc.count) : "—"}</td>
                    <td style={{ fontSize: 12 }}>{lc ? (lc.more ? lc.count + "+" : lc.count) : "—"}</td>
                  </tr>
                );
              })}
              {sorted.length === 0 && (
                <tr><td colSpan={8} className="empty-state">No matters.</td></tr>
              )}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
