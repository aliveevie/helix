import { useEffect, useMemo, useState } from "react";
import { useAccount, useSignTypedData } from "wagmi";
import {
  ADDR, DEMO_POOL_ID, EIP712_DOMAIN, EIP712_TYPES, hookAbi,
} from "@/lib/helix/config";
import { addIntent, type StoredIntent } from "@/lib/helix/storage";
import { publicClient } from "@/lib/helix/public-client";
import { hashTypedData, parseUnits } from "viem";
import { toast } from "sonner";
import { short } from "@/lib/helix/format";

export function CreateIntent({ onCreated }: { onCreated: () => void }) {
  const { address, isConnected } = useAccount();
  const { signTypedDataAsync, isPending } = useSignTypedData();

  const [maxDriftBps, setMaxDriftBps] = useState(2000);
  const [minDuration, setMinDuration] = useState(3600);
  const [maxSize, setMaxSize] = useState("1000");
  const [nonce, setNonce] = useState<string>("");
  const [busy, setBusy] = useState(false);
  const [lastSig, setLastSig] = useState<{ sig: string; digest: string } | null>(null);

  // Auto-pick nonce by scanning forward
  useEffect(() => {
    let cancelled = false;
    async function pickNonce() {
      if (!address) return;
      let n = BigInt(Math.floor(Date.now() / 1000));
      for (let i = 0; i < 8; i++) {
        const used = await publicClient.readContract({
          address: ADDR.hook, abi: hookAbi, functionName: "nonceUsed", args: [address, n],
        });
        if (!used) break;
        n += 1n;
      }
      if (!cancelled) setNonce(n.toString());
    }
    pickNonce();
    return () => { cancelled = true; };
  }, [address]);

  const deadline = useMemo(
    () => BigInt(Math.floor(Date.now() / 1000) + 7 * 24 * 3600).toString(),
    [],
  );

  async function sign() {
    if (!address || !nonce) return;
    setBusy(true);
    try {
      const message = {
        lp: address,
        pool: DEMO_POOL_ID,
        maxDriftBps: BigInt(maxDriftBps),
        minDuration: BigInt(minDuration),
        maxSize: parseUnits(maxSize, 18),
        repFloor: 0,
        nonce: BigInt(nonce),
        deadline: BigInt(deadline),
      } as const;

      const sig = await signTypedDataAsync({
        domain: EIP712_DOMAIN, types: EIP712_TYPES, primaryType: "Intent", message,
      });
      const digest = hashTypedData({
        domain: EIP712_DOMAIN, types: EIP712_TYPES, primaryType: "Intent", message,
      });

      const stored: StoredIntent = {
        id: `${address}-${nonce}`,
        intent: {
          lp: address, pool: DEMO_POOL_ID,
          maxDriftBps: String(maxDriftBps),
          minDuration: String(minDuration),
          maxSize: parseUnits(maxSize, 18).toString(),
          repFloor: 0, nonce, deadline,
        },
        signature: sig, digest, createdAt: Date.now(),
      };
      addIntent(stored);
      setLastSig({ sig, digest });
      toast.success("Intent signed", { description: "Added to mempool" });
      onCreated();
      // increment nonce
      setNonce((n) => (BigInt(n || "0") + 1n).toString());
    } catch (e: any) {
      toast.error("Signing failed", { description: e?.shortMessage ?? e?.message });
    } finally {
      setBusy(false);
    }
  }

  return (
    <section className="surface p-6">
      <h2 className="text-lg font-semibold">Create Intent</h2>
      <p className="text-sm text-[var(--color-muted-foreground)] mt-1">
        Sign an EIP-712 intent to join a matched basket. Pool fixed to the demo ETH/USDC pool.
      </p>

      <div className="mt-5 grid gap-4 md:grid-cols-2">
        <div>
          <label className="text-xs uppercase tracking-wider text-[var(--color-muted-foreground)]">Pool</label>
          <div className="input-base mt-1 truncate" title={DEMO_POOL_ID}>{short(DEMO_POOL_ID, 14, 10)}</div>
        </div>
        <div>
          <label className="text-xs uppercase tracking-wider text-[var(--color-muted-foreground)]">LP</label>
          <div className="input-base mt-1 truncate">{address ?? "— connect wallet —"}</div>
        </div>

        <div>
          <div className="flex items-center justify-between">
            <label className="text-xs uppercase tracking-wider text-[var(--color-muted-foreground)]">
              Max Drift (bps)
            </label>
            <span className="mono text-sm text-gradient">{maxDriftBps}</span>
          </div>
          <input
            type="range" min={500} max={5000} step={50}
            value={maxDriftBps}
            onChange={(e) => setMaxDriftBps(parseInt(e.target.value))}
            className="w-full mt-2 accent-[var(--color-cyan)]"
          />
        </div>

        <div>
          <label className="text-xs uppercase tracking-wider text-[var(--color-muted-foreground)]">Min Duration (sec)</label>
          <input
            type="number" min={60} className="input-base mt-1"
            value={minDuration} onChange={(e) => setMinDuration(parseInt(e.target.value || "0"))}
          />
        </div>

        <div>
          <label className="text-xs uppercase tracking-wider text-[var(--color-muted-foreground)]">Max Size (USDV, whole tokens)</label>
          <input
            className="input-base mt-1" value={maxSize}
            onChange={(e) => setMaxSize(e.target.value.replace(/[^0-9.]/g, ""))}
          />
        </div>

        <div>
          <label className="text-xs uppercase tracking-wider text-[var(--color-muted-foreground)]">Nonce (auto)</label>
          <input className="input-base mt-1" value={nonce} onChange={(e) => setNonce(e.target.value)} />
        </div>
      </div>

      <div className="mt-5 flex items-center gap-3">
        <button className="btn-primary mono" onClick={sign} disabled={!isConnected || busy || isPending || !nonce}>
          {busy || isPending ? "Signing…" : "Sign Intent"}
        </button>
        <span className="text-xs text-[var(--color-muted-foreground)]">
          deadline = now + 7d
        </span>
      </div>

      {lastSig && (
        <div className="mt-5 grid gap-3">
          <div>
            <div className="text-xs uppercase tracking-wider text-[var(--color-muted-foreground)]">Digest</div>
            <div className="input-base mono mt-1 break-all text-xs">{lastSig.digest}</div>
          </div>
          <div>
            <div className="text-xs uppercase tracking-wider text-[var(--color-muted-foreground)]">Signature</div>
            <div className="input-base mono mt-1 break-all text-xs">{lastSig.sig}</div>
          </div>
        </div>
      )}
    </section>
  );
}
