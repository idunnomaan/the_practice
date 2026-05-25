import type { TopUpRequestRecord } from "../backend/api/backend";
import { TopUpRequestStatus } from "../backend/api/backend";

interface Props {
  requests: TopUpRequestRecord[];
  isOps: boolean;
  isMaster: boolean;
  onFulfill: (id: bigint) => Promise<void>;
  onCancel: (id: bigint) => Promise<void>;
  onRefresh: () => void;
}

function statusBadge(status: TopUpRequestStatus) {
  if (status === TopUpRequestStatus.Pending)
    return <span className="badge" style={{ background: "var(--warn, #f59e0b)", color: "#000" }}>Pending</span>;
  if (status === TopUpRequestStatus.Fulfilled)
    return <span className="badge badge-active">Fulfilled</span>;
  return <span className="badge badge-archived">Cancelled</span>;
}

function shortDate(ns: bigint) {
  return new Date(Number(ns / 1_000_000n)).toLocaleDateString();
}

export default function TopUpRequestList({ requests, isOps, isMaster, onFulfill, onCancel, onRefresh }: Props) {
  if (requests.length === 0) {
    return <div style={{ color: "var(--tx2)", fontSize: 13 }}>No top-up requests yet.</div>;
  }

  return (
    <table className="tp-table">
      <thead>
        <tr>
          <th>#</th>
          <th>Amount</th>
          <th>Note</th>
          <th>Status</th>
          <th>Requested</th>
          <th></th>
        </tr>
      </thead>
      <tbody>
        {requests.map(req => (
          <tr key={String(req.id)}>
            <td style={{ color: "var(--tx2)", fontSize: 12 }}>{String(req.id)}</td>
            <td>{String(req.requestedTrillionCycles)}T</td>
            <td style={{ fontSize: 12, color: "var(--tx2)", maxWidth: 200 }}>{req.note || "—"}</td>
            <td>{statusBadge(req.status)}</td>
            <td style={{ fontSize: 12, color: "var(--tx2)" }}>{shortDate(req.createdAt)}</td>
            <td>
              <div style={{ display: "flex", gap: 6 }}>
                {req.status === TopUpRequestStatus.Pending && isOps && (
                  <button
                    className="btn btn-primary btn-sm"
                    onClick={() => { void onFulfill(req.id).then(onRefresh); }}
                  >
                    Mark fulfilled
                  </button>
                )}
                {req.status === TopUpRequestStatus.Pending && isMaster && (
                  <button
                    className="btn btn-danger btn-sm"
                    onClick={() => { void onCancel(req.id).then(onRefresh); }}
                  >
                    Cancel
                  </button>
                )}
              </div>
            </td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}
