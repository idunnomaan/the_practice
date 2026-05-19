import { useState, useCallback } from "react";
import { useAuth } from "../auth/useAuth";
import type { AuditEntry } from "../backend/api/backend";

export function useAudit() {
  const { actor } = useAuth();
  const [entries, setEntries] = useState<AuditEntry[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [cursor, setCursor] = useState(0n);
  const [hasMore, setHasMore] = useState(true);

  const PAGE_SIZE = 50n;

  const loadFirst = useCallback(async () => {
    if (!actor) return;
    setLoading(true);
    setError(null);
    try {
      const result = await actor.readAuditEntries(0n, PAGE_SIZE);
      if (result.__kind__ === "err") { setError(result.err); return; }
      const batch = result.ok;
      setEntries(batch);
      setHasMore(batch.length === Number(PAGE_SIZE));
      if (batch.length > 0) setCursor(batch[batch.length - 1].id + 1n);
    } catch (e) {
      setError(String(e));
    } finally {
      setLoading(false);
    }
  }, [actor]);

  const loadMore = useCallback(async () => {
    if (!actor || !hasMore) return;
    setLoading(true);
    setError(null);
    try {
      const result = await actor.readAuditEntries(cursor, PAGE_SIZE);
      if (result.__kind__ === "err") { setError(result.err); return; }
      const batch = result.ok;
      setEntries((prev) => [...prev, ...batch]);
      setHasMore(batch.length === Number(PAGE_SIZE));
      if (batch.length > 0) setCursor(batch[batch.length - 1].id + 1n);
    } catch (e) {
      setError(String(e));
    } finally {
      setLoading(false);
    }
  }, [actor, cursor, hasMore]);

  return { entries, loading, error, hasMore, loadFirst, loadMore };
}
