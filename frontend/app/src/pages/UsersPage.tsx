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
  const [roleToast, setRoleToast] = useState(false);
  const [showAddUser, setShowAddUser] = useState(false);

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
        setShowAddUser(false);
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

  function closeModal() {
    setShowAddUser(false);
    setNewPrincipal("");
    setNewRole(Role.Staff);
    setFormError(null);
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
    else {
      void load();
      setRoleToast(true);
      setTimeout(() => setRoleToast(false), 2000);
    }
  }

  return (
    <div>
      {roleToast && (
        <div style={{
          position: "fixed", bottom: 24, right: 24,
          background: "#16a34a", color: "#fff",
          padding: "10px 18px", borderRadius: 6,
          fontSize: 13, fontWeight: 500, zIndex: 1000,
          boxShadow: "0 2px 8px rgba(0,0,0,0.2)",
        }}>
          Role updated
        </div>
      )}

      {showAddUser && (
        <div style={{ position: "fixed", inset: 0, background: "rgba(0,0,0,0.4)", zIndex: 200, display: "flex", alignItems: "center", justifyContent: "center" }}>
          <div style={{ background: "var(--surf)", border: "0.5px solid var(--bd)", borderRadius: 12, padding: 24, minWidth: 340, maxWidth: 480, width: "90%" }}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 16 }}>
              <h3 style={{ margin: 0, fontSize: 16 }}>Add User</h3>
              <button className="btn btn-neutral btn-sm" onClick={closeModal}>✕</button>
            </div>
            <form className="tp-form" onSubmit={(e) => { void handleAdd(e); }}>
              {formError && <ErrorMessage message={formError} onDismiss={() => setFormError(null)} />}
              <label className="tp-label" style={{ textTransform: "none", letterSpacing: 0, fontSize: 13, color: "var(--tx)" }}>Principal *
                <input className="tp-input" value={newPrincipal} onChange={e => setNewPrincipal(e.target.value)} placeholder="xxxxx-xxxxx-…" />
              </label>
              <label className="tp-label" style={{ textTransform: "none", letterSpacing: 0, fontSize: 13, color: "var(--tx)" }}>Role
                <select className="tp-input" value={newRole} onChange={e => setNewRole(e.target.value as Role)}>
                  <option value={Role.Partner}>Partner</option>
                  <option value={Role.Associate}>Associate</option>
                  <option value={Role.Staff}>Staff</option>
                </select>
              </label>
              <div style={{ display: "flex", gap: 8, marginTop: 4 }}>
                <button type="submit" className="btn btn-primary" disabled={submitting}>
                  {submitting ? "Adding…" : "Add User"}
                </button>
                <button type="button" className="btn btn-neutral" onClick={closeModal}>Cancel</button>
              </div>
            </form>
          </div>
        </div>
      )}

      <div className="page-header">
        <div className="page-title">User Management</div>
        <button className="add-btn" onClick={() => setShowAddUser(true)}>
          <i className="ti ti-user-plus" /> Add User
        </button>
      </div>

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
                          <button className="btn btn-danger btn-sm"
                            style={{ background: "transparent", border: "1px solid var(--danger, #ef4444)", color: "var(--danger, #ef4444)" }}
                            onClick={() => { void handleAction(suspendUser, p); }}>Suspend</button>
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
