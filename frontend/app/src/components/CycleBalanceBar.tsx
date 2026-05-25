interface Props {
  cycles: bigint;
  idleBurnPerDay: bigint;
  label: string;
}

const T = 1_000_000_000_000n;

function zone(c: bigint): string {
  if (c >= 5n * T) return "var(--ok, #22c55e)";
  if (c >= T)      return "var(--warn, #f59e0b)";
  return "var(--danger, #ef4444)";
}

export default function CycleBalanceBar({ cycles, idleBurnPerDay, label }: Props) {
  const tCycles = Number(cycles) / Number(T);
  const daysEst = idleBurnPerDay > 0n
    ? Math.floor(Number(cycles) / Number(idleBurnPerDay))
    : null;

  // Bar fills proportional to a 10T "full" reference
  const pct = Math.min(100, (Number(cycles) / (Number(T) * 10)) * 100);
  const color = zone(cycles);

  return (
    <div style={{ marginBottom: 12 }}>
      <div style={{ display: "flex", justifyContent: "space-between", marginBottom: 4, fontSize: 13 }}>
        <span style={{ fontWeight: 500 }}>{label}</span>
        <span style={{ color: "var(--tx2)" }}>
          {tCycles.toFixed(2)}T cycles
          {daysEst !== null && ` · ~${daysEst} days at idle burn`}
        </span>
      </div>
      <div style={{ height: 8, background: "var(--bd)", borderRadius: 4, overflow: "hidden" }}>
        <div style={{ height: "100%", width: `${pct}%`, background: color, transition: "width .3s" }} />
      </div>
    </div>
  );
}
