interface Props {
  cycles: bigint;
  idleBurnPerDay: bigint;
  label: string;
}

const T = 1_000_000_000_000n;
const DISPLAY_MAX = 2n * T; // 2T cap — bar is full green above this

function zone(c: bigint): string {
  const pct = Math.min(100, (Number(c) / Number(DISPLAY_MAX)) * 100);
  if (pct > 33) return "var(--ok, #22c55e)";
  if (pct > 10) return "var(--warn, #f59e0b)";
  return "var(--danger, #ef4444)";
}

export default function CycleBalanceBar({ cycles, idleBurnPerDay, label }: Props) {
  const tCycles = Number(cycles) / Number(T);
  const daysEst = idleBurnPerDay > 0n
    ? Math.floor(Number(cycles) / Number(idleBurnPerDay))
    : null;

  const pct = Math.min(100, (Number(cycles) / Number(DISPLAY_MAX)) * 100);
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
