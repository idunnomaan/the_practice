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
    <div className="app-root">
      <div className="login-wrap">
        <div className="login-card">
          <div className="login-title">The Practice</div>
          <div className="login-sub">Sovereign Legal Platform</div>
          {error && <ErrorMessage message={error} onDismiss={() => setError(null)} />}
          <button
            className="btn btn-primary btn-full"
            onClick={() => { void handleLogin(); }}
            disabled={loggingIn}
          >
            {loggingIn ? "Opening Internet Identity…" : "Login with Internet Identity"}
          </button>
          <div className="login-footer">Secured by the Internet Computer</div>
        </div>
      </div>
    </div>
  );
}
