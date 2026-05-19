import { useEffect, useState } from "react";
import { useUsers } from "../hooks/useUsers";
import { useAuth } from "../auth/useAuth";
import { Role } from "../backend/api/backend";
import type { Principal } from "@icp-sdk/core/principal";
import LoadingSpinner from "../components/LoadingSpinner";
import ErrorMessage from "../components/ErrorMessage";

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
      <h1 style={{ marginTop: 0 }}>User Management</h1>

      <form onSubmit={(e) => { void handleAdd(e); }} style={formStyle}>
        <h3 style={{ margin: 0 }}>Add User</h3>
        {formError && <ErrorMessage message={formError} onDismiss={() => setFormError(null)} />}
        <label>Principal *<br /><input value={newPrincipal} onChange={e => setNewPrincipal(e.target.value)} style={inputStyle} placeholder="xxxxx-xxxxx-…" /></label>
        <label>Role<br />
          <select value={newRole} onChange={e => setNewRole(e.target.value as Role)} style={inputStyle}>
            <option value={Role.Partner}>Partner</option>
            <option value={Role.Associate}>Associate</option>
            <option value={Role.Staff}>Staff</option>
          </select>
        </label>
        <button type="submit" disabled={submitting} style={btnStyle}>{submitting ? "Adding…" : "Add User"}</button>
      </form>

      {actionError && <ErrorMessage message={actionError} onDismiss={() => setActionError(null)} />}
      {error && <ErrorMessage message={error} />}
      {loading && <LoadingSpinner />}

      <table style={{ width: "100%", borderCollapse: "collapse", marginTop: "1rem" }}>
        <thead>
          <tr style={{ background: "#f0f0f0" }}>
            <th style={thStyle}>Principal</th>
            <th style={thStyle}>Role</th>
            <th style={thStyle}>Status</th>
            <th style={thStyle}>Actions</th>
          </tr>
        </thead>
        <tbody>
          {users.map(([p, rec]) => {
            const pText = p.toText();
            const isMe = pText === myPrincipal;
            return (
              <tr key={pText} style={{ borderBottom: "1px solid #eee", background: isMe ? "#f0f8ff" : undefined }}>
                <td style={tdStyle}><code style={{ fontSize: "0.8rem" }}>{pText.slice(0, 20)}…</code>{isMe && <span style={{ marginLeft: 4, color: "#888" }}>(you)</span>}</td>
                <td style={tdStyle}>{rec.role}</td>
                <td style={tdStyle}>{rec.suspended ? "Suspended" : "Active"}</td>
                <td style={tdStyle}>
                  {!isMe && (
                    <>
                      {rec.suspended ? (
                        <button onClick={() => { void handleAction(unsuspendUser, p); }} style={{ ...smallBtn, background: "#060" }}>Reactivate</button>
                      ) : (
                        <button onClick={() => { void handleAction(suspendUser, p); }} style={{ ...smallBtn, background: "#c00" }}>Suspend</button>
                      )}
                      <select
                        value={rec.role}
                        onChange={e => { void handleRoleChange(p, e.target.value as Role); }}
                        style={{ marginLeft: 8, padding: "0.3rem" }}
                      >
                        <option value={Role.Partner}>Partner</option>
                        <option value={Role.Associate}>Associate</option>
                        <option value={Role.Staff}>Staff</option>
                      </select>
                    </>
                  )}
                </td>
              </tr>
            );
          })}
          {!loading && users.length === 0 && (
            <tr><td colSpan={4} style={{ padding: "1rem", color: "#888", textAlign: "center" }}>No users.</td></tr>
          )}
        </tbody>
      </table>
    </div>
  );
}

const btnStyle: React.CSSProperties = { padding: "0.5rem 1rem", background: "#1a1a2e", color: "#fff", border: "none", borderRadius: 4, cursor: "pointer" };
const smallBtn: React.CSSProperties = { padding: "0.3rem 0.6rem", color: "#fff", border: "none", borderRadius: 4, cursor: "pointer", fontSize: "0.85rem" };
const formStyle: React.CSSProperties = { background: "#f9f9f9", padding: "1rem", borderRadius: 8, marginBottom: "1rem", display: "flex", flexDirection: "column", gap: "0.75rem", maxWidth: 500 };
const inputStyle: React.CSSProperties = { width: "100%", padding: "0.4rem", boxSizing: "border-box", marginTop: 4 };
const thStyle: React.CSSProperties = { padding: "0.5rem", textAlign: "left", fontWeight: 600 };
const tdStyle: React.CSSProperties = { padding: "0.5rem" };
