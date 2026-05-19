import React, { createContext, useContext, useEffect, useRef, useState } from "react";
import { AuthClient } from "@icp-sdk/auth/client";
import type { Identity } from "@icp-sdk/core/agent";
import { getActor } from "../api/canister";
import { Role } from "../backend/api/backend";
import type { Backend } from "../backend/api/backend";

// @icp-sdk/auth@7.0.0 API (differs from skill docs which show the older v5 API):
//   new AuthClient({ identityProvider }) — constructor, not AuthClient.create()
//   client.isAuthenticated()            — synchronous boolean
//   client.getIdentity()                — async, returns Promise<Identity>
//   client.signIn({ maxTimeToLive })    — async, opens popup, returns Promise<Identity>
//   client.signOut()                    — async

// icp-cli >= 0.2.4: mainnet II validates against local replica — no local II deployment needed
const II_URL = "https://id.ai";
const MAX_TTL = BigInt(8) * BigInt(3_600_000_000_000); // 8 hours in nanoseconds

export interface AuthContextValue {
  isAuthenticated: boolean;
  principal: string | null;
  role: Role | null;
  actor: Backend | null;
  login: () => Promise<void>;
  logout: () => Promise<void>;
  isLoading: boolean;
  noAccess: boolean; // authenticated with II but principal not registered in canister
}

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const clientRef = useRef<AuthClient | null>(null);
  const [isAuthenticated, setIsAuthenticated] = useState(false);
  const [principal, setPrincipal] = useState<string | null>(null);
  const [role, setRole] = useState<Role | null>(null);
  const [actor, setActor] = useState<Backend | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [noAccess, setNoAccess] = useState(false);

  async function applyIdentity(identity: Identity) {
    const backend = await getActor(identity);
    const principalText = identity.getPrincipal().toText();
    const roleResult = await backend.getMyRole();

    if (roleResult === null) {
      // Principal not registered — show no-access state, don't crash
      setNoAccess(true);
      setIsAuthenticated(true);
      setPrincipal(principalText);
      setActor(null);
      setRole(null);
      return;
    }

    setActor(backend);
    setPrincipal(principalText);
    setRole(roleResult);
    setIsAuthenticated(true);
    setNoAccess(false);
  }

  useEffect(() => {
    const client = new AuthClient({ identityProvider: II_URL });
    clientRef.current = client;

    if (client.isAuthenticated()) {
      client.getIdentity()
        .then((identity) => applyIdentity(identity))
        .catch((e: unknown) => console.error("Session restore failed:", e))
        .finally(() => setIsLoading(false));
    } else {
      setIsLoading(false);
    }
    // applyIdentity only calls stable state setters — no deps needed
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function login() {
    const client = clientRef.current;
    if (!client) return;
    setIsLoading(true);
    try {
      const identity = await client.signIn({ maxTimeToLive: MAX_TTL });
      await applyIdentity(identity);
    } finally {
      setIsLoading(false);
    }
  }

  async function logout() {
    const client = clientRef.current;
    if (!client) return;
    await client.signOut();
    setIsAuthenticated(false);
    setPrincipal(null);
    setRole(null);
    setActor(null);
    setNoAccess(false);
  }

  return (
    <AuthContext.Provider value={{ isAuthenticated, principal, role, actor, login, logout, isLoading, noAccess }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth must be used inside AuthProvider");
  return ctx;
}
