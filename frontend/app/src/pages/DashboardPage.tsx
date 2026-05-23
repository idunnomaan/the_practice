import { useEffect, useState } from "react";
import { useAuth } from "../auth/useAuth";
import LoadingSpinner from "../components/LoadingSpinner";
import ErrorMessage from "../components/ErrorMessage";
import type { MatterStatusCounts, ClientStatusCounts, DocumentStatusCounts } from "../backend/api/backend";

export default function DashboardPage() {
  const { actor } = useAuth();
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
      <div className="page-title" style={{ marginBottom: 22 }}>Dashboard</div>

      {error && <ErrorMessage message={error} />}

      {matters && (
        <div className="stat-grid">
          <StatCard icon="ti-briefcase"    label="Open Matters"  value={matters.open} />
          <StatCard icon="ti-pause"        label="On Hold"       value={matters.onHold} />
          <StatCard icon="ti-check"        label="Closed"        value={matters.closed} />
          <StatCard icon="ti-archive"      label="Archived"      value={matters.archived} />
        </div>
      )}

      {(clients || documents) && (
        <div className="stat-grid">
          {clients && (
            <>
              <StatCard icon="ti-users"      label="Active Clients"   value={clients.active} />
              <StatCard icon="ti-user-off"   label="Inactive Clients" value={clients.inactive} />
            </>
          )}
          {documents && (
            <>
              <StatCard icon="ti-files"       label="Active Documents"  value={documents.active} />
              <StatCard icon="ti-trash"        label="Deleted Documents" value={documents.deleted} />
            </>
          )}
        </div>
      )}
    </div>
  );
}

function StatCard({ label, value, icon }: { label: string; value: bigint; icon: string }) {
  return (
    <div className="stat-card">
      <div className="stat-icon"><i className={`ti ${icon}`} /></div>
      <div className="stat-label">{label}</div>
      <div className="stat-val">{value.toString()}</div>
    </div>
  );
}
