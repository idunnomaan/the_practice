import { useEffect, useState } from "react";
import { useUsers } from "../hooks/useUsers";
import { useAuth } from "../auth/useAuth";
import { Role } from "../backend/api/backend";
import type { Principal } from "@icp-sdk/core/principal";
import LoadingSpinner from "../components/LoadingSpinner";
import ErrorMessage from "../components/ErrorMessage";

function roleBadge(role: string) {
  return role === "Partner" ? "badge badge-partner" : "badge badge-assoc";
}

export default function UsersPage() {
  const { principal: myPrincipal } = useAuth();
  const { users, loading, error, load, addUser, suspendUser, unsuspendUser, setUserRole } = useUsers();

  const [newPrincipal, setNewPrincipal] = useState("");
  const [newRole, setNewRole] = useState<Role>(Role.Staff);
  const [formError, setFormError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);

  useEffect(() => { void load(); }, [load]);

  async function handleAdd(e: React.FormEvent) {
    e.preventDefault();
    if (!newPrincipal.trim()) { setFormError("Principal is required."); return; }
    setSubmitting(true);
    setFormError(null);
    try {
      const result = await addUser(newPrincipal.trim(), newRole);
      if (!result) return;
      if (result.__kind__ === "ok") {
        setNewPrincipal(""); setNewRole(Role.Staff);
        void load();
      } else {
        setFormError(result.err);
      }
    } catch (e) {
      setFormError(String(e));
    } finally {
      setSubmitting(false);
    }
  }

  async function handleAction(fn: (p: Principal) => Promise<{ __kind__: "ok"; ok: null } | { __kind__: "err"; err: string } | null>, p: Principal) {
    setActionError(null);
    const result = await fn(p);
    if (!result) return;
    if (result.__kind__ === "err") setActionError(result.err);
    else void load();
  }

  async function handleRoleChange(p: Principal, role: Role) {
    setActionError(null);
    const result = await setUserRole(p, role);
    if (!result) return;
    if (result.__kind__ === "err") setActionError(result.err);
    else void load();
  }

  return (
    <div>
      <div className="page-header">
        <div className="page-title">User Management</div>
      </div>

      <form className="tp-form" style={{ maxWidth: 500 }} onSubmit={(e) => { void handleAdd(e); }}>
        <h3>Add User</h3>
        {formError && <ErrorMessage message={formError} onDismiss={() => setFormError(null)} />}
        <label className="tp-label">Principal *
          <input className="tp-input" value={newPrincipal} onChange={e => setNewPrincipal(e.target.value)} placeholder="xxxxx-xxxxx-…" />
        </label>
        <label className="tp-label">Role
          <select className="tp-input" value={newRole} onChange={e => setNewRole(e.target.value as Role)}>
            <option value={Role.Partner}>Partner</option>
            <option value={Role.Associate}>Associate</option>
            <option value={Role.Staff}>Staff</option>
          </select>
        </label>
        <div>
          <button type="submit" className="btn btn-primary" disabled={submitting}>
            {submitting ? "Adding…" : "Add User"}
          </button>
        </div>
      </form>

      {actionError && <ErrorMessage message={actionError} onDismiss={() => setActionError(null)} />}
      {error && <ErrorMessage message={error} />}
      {loading && <LoadingSpinner />}

      <div className="card">
        <table className="tp-table">
          <thead>
            <tr>
              <th>Principal</th>
              <th>Role</th>
              <th>Status</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            {users.map(([p, rec]) => {
              const pText = p.toText();
              const isMe = pText === myPrincipal;
              return (
                <tr key={pText} style={{ background: isMe ? "var(--ac2)" : undefined }}>
                  <td>
                    <span className="mono">{pText.slice(0, 20)}…</span>
                    {isMe && <span style={{ marginLeft: 6, fontSize: 11, color: "var(--tx2)" }}>(you)</span>}
                  </td>
                  <td><span className={roleBadge(rec.role)}>{rec.role}</span></td>
                  <td>
                    <span className={rec.suspended ? "badge badge-suspended" : "badge badge-active"}>
                      {rec.suspended ? "Suspended" : "Active"}
                    </span>
                  </td>
                  <td>
                    {!isMe && (
                      <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                        {rec.suspended ? (
                          <button className="btn btn-success btn-sm" onClick={() => { void handleAction(unsuspendUser, p); }}>Reactivate</button>
                        ) : (
                          <button className="btn btn-danger btn-sm" onClick={() => { void handleAction(suspendUser, p); }}>Suspend</button>
                        )}
                        <select
                          className="tp-input"
                          style={{ width: "auto", padding: "5px 8px" }}
                          value={rec.role}
                          onChange={e => { void handleRoleChange(p, e.target.value as Role); }}
                        >
                          <option value={Role.Partner}>Partner</option>
                          <option value={Role.Associate}>Associate</option>
                          <option value={Role.Staff}>Staff</option>
                        </select>
                      </div>
                    )}
                  </td>
                </tr>
              );
            })}
            {!loading && users.length === 0 && (
              <tr><td colSpan={4} className="empty-state">No users.</td></tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
