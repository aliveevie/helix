import { useEffect, useState } from "react";
import { useAccount, useReadContract, useWriteContract } from "wagmi";
import { ADDR, hookAbi, registryAbi, STATUS_LABEL, PENDING_LABEL } from "@/lib/helix/config";
import { fmtNum, short, txUrl, addrUrl } from "@/lib/helix/format";
import type { Hex } from "viem";
import { toast } from "sonner";

function Countdown({ to }: { to: bigint }) {
  const [now, setNow] = useState(() => Math.floor(Date.now() / 1000));
  useEffect(() => {
    const t = setInterval(() => setNow(Math.floor(Date.now() / 1000)), 1000);
    return () => clearInterval(t);
  }, []);
  const diff = Number(to) - now;
  if (Number(to) === 0) return <span className="mono text-[var(--color-muted-foreground)]">—</span>;
  if (diff <= 0) return <span className="mono text-[var(--warning)]">ended</span>;
  const h = Math.floor(diff / 3600), m = Math.floor((diff % 3600) / 60), s = diff % 60;
  return <span className="mono">{h}h {m}m {s}s</span>;
}

function MemberRow({ matchId, lp }: { matchId: Hex; lp: string }) {
  const m = useReadContract({
    address: ADDR.registry, abi: registryAbi, functionName: "marginOf",
    args: [matchId, lp as Hex],
  });
  return (
    <div className="flex items-center justify-between rounded-md border border-[var(--color-border)] px-3 py-2">
      <a className="mono text-sm hover:text-[var(--color-cyan)]" href={addrUrl(lp)} target="_blank" rel="noreferrer">
        {short(lp)}
      </a>
      <div className="mono text-sm text-gradient">
        {m.data !== undefined ? fmtNum(m.data as bigint, 18, 4) : "…"} <span className="text-[var(--color-muted-foreground)]">USDV</span>
      </div>
    </div>
  );
}

export function Baskets({ initialMatchId }: { initialMatchId?: string }) {
  const [input, setInput] = useState(initialMatchId ?? "");
  const [queryId, setQueryId] = useState<Hex | undefined>(initialMatchId as Hex | undefined);
  const { isConnected } = useAccount();

  useEffect(() => {
    if (initialMatchId) {
      setInput(initialMatchId);
      setQueryId(initialMatchId as Hex);
    }
  }, [initialMatchId]);

  const m = useReadContract({
    address: ADDR.hook, abi: hookAbi, functionName: "getMatch",
    args: queryId ? [queryId] : undefined,
    query: { enabled: !!queryId, refetchInterval: 12_000 },
  });
  const entryWindowQ = useReadContract({
    address: ADDR.hook, abi: hookAbi, functionName: "entryWindow",
  });

  const data = m.data as
    | undefined
    | {
        pool: Hex; createdAt: bigint; epochEnd: bigint; minDuration: bigint;
        rho: number; requiredRatioBps: number; enteredCount: number;
        status: number; pending: number; lps: readonly string[]; keys: readonly Hex[]; sizes: readonly bigint[];
      };

  const { writeContractAsync, isPending } = useWriteContract();

  const now = Math.floor(Date.now() / 1000);
  const cancelable =
    !!data && data.status === 1 &&
    !!entryWindowQ.data &&
    now > Number(data.createdAt) + Number(entryWindowQ.data);

  async function cancel() {
    if (!queryId) return;
    try {
      const hash = await writeContractAsync({
        address: ADDR.hook, abi: hookAbi, functionName: "cancelMatch", args: [queryId],
      });
      toast.success("cancelMatch sent", {
        action: { label: "Etherscan", onClick: () => window.open(txUrl(hash), "_blank") },
      });
    } catch (e: any) {
      toast.error("cancel failed", { description: e?.shortMessage ?? e?.message });
    }
  }

  return (
    <section className="surface p-6">
      <h2 className="text-lg font-semibold">Baskets</h2>
      <p className="text-sm text-[var(--color-muted-foreground)] mt-1">
        Inspect a matched basket by its <span className="mono">matchId</span>.
      </p>

      <div className="mt-4 flex gap-2 flex-wrap">
        <input
          className="input-base flex-1 min-w-[260px]"
          placeholder="0x… matchId"
          value={input} onChange={(e) => setInput(e.target.value.trim())}
        />
        <button className="btn-ghost mono" onClick={() => setQueryId(input as Hex)} disabled={!input.startsWith("0x")}>
          Inspect
        </button>
      </div>

      {!queryId ? (
        <div className="mt-5 rounded-lg border border-dashed border-[var(--color-border)] p-6 text-sm text-[var(--color-muted-foreground)]">
          Submit a match above to auto-populate, or paste a matchId.
        </div>
      ) : m.isLoading ? (
        <div className="mt-5 text-sm text-[var(--color-muted-foreground)]">Loading…</div>
      ) : !data || data.status === 0 ? (
        <div className="mt-5 text-sm text-[var(--danger)]">No match found for that id.</div>
      ) : (
        <div className="mt-5 grid gap-4">
          <div className="grid sm:grid-cols-3 gap-3">
            <Stat label="Status" value={
              <span className={`mono ${
                data.status === 2 ? "text-[var(--success)]" :
                data.status === 1 ? "text-[var(--warning)]" :
                data.status === 4 ? "text-[var(--danger)]" : ""
              }`}>{STATUS_LABEL[data.status] ?? data.status}</span>
            }/>
            <Stat label="Pending" value={<span className="mono">{PENDING_LABEL[data.pending] ?? data.pending}</span>}/>
            <Stat label="Rho" value={<span className="mono text-gradient">{(data.rho / 100).toFixed(2)}%</span>}/>
            <Stat label="Entered / Total" value={<span className="mono">{data.enteredCount} / {data.lps.length}</span>}/>
            <Stat label="Required ratio" value={<span className="mono">{(data.requiredRatioBps / 100).toFixed(2)}%</span>}/>
            <Stat label="Epoch ends in" value={<Countdown to={data.epochEnd} />}/>
          </div>

          <div>
            <div className="text-xs uppercase tracking-wider text-[var(--color-muted-foreground)] mb-2">Members</div>
            <div className="grid gap-2">
              {data.lps.map((lp) => <MemberRow key={lp} matchId={queryId} lp={lp} />)}
            </div>
          </div>

          <div className="flex items-center gap-3 flex-wrap">
            <button
              className="btn-ghost mono"
              onClick={cancel}
              disabled={!isConnected || !cancelable || isPending}
              title={!cancelable ? "Only PENDING after entry window" : ""}
            >
              {isPending ? "Cancelling…" : "Cancel match"}
            </button>
            <span className="relative group">
              <button className="btn-ghost mono opacity-50 cursor-not-allowed" disabled>
                settle()
              </button>
              <span className="pointer-events-none absolute left-0 top-full mt-2 w-72 rounded-md border border-[var(--color-border)] bg-[var(--card)] p-2 text-xs text-[var(--color-muted-foreground)] opacity-0 group-hover:opacity-100 transition z-20">
                Settlement runs after epoch via the v4 PoolManager hook (afterAddLiquidity / afterRemoveLiquidity).
                Not callable from the browser in this mock deployment.
              </span>
            </span>
          </div>
        </div>
      )}
    </section>
  );
}

function Stat({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="rounded-lg border border-[var(--color-border)] p-3">
      <div className="text-[10px] uppercase tracking-wider text-[var(--color-muted-foreground)]">{label}</div>
      <div className="mt-1 text-base">{value}</div>
    </div>
  );
}
