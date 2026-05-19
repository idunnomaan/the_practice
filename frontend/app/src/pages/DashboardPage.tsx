import { useEffect, useState } from "react";
import { useAuth } from "../auth/useAuth";
import LoadingSpinner from "../components/LoadingSpinner";
import ErrorMessage from "../components/ErrorMessage";
import type { MatterStatusCounts, ClientStatusCounts, DocumentStatusCounts } from "../backend/api/backend";

export default function DashboardPage() {
  const { actor, principal, role } = useAuth();
  const [matters, setMatters] = useState<MatterStatusCounts | null>(null);
  const [clients, setClients] = useState<ClientStatusCounts | null>(null);
  const [documents, setDocuments] = useState<DocumentStatusCounts | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!actor) return;
    Promise.all([
      actor.mattersByStatus(),
      actor.clientsByStatus(),
      actor.documentsByStatus(),
    ]).then(([m, c, d]) => {
      setMatters(m);
      setClients(c);
      setDocuments(d);
    }).catch((e: unknown) => {
      setError(String(e));
    }).finally(() => {
      setLoading(false);
    });
  }, [actor]);

  if (loading) return <LoadingSpinner />;

  return (
    <div>
      <h1 style={{ marginTop: 0 }}>Dashboard</h1>
      <p style={{ color: "#555" }}>
        Principal: <code>{principal}</code> &nbsp;|&nbsp; Role: <strong>{role}</strong>
      </p>

      {error && <ErrorMessage message={error} />}

      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(200px, 1fr))", gap: "1rem", marginTop: "1.5rem" }}>
        {matters && (
          <>
            <StatCard label="Open Matters" value={matters.open} />
            <StatCard label="On Hold" value={matters.onHold} />
            <StatCard label="Closed Matters" value={matters.closed} />
            <StatCard label="Archived Matters" value={matters.archived} />
          </>
        )}
        {clients && (
          <>
            <StatCard label="Active Clients" value={clients.active} />
            <StatCard label="Inactive Clients" value={clients.inactive} />
          </>
        )}
        {documents && (
          <>
            <StatCard label="Active Documents" value={documents.active} />
            <StatCard label="Deleted Documents" value={documents.deleted} />
          </>
        )}
      </div>
    </div>
  );
}

function StatCard({ label, value }: { label: string; value: bigint }) {
  return (
    <div style={{ background: "#f5f5f5", borderRadius: 8, padding: "1.25rem", textAlign: "center" }}>
      <div style={{ fontSize: "2rem", fontWeight: 700 }}>{value.toString()}</div>
      <div style={{ color: "#555", marginTop: "0.25rem" }}>{label}</div>
    </div>
  );
}
