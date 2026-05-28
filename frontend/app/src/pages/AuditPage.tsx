import { useEffect } from "react";
import { useAudit } from "../hooks/useAudit";
import LoadingSpinner from "../components/LoadingSpinner";
import ErrorMessage from "../components/ErrorMessage";

function fmtAction(raw: string): string {
  const map: Record<string, string> = {
    install: "System installed",
    addUser: "User added",
    createClient: "Client created",
    updateClient: "Client updated",
    deactivateClient: "Client deactivated",
    reactivateClient: "Client reactivated",
    createMatter: "Matter created",
    putMatterOnHold: "Matter put on hold",
    resumeMatter: "Matter resumed",
    closeMatter: "Matter closed",
    archiveMatter: "Matter archived",
    "library.upload.start": "Library upload started",
    appendLibraryChunk: "Library file chunk uploaded",
    grantOperations: "Operations principal granted",
    revokeOperations: "Operations principal revoked",
    transferMasterController: "Master controller transferred",
    readAuditEntries: "Audit log read",
    setStorageBudget: "Storage budget updated",
    requestCycleTopUp: "Cycle top-up requested",
    // In-App File Rendering sprint (2026-05-27) — format changed to dot-notation
    "document.view": "Document viewed",
    "document.download": "Document downloaded",
    "libraryItem.view": "Library item viewed",
    "library.download": "Library item downloaded",
    "compliance.certificate.generate": "Compliance certificate generated",
  };
  // Handle dynamic keys like "library.upload:1", "library.upload:2", …
  if (/^library\.upload:\d+$/.test(raw)) return "Library file chunk uploaded";
  return map[raw] ?? raw; // fall through: show raw if unmapped (catches future additions)
}

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
            {[...entries].reverse().map(e => (
              <tr key={String(e.id)}>
                <td className="mono" style={{ whiteSpace: "nowrap" }}>{formatTime(e.timestamp)}</td>
                <td><span className="mono">{truncate(e.caller.toText())}</span></td>
                <td>{fmtAction(e.action)}</td>
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
