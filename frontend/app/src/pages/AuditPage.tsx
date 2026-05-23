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
      <div className="page-header">
        <div className="page-title">Audit Log</div>
      </div>

      {error && <ErrorMessage message={error} />}
      {loading && entries.length === 0 && <LoadingSpinner />}

      <div className="card">
        <table className="tp-table">
          <thead>
            <tr>
              <th>Time</th>
              <th>Caller</th>
              <th>Action</th>
              <th>Target</th>
              <th>Outcome</th>
            </tr>
          </thead>
          <tbody>
            {entries.map(e => (
              <tr key={String(e.id)}>
                <td className="mono" style={{ whiteSpace: "nowrap" }}>{formatTime(e.timestamp)}</td>
                <td><span className="mono">{truncate(e.caller.toText())}</span></td>
                <td>{e.action}</td>
                <td>{e.target ? <span className="mono">{truncate(e.target.toText())}</span> : "—"}</td>
                <td>
                  {e.outcome.__kind__ === "ok"
                    ? <span className="outcome-ok">✓ ok</span>
                    : <span className="outcome-err">✗ {e.outcome.err}</span>
                  }
                </td>
              </tr>
            ))}
            {!loading && entries.length === 0 && (
              <tr><td colSpan={5} className="empty-state">No entries.</td></tr>
            )}
          </tbody>
        </table>
      </div>

      {hasMore && (
        <div style={{ marginTop: 16, textAlign: "center" }}>
          <button className="btn btn-neutral" onClick={() => { void loadMore(); }} disabled={loading}>
            {loading ? "Loading…" : "Load More"}
          </button>
        </div>
      )}
    </div>
  );
}
