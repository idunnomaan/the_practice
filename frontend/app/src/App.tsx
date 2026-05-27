import { useState } from "react";
import { BrowserRouter, Routes, Route, Navigate } from "react-router-dom";
import "./styles/theme.css";
import { AuthProvider } from "./auth/AuthContext";
import ProtectedRoute from "./components/ProtectedRoute";
import AppShell from "./components/AppShell";
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
import LibraryPage from "./pages/LibraryPage";
import AdminSettingsPage from "./pages/AdminSettingsPage";
import FileViewerModal from "./components/FileViewerModal";
import { FileViewerContext, type FileViewerSource } from "./state/fileViewerStore";

export default function App() {
  const [viewerState, setViewerState] = useState<{ open: boolean; source: FileViewerSource | null }>({
    open: false, source: null,
  });
  const fileViewerCtx = {
    state: viewerState,
    openViewer: (source: FileViewerSource) => setViewerState({ open: true, source }),
    closeViewer: () => setViewerState(s => ({ ...s, open: false })),
  };

  return (
    <FileViewerContext.Provider value={fileViewerCtx}>
    <AuthProvider>
      <BrowserRouter>
        <Routes>
          <Route path="/login" element={<LoginPage />} />
          <Route element={<ProtectedRoute />}>
            <Route element={<AppShell />}>
              <Route index element={<Navigate to="/dashboard" replace />} />
              <Route path="/dashboard" element={<DashboardPage />} />
              <Route path="/clients" element={<ClientsPage />} />
              <Route path="/clients/:id" element={<ClientDetailPage />} />
              <Route path="/matters" element={<MattersPage />} />
              <Route path="/matters/:id" element={<MatterDetailPage />} />
              <Route path="/matters/:id/documents" element={<DocumentsPage />} />
              <Route path="/library" element={<LibraryPage />} />
              <Route path="/users" element={<PartnerOnly><UsersPage /></PartnerOnly>} />
              <Route path="/audit" element={<PartnerOnly><AuditPage /></PartnerOnly>} />
              <Route path="/admin" element={<AdminSettingsPage />} />
            </Route>
          </Route>
        </Routes>
      </BrowserRouter>
      <FileViewerModal />
    </AuthProvider>
    </FileViewerContext.Provider>
  );
}
