import { useState } from "react";

interface Props {
  onSubmit: (amountT: bigint, note: string) => Promise<void>;
}

export default function TopUpRequestForm({ onSubmit }: Props) {
  const [amountT, setAmountT] = useState("10");
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState(false);

  const amount = parseInt(amountT, 10);
  const canSubmit = !busy && !isNaN(amount) && amount >= 1 && amount <= 100 && note.length <= 1024;

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!canSubmit) return;
    setError(null);
    setSuccess(false);
    setBusy(true);
    try {
      await onSubmit(BigInt(amount), note);
      setSuccess(true);
      setAmountT("10");
      setNote("");
      setTimeout(() => setSuccess(false), 3000);
    } catch (err) {
      setError(String(err));
    } finally {
      setBusy(false);
    }
  }

  return (
    <form onSubmit={(e) => { void handleSubmit(e); }}>
      {error && <div style={{ color: "var(--danger, #ef4444)", fontSize: 13, marginBottom: 8 }}>{error}</div>}
      {success && <div style={{ color: "var(--ok, #22c55e)", fontSize: 13, marginBottom: 8 }}>Request submitted.</div>}
      <div style={{ display: "flex", gap: 8, alignItems: "flex-end", flexWrap: "wrap" }}>
        <label className="tp-label" style={{ flex: "0 0 140px", marginBottom: 0, textTransform: "none", letterSpacing: 0 }}>
          Amount (T cycles)
          <input
            className="tp-input"
            type="number"
            min={1}
            max={100}
            value={amountT}
            onChange={e => setAmountT(e.target.value)}
            style={{ width: "100%" }}
          />
        </label>
        <label className="tp-label" style={{ flex: 1, minWidth: 160, marginBottom: 0, textTransform: "none", letterSpacing: 0 }}>
          Note (optional, max 1024 chars)
          <input
            className="tp-input"
            value={note}
            onChange={e => setNote(e.target.value)}
            placeholder="Reason for top-up"
            maxLength={1024}
          />
        </label>
        <button type="submit" className="btn btn-primary" disabled={!canSubmit} style={{ flexShrink: 0 }}>
          {busy ? "Submitting…" : "Request top-up"}
        </button>
      </div>
    </form>
  );
}
