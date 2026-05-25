import { useState } from "react";

interface Props {
  onConfirm: (newPrincipal: string) => Promise<void>;
  onCancel: () => void;
}

export default function TransferMasterDialog({ onConfirm, onCancel }: Props) {
  const [newPrincipal, setNewPrincipal] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const expectedSuffix = newPrincipal.trim().slice(-5);
  const canSubmit = newPrincipal.trim().length > 5
    && confirmation === expectedSuffix
    && !busy;

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!canSubmit) return;
    setError(null);
    setBusy(true);
    try {
      await onConfirm(newPrincipal.trim());
    } catch (err) {
      setError(String(err));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div style={{
      position: "fixed", inset: 0, background: "rgba(0,0,0,.5)",
      display: "flex", alignItems: "center", justifyContent: "center", zIndex: 100,
    }}>
      <div className="card" style={{ maxWidth: 480, width: "90%", padding: 24 }}>
        <div style={{ fontWeight: 600, fontSize: 16, marginBottom: 8 }}>
          Transfer Master Controller
        </div>
        <p style={{ fontSize: 13, color: "var(--tx2)", marginBottom: 16 }}>
          This transfers full control of the canister to a new principal. The new principal
          must already be a registered Partner. This action cannot be undone.
        </p>
        {error && <div style={{ color: "var(--danger, #ef4444)", fontSize: 13, marginBottom: 8 }}>{error}</div>}
        <form onSubmit={(e) => { void handleSubmit(e); }}>
          <label className="tp-label">New principal
            <input
              className="tp-input"
              value={newPrincipal}
              onChange={e => { setNewPrincipal(e.target.value); setConfirmation(""); }}
              placeholder="e.g. aaaaa-aa..."
              autoFocus
            />
          </label>
          {newPrincipal.trim().length > 5 && (
            <label className="tp-label" style={{ marginTop: 12 }}>
              Type the last 5 characters of the principal to confirm: <code>{expectedSuffix}</code>
              <input
                className="tp-input"
                value={confirmation}
                onChange={e => setConfirmation(e.target.value)}
                placeholder={expectedSuffix}
              />
            </label>
          )}
          <div style={{ display: "flex", gap: 8, marginTop: 16 }}>
            <button type="submit" className="btn btn-danger" disabled={!canSubmit}>
              {busy ? "Transferring…" : "Transfer control"}
            </button>
            <button type="button" className="btn btn-neutral" onClick={onCancel} disabled={busy}>
              Cancel
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
