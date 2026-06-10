import { useState } from "react";
import { useAccount, useReadContract } from "wagmi";
import { ADDR, reputationAbi } from "@/lib/helix/config";
import type { Address } from "viem";

export function Reputation() {
  const { address } = useAccount();
  const [input, setInput] = useState<string>("");
  const target = (input.startsWith("0x") && input.length === 42 ? input : address) as Address | undefined;

  const q = useReadContract({
    address: ADDR.reputation, abi: reputationAbi, functionName: "scoreOf",
    args: target ? [target] : undefined,
    query: { enabled: !!target },
  });

  const score = typeof q.data === "number" ? q.data : Number(q.data ?? 0);
  const pct = Math.max(0, Math.min(100, (score / 10000) * 100));

  return (
    <section className="surface p-6">
      <h2 className="text-lg font-semibold">Reputation</h2>
      <p className="text-sm text-[var(--color-muted-foreground)] mt-1">
        ERC-8004 reputation score (0–10,000).
      </p>

      <div className="mt-4 flex gap-2 flex-wrap">
        <input
          className="input-base flex-1 min-w-[260px]"
          placeholder={address ?? "0x… address"}
          value={input} onChange={(e) => setInput(e.target.value.trim())}
        />
      </div>

      <div className="mt-5">
        <div className="flex items-baseline justify-between">
          <div className="text-xs uppercase tracking-wider text-[var(--color-muted-foreground)]">Score</div>
          <div className="mono text-3xl text-gradient">{target ? score : "—"}</div>
        </div>
        <div className="mt-2 h-3 w-full rounded-full bg-[var(--input)] overflow-hidden border border-[var(--color-border)]">
          <div
            className="h-full rounded-full"
            style={{
              width: `${pct}%`,
              background: "var(--gradient-accent)",
              boxShadow: "var(--glow-cyan)",
            }}
          />
        </div>
        <div className="mt-1 flex justify-between text-[10px] text-[var(--color-muted-foreground)] mono">
          <span>0</span><span>5000</span><span>10000</span>
        </div>
      </div>
    </section>
  );
}
