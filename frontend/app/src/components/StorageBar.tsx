interface Props {
  usedBytes: bigint;
  limitBytes: bigint;
  label: string;
}

function formatBytes(b: bigint) {
  const n = Number(b);
  if (n >= 1024 ** 3) return `${(n / 1024 ** 3).toFixed(2)} GB`;
  if (n >= 1024 ** 2) return `${(n / 1024 ** 2).toFixed(1)} MB`;
  if (n >= 1024) return `${(n / 1024).toFixed(1)} KB`;
  return `${n} B`;
}

export default function StorageBar({ usedBytes, limitBytes, label }: Props) {
  const pct = limitBytes > 0n ? Math.min(100, Number(usedBytes * 100n / limitBytes)) : 0;
  const color = pct >= 90 ? "var(--danger, #ef4444)"
    : pct >= 70 ? "var(--warn, #f59e0b)"
    : "var(--ok, #22c55e)";

  return (
    <div style={{ marginBottom: 12 }}>
      <div style={{ display: "flex", justifyContent: "space-between", marginBottom: 4, fontSize: 13 }}>
        <span style={{ fontWeight: 500 }}>{label}</span>
        <span style={{ color: "var(--tx2)" }}>
          {formatBytes(usedBytes)} / {formatBytes(limitBytes)} ({pct}%)
        </span>
      </div>
      <div style={{ height: 8, background: "var(--bd)", borderRadius: 4, overflow: "hidden" }}>
        <div style={{ height: "100%", width: `${pct}%`, background: color, transition: "width .3s" }} />
      </div>
    </div>
  );
}
