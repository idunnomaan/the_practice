import { useState } from "react";
import { Navigate } from "react-router-dom";
import { useAuth } from "../auth/useAuth";
import LoadingSpinner from "../components/LoadingSpinner";
import ErrorMessage from "../components/ErrorMessage";

export default function LoginPage() {
  const { isAuthenticated, isLoading, login } = useAuth();
  const [error, setError] = useState<string | null>(null);
  const [loggingIn, setLoggingIn] = useState(false);

  if (isLoading) return <LoadingSpinner />;
  if (isAuthenticated) return <Navigate to="/dashboard" replace />;

  async function handleLogin() {
    setError(null);
    setLoggingIn(true);
    try {
      await login();
    } catch (e) {
      setError(String(e));
    } finally {
      setLoggingIn(false);
    }
  }

  return (
    <div style={{ display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", minHeight: "100vh", fontFamily: "sans-serif" }}>
      <div style={{ maxWidth: 380, width: "90%", textAlign: "center" }}>
        <h1 style={{ marginBottom: "0.25rem" }}>The Practice</h1>
        <p style={{ color: "#555", marginBottom: "2rem" }}>Sovereign Legal Platform</p>
        {error && <ErrorMessage message={error} onDismiss={() => setError(null)} />}
        <button
          onClick={() => { void handleLogin(); }}
          disabled={loggingIn}
          style={{
            width: "100%", padding: "0.75rem",
            background: loggingIn ? "#888" : "#1a1a2e",
            color: "#fff", border: "none", borderRadius: 6,
            fontSize: "1rem", cursor: loggingIn ? "default" : "pointer",
          }}
        >
          {loggingIn ? "Opening Internet Identity…" : "Login with Internet Identity"}
        </button>
        <p style={{ marginTop: "1rem", fontSize: "0.8rem", color: "#999" }}>
          Secured by the Internet Computer
        </p>
      </div>
    </div>
  );
}
