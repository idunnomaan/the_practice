import { useEffect, useState, useCallback } from "react";
import { Actor, HttpAgent } from "@icp-sdk/core/agent";
import { IDL } from "@icp-sdk/core/candid";
import { Principal } from "@icp-sdk/core/principal";
import { safeGetCanisterEnv } from "@icp-sdk/core/agent/canister-env";
import { useAuth } from "../auth/useAuth";
import type { TopUpRequestRecord } from "../backend/api/backend";
import PrincipalDisplay from "../components/PrincipalDisplay";
import StorageBar from "../components/StorageBar";
import CycleBalanceBar from "../components/CycleBalanceBar";
import TopUpRequestForm from "../components/TopUpRequestForm";
import TopUpRequestList from "../components/TopUpRequestList";
import TransferMasterDialog from "../components/TransferMasterDialog";
import ErrorMessage from "../components/ErrorMessage";
import LoadingSpinner from "../components/LoadingSpinner";

// Minimal inline IDL for the IC management canister — only the fields we consume.
const mgmtIDL = ({ IDL: I }: { IDL: typeof IDL }) =>
  I.Service({
    canister_status: I.Func(
      [I.Record({ canister_id: I.Principal })],
      [I.Record({
        cycles: I.Nat,
        idle_cycles_burned_per_day: I.Nat,
        memory_size: I.Nat,
      })],
      [],
    ),
  });

const canisterEnv = safeGetCanisterEnv();
const FRONTEND_CANISTER_ID = canisterEnv?.["PUBLIC_CANISTER_ID:frontend"] ?? "";

export default function AdminSettingsPage() {
  const { actor, principal, identity, isMasterController } = useAuth();

  const [masterPrincipal, setMasterPrincipal] = useState<string | null>(null);
  const [opsPrincipal, setOpsPrincipal] = useState<string | null>(null);
  const [storageBudget, setStorageBudget] = useState<bigint | null>(null);
  const [storageUsed, setStorageUsed] = useState<bigint | null>(null);
  const [backendCycles, setBackendCycles] = useState<bigint | null>(null);
  const [frontendCycles, setFrontendCycles] = useState<bigint | null>(null);
  const [frontendIdleBurn, setFrontendIdleBurn] = useState<bigint>(0n);
  const [topUpRequests, setTopUpRequests] = useState<TopUpRequestRecord[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Inline form state
  const [grantInput, setGrantInput] = useState("");
  const [grantBusy, setGrantBusy] = useState(false);
  const [grantError, setGrantError] = useState<string | null>(null);
  const [budgetInput, setBudgetInput] = useState("");
  const [budgetBusy, setBudgetBusy] = useState(false);
  const [budgetError, setBudgetError] = useState<string | null>(null);
  const [showTransfer, setShowTransfer] = useState(false);

  const isOps = !!(principal && opsPrincipal && principal === opsPrincipal);

  const loadAll = useCallback(async () => {
    if (!actor) return;
    setLoading(true);
    setError(null);
    try {
      const [master, ops, budget, used, cycles, requests] = await Promise.all([
        actor.getMasterController(),
        actor.getOperationsPrincipal(),
        actor.getStorageBudget(),
        actor.getStorageUsed(),
        actor.getCycleBalance(),
        actor.listTopUpRequests(null),
      ]);
      setMasterPrincipal(master.toText());
      setOpsPrincipal(ops ? ops.toText() : null);
      setStorageBudget(budget);
      setStorageUsed(used);
      setBackendCycles(cycles);
      setTopUpRequests(requests);

      // Fetch frontend canister cycles via IC management canister
      if (identity && FRONTEND_CANISTER_ID) {
        try {
          const agent = await HttpAgent.create({
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            identity: identity as any,
            host: window.location.origin,
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            rootKey: (canisterEnv as any)?.IC_ROOT_KEY,
          });
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          const mgmt = Actor.createActor(mgmtIDL as any, { agent, canisterId: "aaaaa-aa" });
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          const status = await (mgmt as any).canister_status({
            canister_id: Principal.fromText(FRONTEND_CANISTER_ID),
          }) as { cycles: bigint; idle_cycles_burned_per_day: bigint };
          setFrontendCycles(status.cycles);
          setFrontendIdleBurn(status.idle_cycles_burned_per_day);
        } catch {
          // Non-critical — master principal may not be an IC controller of frontend
          setFrontendCycles(null);
        }
      }
    } catch (e) {
      setError(String(e));
    } finally {
      setLoading(false);
    }
  }, [actor, identity]);

  useEffect(() => { void loadAll(); }, [loadAll]);

  async function handleGrantOps(e: React.FormEvent) {
    e.preventDefault();
    if (!actor || !grantInput.trim()) return;
    setGrantError(null);
    setGrantBusy(true);
    try {
      const result = await actor.grantOperations(Principal.fromText(grantInput.trim()));
      if (result.__kind__ === "err") { setGrantError(result.err); return; }
      setGrantInput("");
      void loadAll();
    } catch (err) {
      setGrantError(String(err));
    } finally {
      setGrantBusy(false);
    }
  }

  async function handleRevokeOps() {
    if (!actor) return;
    setGrantError(null);
    setGrantBusy(true);
    try {
      const result = await actor.revokeOperations();
      if (result.__kind__ === "err") { setGrantError(result.err); return; }
      void loadAll();
    } catch (err) {
      setGrantError(String(err));
    } finally {
      setGrantBusy(false);
    }
  }

  async function handleSetBudget(e: React.FormEvent) {
    e.preventDefault();
    if (!actor) return;
    const gb = parseFloat(budgetInput);
    if (isNaN(gb) || gb <= 0) { setBudgetError("Enter a positive number of GB."); return; }
    setBudgetError(null);
    setBudgetBusy(true);
    try {
      const bytes = BigInt(Math.round(gb * 1024 ** 3));
      const result = await actor.setStorageBudget(bytes);
      if (result.__kind__ === "err") { setBudgetError(result.err); return; }
      setBudgetInput("");
      void loadAll();
    } catch (err) {
      setBudgetError(String(err));
    } finally {
      setBudgetBusy(false);
    }
  }

  async function handleTransfer(newPrincipal: string) {
    if (!actor) return;
    const result = await actor.transferMasterController(Principal.fromText(newPrincipal));
    if (result.__kind__ === "err") throw new Error(result.err);
    setShowTransfer(false);
    void loadAll();
  }

  async function handleCreateTopUp(amountT: bigint, note: string) {
    if (!actor) return;
    const result = await actor.createTopUpRequest(amountT, note);
    if (result.__kind__ === "err") throw new Error(result.err);
    void loadAll();
  }

  async function handleFulfill(id: bigint) {
    if (!actor) return;
    const result = await actor.fulfillTopUpRequest(id);
    if (result.__kind__ === "err") throw new Error(result.err);
  }

  async function handleCancel(id: bigint) {
    if (!actor) return;
    const result = await actor.cancelTopUpRequest(id);
    if (result.__kind__ === "err") throw new Error(result.err);
  }

  if (!isMasterController) {
    return (
      <div>
        <div className="page-header"><div className="page-title">Admin Settings</div></div>
        <div style={{ color: "var(--tx2)", fontSize: 14 }}>Access restricted to master controller.</div>
      </div>
    );
  }

  return (
    <div>
      <div className="page-header"><div className="page-title">Admin Settings</div></div>

      {showTransfer && (
        <TransferMasterDialog
          onConfirm={handleTransfer}
          onCancel={() => setShowTransfer(false)}
        />
      )}

      {error && <ErrorMessage message={error} onDismiss={() => setError(null)} />}
      {loading && <LoadingSpinner />}

      {/* ── Identity ─────────────────────────────────────────────────────── */}
      <div className="card" style={{ marginBottom: 16, padding: 16 }}>
        <div className="section-head">Identity</div>

        <div style={{ marginBottom: 12 }}>
          <div style={{ fontSize: 13, fontWeight: 500, marginBottom: 4 }}>Master controller</div>
          {masterPrincipal && <PrincipalDisplay principal={masterPrincipal} />}
        </div>

        <div style={{ marginBottom: 12 }}>
          <div style={{ fontSize: 13, fontWeight: 500, marginBottom: 4 }}>Operations principal</div>
          {opsPrincipal
            ? <PrincipalDisplay principal={opsPrincipal} />
            : <span style={{ color: "var(--tx2)", fontSize: 13 }}>Not set</span>
          }
        </div>

        {grantError && <ErrorMessage message={grantError} onDismiss={() => setGrantError(null)} />}
        <form onSubmit={(e) => { void handleGrantOps(e); }}
          style={{ display: "flex", gap: 8, alignItems: "flex-end", marginBottom: 8 }}>
          <label className="tp-label"
            style={{ flex: "0 0 70%", marginBottom: 0, textTransform: "none", letterSpacing: 0, fontSize: 13, color: "var(--tx)" }}>
            Grant operations principal
            <input
              className="tp-input"
              value={grantInput}
              onChange={e => setGrantInput(e.target.value)}
              placeholder="Principal text"
              disabled={grantBusy}
            />
          </label>
          <button type="submit" className="btn btn-primary btn-sm" disabled={grantBusy || !grantInput.trim()}>
            {grantBusy ? "…" : "Grant"}
          </button>
          {opsPrincipal && (
            <button type="button" className="btn btn-danger btn-sm" disabled={grantBusy}
              onClick={() => { void handleRevokeOps(); }}>
              Revoke
            </button>
          )}
        </form>

        {/* Danger Zone */}
        <div style={{
          marginTop: 20,
          borderTop: "0.5px solid var(--bd)",
          paddingTop: 14,
        }}>
          <div style={{ fontSize: 11, fontWeight: 600, color: "var(--danger, #ef4444)", textTransform: "uppercase", letterSpacing: "0.05em", marginBottom: 8 }}>
            Danger zone
          </div>
          <p style={{ fontSize: 12, color: "var(--tx2)", margin: "0 0 10px" }}>
            Irreversible. Transfers all master controller authority to a new principal.
          </p>
          <button className="btn btn-danger btn-sm"
            style={{ border: "1px solid var(--danger, #ef4444)", background: "transparent", color: "var(--danger, #ef4444)" }}
            onClick={() => setShowTransfer(true)}>
            Transfer master controller…
          </button>
        </div>
      </div>

      {/* ── Storage ──────────────────────────────────────────────────────── */}
      <div className="card" style={{ marginBottom: 16, padding: 16 }}>
        <div className="section-head">Storage</div>
        {storageUsed !== null && storageBudget !== null && storageBudget > 0n && (
          <StorageBar usedBytes={storageUsed} limitBytes={storageBudget} label="Canister storage" />
        )}
        {budgetError && <ErrorMessage message={budgetError} onDismiss={() => setBudgetError(null)} />}
        <form onSubmit={(e) => { void handleSetBudget(e); }}
          style={{ display: "flex", gap: 8, alignItems: "flex-end", marginTop: 8 }}>
          <label className="tp-label"
            style={{ flex: "0 0 180px", marginBottom: 0, textTransform: "none", letterSpacing: 0, fontSize: 13, color: "var(--tx)" }}>
            Set budget (GB)
            <input
              className="tp-input"
              type="number"
              min={1}
              step={1}
              value={budgetInput}
              onChange={e => setBudgetInput(e.target.value)}
              placeholder={storageBudget !== null
                ? `Current: ${(Number(storageBudget) / 1024 ** 3).toFixed(0)} GB`
                : ""}
              disabled={budgetBusy}
            />
          </label>
          <button type="submit" className="btn btn-primary btn-sm" disabled={budgetBusy || !budgetInput}>
            {budgetBusy ? "…" : "Update"}
          </button>
        </form>
      </div>

      {/* ── Cycles ───────────────────────────────────────────────────────── */}
      <div className="card" style={{ marginBottom: 16, padding: 16 }}>
        <div className="section-head">Cycle balances</div>
        {backendCycles !== null && (
          <CycleBalanceBar cycles={backendCycles} idleBurnPerDay={0n} label="Backend canister" />
        )}
        {frontendCycles !== null
          ? <CycleBalanceBar cycles={frontendCycles} idleBurnPerDay={frontendIdleBurn} label="Frontend canister" />
          : FRONTEND_CANISTER_ID
            ? <div style={{ display: "flex", alignItems: "center", gap: 6, fontSize: 12, color: "var(--tx2)", marginTop: 4 }}>
                <i className="ti ti-info-circle" style={{ fontSize: 14, flexShrink: 0 }} />
                Frontend balance unavailable — master principal must be an IC controller of the frontend canister.
              </div>
            : null
        }
      </div>

      {/* ── Top-up requests ──────────────────────────────────────────────── */}
      <div className="card" style={{ marginBottom: 16, padding: 16 }}>
        <div className="section-head">Cycle top-up requests</div>
        <div style={{ marginBottom: 16 }}>
          <TopUpRequestForm onSubmit={handleCreateTopUp} />
        </div>
        <TopUpRequestList
          requests={topUpRequests}
          isOps={isOps}
          isMaster={isMasterController}
          onFulfill={handleFulfill}
          onCancel={handleCancel}
          onRefresh={() => { void loadAll(); }}
        />
      </div>
    </div>
  );
}
