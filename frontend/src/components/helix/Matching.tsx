import { useEffect, useState } from "react";
import { useAccount, useWriteContract } from "wagmi";
import {
  ADDR, DEMO_POOL_ID, EIP712_DOMAIN, EIP712_TYPES, hookAbi,
} from "@/lib/helix/config";
import { addIntent, loadIntents, removeIntent, type StoredIntent } from "@/lib/helix/storage";
import { publicClient } from "@/lib/helix/public-client";
import { decodeEventLog, hashTypedData, parseUnits } from "viem";
import { generatePrivateKey, privateKeyToAccount } from "viem/accounts";
import { toast } from "sonner";
import { short, txUrl, addrUrl } from "@/lib/helix/format";

export function Matching({
  intents, onChange, onMatched,
}: { intents: StoredIntent[]; onChange: () => void; onMatched: (id: string) => void }) {
  const { isConnected } = useAccount();
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const { writeContractAsync, isPending } = useWriteContract();
  const [genBusy, setGenBusy] = useState(false);

  useEffect(() => {
    // drop selections that no longer exist
    setSelected((prev) => new Set([...prev].filter((id) => intents.some((i) => i.id === id))));
  }, [intents]);

  const selectedIntents = intents.filter((i) => selected.has(i.id));
  const distinctLps = new Set(selectedIntents.map((i) => i.intent.lp.toLowerCase()));
  const canSubmit = selectedIntents.length >= 2 && distinctLps.size === selectedIntents.length;

  function toggle(id: string) {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id); else next.add(id);
      return next;
    });
  }

  async function generateCounterparty() {
    setGenBusy(true);
    try {
      const pk = generatePrivateKey();
      const acct = privateKeyToAccount(pk);
      // pick a nonce
      let n = BigInt(Math.floor(Date.now() / 1000));
      for (let i = 0; i < 5; i++) {
        const used = await publicClient.readContract({
          address: ADDR.hook, abi: hookAbi, functionName: "nonceUsed", args: [acct.address, n],
        });
        if (!used) break;
        n += 1n;
      }
      const message = {
        lp: acct.address,
        pool: DEMO_POOL_ID,
        maxDriftBps: 2000n,
        minDuration: 3600n,
        maxSize: parseUnits("1000", 18),
        repFloor: 0,
        nonce: n,
        deadline: BigInt(Math.floor(Date.now() / 1000) + 7 * 24 * 3600),
      } as const;
      const sig = await acct.signTypedData({
        domain: EIP712_DOMAIN, types: EIP712_TYPES, primaryType: "Intent", message,
      });
      const digest = hashTypedData({
        domain: EIP712_DOMAIN, types: EIP712_TYPES, primaryType: "Intent", message,
      });
      addIntent({
        id: `${acct.address}-${n.toString()}`,
        intent: {
          lp: acct.address, pool: DEMO_POOL_ID,
          maxDriftBps: "2000", minDuration: "3600",
          maxSize: parseUnits("1000", 18).toString(), repFloor: 0,
          nonce: n.toString(),
          deadline: message.deadline.toString(),
        },
        signature: sig, digest, ephemeralKey: pk, createdAt: Date.now(),
      });
      toast.success("Counterparty generated", { description: short(acct.address) });
      onChange();
    } catch (e: any) {
      toast.error("Generation failed", { description: e?.shortMessage ?? e?.message });
    } finally {
      setGenBusy(false);
    }
  }

  async function submitMatch() {
    if (!canSubmit) return;
    try {
      const intentsArg = selectedIntents.map((i) => ({
        lp: i.intent.lp,
        pool: i.intent.pool,
        maxDriftBps: BigInt(i.intent.maxDriftBps),
        minDuration: BigInt(i.intent.minDuration),
        maxSize: BigInt(i.intent.maxSize),
        repFloor: i.intent.repFloor,
        nonce: BigInt(i.intent.nonce),
        deadline: BigInt(i.intent.deadline),
      }));
      const sigs = selectedIntents.map((i) => i.signature);

      const hash = await writeContractAsync({
        address: ADDR.hook, abi: hookAbi, functionName: "submitMatch",
        args: [intentsArg as any, sigs as any],
      });
      toast.success("submitMatch sent", {
        description: "Waiting for confirmation…",
        action: { label: "Etherscan", onClick: () => window.open(txUrl(hash), "_blank") },
      });
      const receipt = await publicClient.waitForTransactionReceipt({ hash });

      let matchId: string | undefined;
      for (const log of receipt.logs) {
        try {
          const ev = decodeEventLog({ abi: hookAbi, data: log.data, topics: log.topics });
          if (ev.eventName === "MatchSubmitted") {
            matchId = (ev.args as any).matchId as string;
            break;
          }
        } catch { /* not our event */ }
      }
      if (matchId) {
        toast.success("Match created", {
          description: matchId,
          action: { label: "Inspect", onClick: () => onMatched(matchId!) },
        });
        onMatched(matchId);
        // remove used intents
        selectedIntents.forEach((i) => removeIntent(i.id));
        setSelected(new Set());
        onChange();
      } else {
        toast("Tx confirmed but no MatchSubmitted event decoded");
      }
    } catch (e: any) {
      toast.error("submitMatch failed", { description: e?.shortMessage ?? e?.message });
    }
  }

  return (
    <section className="surface p-6">
      <div className="flex items-start justify-between gap-3 flex-wrap">
        <div>
          <h2 className="text-lg font-semibold">Matching</h2>
          <p className="text-sm text-[var(--color-muted-foreground)] mt-1">
            Select ≥2 signed intents from distinct LPs and submit on-chain.
          </p>
        </div>
        <div className="flex gap-2">
          <button className="btn-ghost mono" onClick={generateCounterparty} disabled={genBusy}>
            {genBusy ? "Generating…" : "+ Generate counterparty"}
          </button>
          <button className="btn-primary mono" onClick={submitMatch} disabled={!isConnected || !canSubmit || isPending}>
            {isPending ? "Submitting…" : `submitMatch (${selectedIntents.length})`}
          </button>
        </div>
      </div>

      <div className="mt-5">
        {intents.length === 0 ? (
          <div className="rounded-lg border border-dashed border-[var(--color-border)] p-8 text-center text-sm text-[var(--color-muted-foreground)]">
            No intents in the mempool yet. Sign one above, or generate a counterparty.
          </div>
        ) : (
          <ul className="grid gap-2">
            {intents.map((i) => {
              const isSel = selected.has(i.id);
              return (
                <li
                  key={i.id}
                  className={`flex items-center justify-between gap-3 rounded-lg border px-4 py-3 cursor-pointer transition ${
                    isSel ? "border-[var(--color-cyan)] glow-ring" : "border-[var(--color-border)] hover:border-white/20"
                  }`}
                  onClick={() => toggle(i.id)}
                >
                  <div className="flex items-center gap-3 min-w-0">
                    <input type="checkbox" readOnly checked={isSel} className="accent-[var(--color-cyan)]" />
                    <div className="min-w-0">
                      <div className="mono text-sm">
                        <a className="hover:text-[var(--color-cyan)]"
                          href={addrUrl(i.intent.lp)} target="_blank" rel="noreferrer"
                          onClick={(e) => e.stopPropagation()}>
                          {short(i.intent.lp)}
                        </a>
                        {i.ephemeralKey && (
                          <span className="ml-2 chip mono text-[10px]">ephemeral</span>
                        )}
                      </div>
                      <div className="text-xs text-[var(--color-muted-foreground)] mono">
                        nonce {i.intent.nonce} · drift {i.intent.maxDriftBps}bps · size {(BigInt(i.intent.maxSize) / 10n ** 18n).toString()}
                      </div>
                    </div>
                  </div>
                  <button
                    className="text-xs text-[var(--color-muted-foreground)] hover:text-[var(--danger)]"
                    onClick={(e) => { e.stopPropagation(); removeIntent(i.id); onChange(); }}
                  >
                    remove
                  </button>
                </li>
              );
            })}
          </ul>
        )}
      </div>
    </section>
  );
}
