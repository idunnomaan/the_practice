import { Link, Outlet } from "react-router-dom";
import { useAuth } from "../auth/useAuth";
import { Role } from "../backend/api/backend";

export default function Layout() {
  const { principal, role, logout } = useAuth();

  const truncate = (s: string | null) =>
    s ? s.slice(0, 12) + "…" + s.slice(-4) : "";

  return (
    <div style={{ display: "flex", minHeight: "100vh", fontFamily: "sans-serif" }}>
      <nav style={{
        width: 200, background: "#1a1a2e", color: "#eee", padding: "1rem",
        display: "flex", flexDirection: "column", gap: "0.5rem", flexShrink: 0,
      }}>
        <div style={{ fontWeight: 700, fontSize: "1.1rem", marginBottom: "1rem", color: "#fff" }}>
          The Practice
        </div>
        <NavLink to="/dashboard">Dashboard</NavLink>
        <NavLink to="/clients">Clients</NavLink>
        <NavLink to="/matters">Matters</NavLink>
        {role === Role.Partner && <NavLink to="/users">Users</NavLink>}
        {role === Role.Partner && <NavLink to="/audit">Audit Log</NavLink>}
        <div style={{ marginTop: "auto", borderTop: "1px solid #444", paddingTop: "0.75rem" }}>
          <div style={{ fontSize: "0.75rem", color: "#aaa", marginBottom: "0.5rem" }}>
            {truncate(principal)}
            {role && <span style={{ marginLeft: "0.5rem", color: "#7af" }}>[{role}]</span>}
          </div>
          <button
            onClick={() => { void logout(); }}
            style={{ width: "100%", padding: "0.4rem", background: "#c00", color: "#fff", border: "none", borderRadius: 4, cursor: "pointer" }}
          >
            Logout
          </button>
        </div>
      </nav>
      <main style={{ flex: 1, padding: "1.5rem", overflowY: "auto" }}>
        <Outlet />
      </main>
    </div>
  );
}

function NavLink({ to, children }: { to: string; children: React.ReactNode }) {
  return (
    <Link to={to} style={{ color: "#cce", textDecoration: "none", padding: "0.4rem 0.5rem", borderRadius: 4 }}>
      {children}
    </Link>
  );
}
