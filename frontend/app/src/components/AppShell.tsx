import { useState, useEffect } from "react";
import { Link, Outlet, useLocation } from "react-router-dom";
import { useAuth } from "../auth/useAuth";
import { Role } from "../backend/api/backend";

export default function AppShell() {
  const { principal, role, logout } = useAuth();
  const location = useLocation();
  const [dark, setDark] = useState(() => localStorage.getItem("tp-dark") === "1");

  useEffect(() => {
    localStorage.setItem("tp-dark", dark ? "1" : "0");
  }, [dark]);

  const truncatePrincipal = (s: string | null) =>
    s ? s.slice(0, 10) + "…" + s.slice(-4) : "";

  const isActive = (base: string) =>
    location.pathname === base || location.pathname.startsWith(base + "/");

  return (
    <div className={`app-root${dark ? " dk" : ""}`}>
      <header className="tp-head">
        <div className="tp-logo">
          The Practice <span>· Onchain Inc.</span>
        </div>
        <button className="tp-toggle" onClick={() => setDark(d => !d)}>
          <i className={dark ? "ti ti-moon" : "ti ti-sun"} />
          {dark ? "Dark mode" : "Light mode"}
        </button>
      </header>

      <div className="tp-body">
        <nav className="tp-nav">
          <div className="nav-section">Workspace</div>
          <NavLink to="/dashboard"  icon="ti-layout-dashboard" label="Dashboard"  active={isActive("/dashboard")} />
          <NavLink to="/clients"    icon="ti-users"            label="Clients"    active={isActive("/clients")} />
          <NavLink to="/matters"    icon="ti-briefcase"        label="Matters"    active={isActive("/matters")} />

          {role === Role.Partner && (
            <>
              <div className="nav-section">Admin</div>
              <NavLink to="/users" icon="ti-user-circle"  label="Users"      active={isActive("/users")} />
              <NavLink to="/audit" icon="ti-shield-check" label="Audit Log"  active={isActive("/audit")} />
            </>
          )}

          <div className="nav-footer">
            <div className="nav-principal">
              {truncatePrincipal(principal)}
              {role && <span className="nav-role">[{role}]</span>}
            </div>
            <button
              className="btn btn-neutral btn-sm btn-full"
              onClick={() => { void logout(); }}
            >
              Logout
            </button>
          </div>
        </nav>

        <main className="tp-main">
          <Outlet />
        </main>
      </div>
    </div>
  );
}

function NavLink({ to, icon, label, active }: {
  to: string; icon: string; label: string; active: boolean;
}) {
  return (
    <Link to={to} className={active ? "active" : ""}>
      <i className={`ti ${icon}`} />
      {label}
    </Link>
  );
}
