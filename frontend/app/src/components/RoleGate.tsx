import type React from "react";
import { Role } from "../backend/api/backend";
import { useAuth } from "../auth/useAuth";

interface Props {
  children: React.ReactNode;
}

export function PartnerOnly({ children }: Props) {
  const { role } = useAuth();
  if (role !== Role.Partner) {
    return <div style={{ padding: "1rem", color: "#888" }}>Access denied — Partners only.</div>;
  }
  return <>{children}</>;
}
