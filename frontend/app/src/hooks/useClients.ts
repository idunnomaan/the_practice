import { useState, useCallback } from "react";
import { useAuth } from "../auth/useAuth";
import { ClientType, ClientStatus } from "../backend/api/backend";
import type { Client } from "../backend/api/backend";

export function useClients() {
  const { actor } = useAuth();
  const [clients, setClients] = useState<Client[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async (after = 0n, limit = 50n, includeInactive = false) => {
    if (!actor) return;
    setLoading(true);
    setError(null);
    try {
      setClients(await actor.listClients(after, limit, includeInactive));
    } catch (e) {
      setError(String(e));
    } finally {
      setLoading(false);
    }
  }, [actor]);

  const createClient = useCallback(async (
    name: string,
    clientType: ClientType,
    primaryEmail: string | null,
    primaryPhone: string | null,
    identifier: string | null,
    notes: string,
  ) => {
    if (!actor) return null;
    return actor.createClient(name, clientType, primaryEmail, primaryPhone, identifier, notes);
  }, [actor]);

  const updateClient = useCallback(async (
    id: bigint,
    name: string | null,
    clientType: ClientType | null,
    primaryEmail: string | null,
    primaryPhone: string | null,
    identifier: string | null,
    notes: string | null,
  ) => {
    if (!actor) return null;
    return actor.updateClient(id, name, clientType, primaryEmail, primaryPhone, identifier, notes);
  }, [actor]);

  const deactivateClient = useCallback(async (id: bigint) => {
    if (!actor) return null;
    return actor.deactivateClient(id);
  }, [actor]);

  const reactivateClient = useCallback(async (id: bigint) => {
    if (!actor) return null;
    return actor.reactivateClient(id);
  }, [actor]);

  const getClient = useCallback(async (id: bigint) => {
    if (!actor) return null;
    return actor.getClient(id);
  }, [actor]);

  return {
    clients, loading, error,
    load, createClient, updateClient, deactivateClient, reactivateClient, getClient,
    ClientType, ClientStatus,
  };
}
