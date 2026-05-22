import React, { createContext, useContext, useEffect, useState } from "react";
import { Signer } from "@icp-sdk/signer";
import { PostMessageTransport } from "@icp-sdk/signer/web";
import { IdbStorage, KEY_STORAGE_KEY, KEY_STORAGE_DELEGATION } from "@icp-sdk/auth/client";
import {
  ECDSAKeyIdentity,
  DelegationChain,
  DelegationIdentity,
  isDelegationValid,
} from "@icp-sdk/core/identity";
import { getActor } from "../api/canister";
import { Role } from "../backend/api/backend";
import type { Backend } from "../backend/api/backend";

// Must be /authorize — root (https://id.ai) redirects to /manage which does not implement ICRC-25
const II_URL = "https://id.ai/authorize";
const KEY_EXPIRATION = "ic-delegation_expiration";
const MAX_TTL = BigInt(8) * BigInt(3_600_000_000_000);

// Use Signer+PostMessageTransport directly rather than AuthClient to allow
// disconnectTimeout: 30 000 ms. AuthClient hardcodes 2 000 ms — too short when
// the WebAuthn passkey prompt briefly pauses the popup's JavaScript execution,
// starving the ICRC-29 heartbeat and triggering a spurious channel close.
const transport = new PostMessageTransport({
  url: II_URL,
  disconnectTimeout: 30_000,
});
const signer = new Signer({ transport });
const storage = new IdbStorage();

function isSessionValid(): boolean {
  const value = localStorage.getItem(KEY_EXPIRATION);
  if (value === null) return false;
  return BigInt(Date.now()) * BigInt(1_000_000) < BigInt(value);
}

async function persistSession(key: ECDSAKeyIdentity, chain: DelegationChain): Promise<void> {
  await storage.set<CryptoKeyPair>(KEY_STORAGE_KEY, key.getKeyPair());
  await storage.set(KEY_STORAGE_DELEGATION, JSON.stringify(chain.toJSON()));
  let earliest: bigint | null = null;
  for (const { delegation } of chain.delegations) {
    if (earliest === null || delegation.expiration < earliest) {
      earliest = delegation.expiration;
    }
  }
  if (earliest !== null) {
    localStorage.setItem(KEY_EXPIRATION, earliest.toString());
  }
}

async function clearSession(): Promise<void> {
  await storage.remove(KEY_STORAGE_KEY);
  await storage.remove(KEY_STORAGE_DELEGATION);
  localStorage.removeItem(KEY_EXPIRATION);
}

async function restoreSession(): Promise<DelegationIdentity | null> {
  const keyPair = await storage.get<CryptoKeyPair>(KEY_STORAGE_KEY);
  if (!keyPair) return null;
  const rawChain = await storage.get<string>(KEY_STORAGE_DELEGATION);
  if (!rawChain) return null;
  let chain: DelegationChain;
  try {
    chain = DelegationChain.fromJSON(rawChain);
  } catch {
    await clearSession();
    return null;
  }
  if (!isDelegationValid(chain)) {
    await clearSession();
    return null;
  }
  try {
    const key = await ECDSAKeyIdentity.fromKeyPair(keyPair);
    return DelegationIdentity.fromDelegation(key, chain);
  } catch {
    await clearSession();
    return null;
  }
}

export interface AuthContextValue {
  isAuthenticated: boolean;
  principal: string | null;
  role: Role | null;
  actor: Backend | null;
  login: () => Promise<void>;
  logout: () => Promise<void>;
  isLoading: boolean;
  noAccess: boolean;
}

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [isAuthenticated, setIsAuthenticated] = useState(false);
  const [principal, setPrincipal] = useState<string | null>(null);
  const [role, setRole] = useState<Role | null>(null);
  const [actor, setActor] = useState<Backend | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [noAccess, setNoAccess] = useState(false);

  async function applyIdentity(identity: DelegationIdentity) {
    const backend = await getActor(identity);
    const principalText = identity.getPrincipal().toText();
    const roleResult = await backend.getMyRole();

    if (roleResult === null) {
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
    if (!isSessionValid()) {
      setIsLoading(false);
      return;
    }
    restoreSession()
      .then((identity) => {
        if (identity) return applyIdentity(identity);
      })
      .catch((e: unknown) => console.error("Session restore failed:", e))
      .finally(() => setIsLoading(false));
    // applyIdentity only calls stable state setters — no deps needed
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function login() {
    setIsLoading(true);
    try {
      await signer.openChannel();
      const key = await ECDSAKeyIdentity.generate();
      const chain = await signer.requestDelegation({
        publicKey: key.getPublicKey(),
        maxTimeToLive: MAX_TTL,
      });
      await persistSession(key, chain);
      const identity = DelegationIdentity.fromDelegation(key, chain);
      await applyIdentity(identity);
    } finally {
      setIsLoading(false);
    }
  }

  async function logout() {
    await clearSession();
    await signer.closeChannel();
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
