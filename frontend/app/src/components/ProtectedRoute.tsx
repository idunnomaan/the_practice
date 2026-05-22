import { Navigate, Outlet } from "react-router-dom";
import { useAuth } from "../auth/useAuth";
import LoadingSpinner from "./LoadingSpinner";

export default function ProtectedRoute() {
  const { isAuthenticated, isLoading, noAccess, principal } = useAuth();
  if (isLoading) return <LoadingSpinner />;
  if (!isAuthenticated) return <Navigate to="/login" replace />;
  if (noAccess) {
    return (
      <div style={{ padding: "2rem" }}>
        <h2>Access Denied</h2>
        <p>Your identity is not registered in this system. Contact the firm administrator.</p>
        <p>Your principal: <code>{principal}</code></p>
      </div>
    );
  }
  return <Outlet />;
}
