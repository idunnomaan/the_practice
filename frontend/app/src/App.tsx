import { BrowserRouter, Routes, Route, Navigate } from "react-router-dom";
import { AuthProvider } from "./auth/AuthContext";
import ProtectedRoute from "./components/ProtectedRoute";
import Layout from "./components/Layout";
import { PartnerOnly } from "./components/RoleGate";
import LoginPage from "./pages/LoginPage";
import DashboardPage from "./pages/DashboardPage";
import ClientsPage from "./pages/ClientsPage";
import ClientDetailPage from "./pages/ClientDetailPage";
import MattersPage from "./pages/MattersPage";
import MatterDetailPage from "./pages/MatterDetailPage";
import DocumentsPage from "./pages/DocumentsPage";
import UsersPage from "./pages/UsersPage";
import AuditPage from "./pages/AuditPage";

export default function App() {
  return (
    <AuthProvider>
      <BrowserRouter>
        <Routes>
          <Route path="/login" element={<LoginPage />} />
          <Route element={<ProtectedRoute />}>
            <Route element={<Layout />}>
              <Route index element={<Navigate to="/dashboard" replace />} />
              <Route path="/dashboard" element={<DashboardPage />} />
              <Route path="/clients" element={<ClientsPage />} />
              <Route path="/clients/:id" element={<ClientDetailPage />} />
              <Route path="/matters" element={<MattersPage />} />
              <Route path="/matters/:id" element={<MatterDetailPage />} />
              <Route path="/matters/:id/documents" element={<DocumentsPage />} />
              <Route path="/users" element={<PartnerOnly><UsersPage /></PartnerOnly>} />
              <Route path="/audit" element={<PartnerOnly><AuditPage /></PartnerOnly>} />
            </Route>
          </Route>
        </Routes>
      </BrowserRouter>
    </AuthProvider>
  );
}
