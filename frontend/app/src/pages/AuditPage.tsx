import { useEffect } from "react";
import { useAudit } from "../hooks/useAudit";
import LoadingSpinner from "../components/LoadingSpinner";
import ErrorMessage from "../components/ErrorMessage";

export default function AuditPage() {
  const { entries, loading, error, hasMore, loadFirst, loadMore } = useAudit();

  useEffect(() => { void loadFirst(); }, [loadFirst]);

  function formatTime(ns: bigint) {
    const ms = Number(ns / 1_000_000n);
    return new Date(ms).toLocaleString();
  }

  function truncate(s: string) {
    if (s.length <= 20) return s;
    return s.slice(0, 10) + "…" + s.slice(-6);
  }

  return (
    <div>
      <h1 style={{ marginTop: 0 }}>Audit Log</h1>

      {error && <ErrorMessage message={error} />}
      {loading && entries.length === 0 && <LoadingSpinner />}

      <table style={{ width: "100%", borderCollapse: "collapse", fontSize: "0.9rem" }}>
        <thead>
          <tr style={{ background: "#f0f0f0" }}>
            <th style={thStyle}>ID</th>
            <th style={thStyle}>Timestamp</th>
            <th style={thStyle}>Caller</th>
            <th style={thStyle}>Action</th>
            <th style={thStyle}>Target</th>
            <th style={thStyle}>Outcome</th>
          </tr>
        </thead>
        <tbody>
          {entries.map(e => (
            <tr key={String(e.id)} style={{ borderBottom: "1px solid #eee" }}>
              <td style={tdStyle}>{String(e.id)}</td>
              <td style={tdStyle}>{formatTime(e.timestamp)}</td>
              <td style={tdStyle}><code style={{ fontSize: "0.8rem" }}>{truncate(e.caller.toText())}</code></td>
              <td style={tdStyle}>{e.action}</td>
              <td style={tdStyle}>{e.target ? <code style={{ fontSize: "0.8rem" }}>{truncate(e.target.toText())}</code> : "—"}</td>
              <td style={tdStyle}>
                {e.outcome.__kind__ === "ok"
                  ? <span style={{ color: "#060" }}>✓ ok</span>
                  : <span style={{ color: "#c00" }}>✗ {e.outcome.err}</span>
                }
              </td>
            </tr>
          ))}
          {!loading && entries.length === 0 && (
            <tr><td colSpan={6} style={{ padding: "1rem", color: "#888", textAlign: "center" }}>No entries.</td></tr>
          )}
        </tbody>
      </table>

      {hasMore && (
        <button onClick={() => { void loadMore(); }} disabled={loading} style={{ ...btnStyle, marginTop: "1rem" }}>
          {loading ? "Loading…" : "Load More"}
        </button>
      )}
    </div>
  );
}

const btnStyle: React.CSSProperties = { padding: "0.5rem 1rem", background: "#1a1a2e", color: "#fff", border: "none", borderRadius: 4, cursor: "pointer" };
const thStyle: React.CSSProperties = { padding: "0.5rem", textAlign: "left", fontWeight: 600 };
const tdStyle: React.CSSProperties = { padding: "0.5rem" };
