import { useState, useCallback } from "react";
import { Principal } from "@icp-sdk/core/principal";
import { useAuth } from "../auth/useAuth";
import { Role } from "../backend/api/backend";
import type { UserRecord } from "../backend/api/backend";

export function useUsers() {
  const { actor } = useAuth();
  const [users, setUsers] = useState<Array<[Principal, UserRecord]>>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!actor) return;
    setLoading(true);
    setError(null);
    try {
      setUsers(await actor.listUsers());
    } catch (e) {
      setError(String(e));
    } finally {
      setLoading(false);
    }
  }, [actor]);

  const addUser = useCallback(async (principalText: string, role: Role) => {
    if (!actor) return null;
    const p = Principal.fromText(principalText);
    return actor.addUser(p, role);
  }, [actor]);

  const suspendUser = useCallback(async (p: Principal) => {
    if (!actor) return null;
    return actor.suspendUser(p);
  }, [actor]);

  const unsuspendUser = useCallback(async (p: Principal) => {
    if (!actor) return null;
    return actor.unsuspendUser(p);
  }, [actor]);

  const setUserRole = useCallback(async (p: Principal, role: Role) => {
    if (!actor) return null;
    return actor.setUserRole(p, role);
  }, [actor]);

  return {
    users, loading, error,
    load, addUser, suspendUser, unsuspendUser, setUserRole,
    Role,
  };
}
