import { useReadContract } from "wagmi";
import { ADDR, breakerAbi, BREAKER_LABEL, DEMO_POOL_ID } from "@/lib/helix/config";
import { fmtNum } from "@/lib/helix/format";

export function BreakerPill() {
  const stateQ = useReadContract({
    address: ADDR.breaker, abi: breakerAbi, functionName: "state", args: [DEMO_POOL_ID],
    query: { refetchInterval: 15_000 },
  });
  const volQ = useReadContract({
    address: ADDR.breaker, abi: breakerAbi, functionName: "volIndex", args: [DEMO_POOL_ID],
    query: { refetchInterval: 15_000 },
  });
  const s = typeof stateQ.data === "number" ? stateQ.data : Number(stateQ.data ?? 0);
  const label = BREAKER_LABEL[s] ?? "—";
  const color =
    s === 0 ? "bg-[var(--success)]" : s === 1 ? "bg-[var(--warning)]" : "bg-[var(--danger)]";
  const volPct = volQ.data !== undefined ? `${fmtNum(volQ.data as bigint, 18, 2)}%` : "—";
  return (
    <div className="chip mono">
      <span className={`h-2 w-2 rounded-full ${color}`} />
      Breaker · {label} · vol {volPct}
    </div>
  );
}
