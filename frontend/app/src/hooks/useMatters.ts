import { useState, useCallback } from "react";
import { Principal } from "@icp-sdk/core/principal";
import { useAuth } from "../auth/useAuth";
import { MatterStatus } from "../backend/api/backend";
import type { Matter } from "../backend/api/backend";

export function useMatters() {
  const { actor } = useAuth();
  const [matters, setMatters] = useState<Matter[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async (after = 0n, limit = 50n, statusFilter: MatterStatus | null = null) => {
    if (!actor) return;
    setLoading(true);
    setError(null);
    try {
      setMatters(await actor.listMatters(after, limit, statusFilter));
    } catch (e) {
      setError(String(e));
    } finally {
      setLoading(false);
    }
  }, [actor]);

  const loadByClient = useCallback(async (clientId: bigint, after = 0n, limit = 50n) => {
    if (!actor) return;
    setLoading(true);
    setError(null);
    try {
      setMatters(await actor.listMattersByClient(clientId, after, limit, null));
    } catch (e) {
      setError(String(e));
    } finally {
      setLoading(false);
    }
  }, [actor]);

  const createMatter = useCallback(async (
    title: string,
    matterType: string,
    clientId: bigint,
    assignedPartner: string | null,
    description: string,
  ) => {
    if (!actor) return null;
    const partner = assignedPartner ? Principal.fromText(assignedPartner) : null;
    return actor.createMatter(title, matterType, clientId, partner, description);
  }, [actor]);

  const updateMatter = useCallback(async (
    id: bigint,
    title: string | null,
    description: string | null,
  ) => {
    if (!actor) return null;
    // Pass { __kind__: "None" } for assignedPartner to leave it unchanged
    return actor.updateMatter(id, title, null, null, { __kind__: "None" }, description);
  }, [actor]);

  const getMatter = useCallback(async (id: bigint) => {
    if (!actor) return null;
    return actor.getMatter(id);
  }, [actor]);

  const closeMatter = useCallback(async (id: bigint) => {
    if (!actor) return null;
    return actor.closeMatter(id);
  }, [actor]);

  const putOnHold = useCallback(async (id: bigint) => {
    if (!actor) return null;
    return actor.putMatterOnHold(id);
  }, [actor]);

  const resumeMatter = useCallback(async (id: bigint) => {
    if (!actor) return null;
    return actor.resumeMatter(id);
  }, [actor]);

  const reopenMatter = useCallback(async (id: bigint) => {
    if (!actor) return null;
    return actor.reopenMatter(id);
  }, [actor]);

  const archiveMatter = useCallback(async (id: bigint) => {
    if (!actor) return null;
    return actor.archiveMatter(id);
  }, [actor]);

  return {
    matters, loading, error,
    load, loadByClient, createMatter, updateMatter, getMatter,
    closeMatter, putOnHold, resumeMatter, reopenMatter, archiveMatter,
    MatterStatus,
  };
}
