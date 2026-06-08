import { useMemo, useState } from "react";
import type { Hex } from "viem";
import { keccak256, toHex } from "viem";
import { DEMO_POOLS } from "../config";
import { bpsToPct, formatToken, formatTimestamp, safeStringify, short } from "../lib/format";
import { useStore } from "../lib/store";
import { useHelix } from "../lib/useHelix";
import type { KnownBasket, SignedIntent } from "../lib/types";
import { Card, Empty, Notice, Tag } from "./ui";

function poolLabel(id: Hex): string {
  return DEMO_POOLS.find((p) => p.id.toLowerCase() === id.toLowerCase())?.label ?? short(id, 8, 6);
}

/** Group intents by pool — only same-pool intents are matchable into a basket. */
function compatible(selected: SignedIntent[]): { ok: boolean; reason?: string } {
  if (selected.length < 2) return { ok: false, reason: "Select at least 2 intents." };
  const pools = new Set(selected.map((s) => s.intent.pool.toLowerCase()));
  if (pools.size > 1) return { ok: false, reason: "All intents in a basket must share one pool." };
  return { ok: true };
}

export function MempoolPanel() {
  const store = useStore();
  const helix = useHelix();
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [info, setInfo] = useState<string | null>(null);

  const selected = useMemo(
    () => store.intents.filter((i) => selectedIds.has(i.id)),
    [store.intents, selectedIds],
  );
  const compat = useMemo(() => compatible(selected), [selected]);

  function toggle(id: string) {
    setSelectedIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  const canSubmitOnChain =
    helix.live && helix.hasWallet && helix.rightChain && selected.every((s) => !s.mock);

  async function formBasket() {
    setError(null);
    setInfo(null);
    if (!compat.ok) {
      setError(compat.reason ?? "Incompatible selection.");
      return;
    }
    setBusy(true);
    try {
      const intents = selected.map((s) => s.intent);
      const signatures = selected.map((s) => s.signature);

      if (canSubmitOnChain && helix.client) {
        const tx = await helix.client.submitMatch(intents, signatures);
        const basket: KnownBasket = {
          // we don't know the on-chain matchId until the event; use tx as a stand-in key
          matchId: tx,
          intentIds: selected.map((s) => s.id),
          submitTx: tx,
          createdAt: Date.now(),
          mock: false,
          label: `${poolLabel(selected[0]!.intent.pool)} · ${selected.length} LPs`,
        };
        store.addBasket(basket);
        setInfo(`submitMatch sent · tx ${short(tx, 10, 8)}. Track it in Baskets.`);
      } else {
        // Simulate — derive a deterministic pseudo matchId so the basket is loadable.
        const pseudoId = keccak256(
          toHex(selected.map((s) => s.digest).join("|") + Date.now()),
        ) as Hex;
        const basket: KnownBasket = {
          matchId: pseudoId,
          intentIds: selected.map((s) => s.id),
          createdAt: Date.now(),
          mock: true,
          label: `${poolLabel(selected[0]!.intent.pool)} · ${selected.length} LPs (sim)`,
        };
        store.addBasket(basket);
        setInfo(
          `Simulated basket formed (no on-chain submit). Pseudo matchId ${short(pseudoId, 10, 8)} added to Baskets.`,
        );
      }
      setSelectedIds(new Set());
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setBusy(false);
    }
  }

  const submitPreview = useMemo(() => {
    if (selected.length === 0) return null;
    return {
      intents: selected.map((s) => s.intent),
      signatures: selected.map((s) => short(s.signature, 10, 8)),
    };
  }, [selected]);

  return (
    <Card
      title="Intent Mempool · Matching"
      subtitle="Permissionless matching: select compatible intents and form a basket."
      actions={
        store.intents.length > 0 ? (
          <button
            className="btn ghost sm"
            onClick={() => {
              store.clearIntents();
              setSelectedIds(new Set());
            }}
          >
            Clear all
          </button>
        ) : undefined
      }
    >
      {store.intents.length === 0 ? (
        <Empty>No signed intents yet. Create one in the Create Intent panel.</Empty>
      ) : (
        <div className="list">
          {store.intents.map((it) => {
            const on = selectedIds.has(it.id);
            return (
              <div
                key={it.id}
                className={on ? "row selected" : "row"}
                onClick={() => toggle(it.id)}
                style={{ cursor: "pointer" }}
              >
                <div className={on ? "checkbox on" : "checkbox"} />
                <div className="grow">
                  <div className="row-title">
                    {poolLabel(it.intent.pool)}{" "}
                    {it.mock ? <Tag color="violet">mock</Tag> : <Tag color="cyan">signed</Tag>}
                  </div>
                  <div className="row-sub">
                    LP <span className="mono">{short(it.signer)}</span> · drift{" "}
                    {bpsToPct(it.intent.maxDriftBps)} · size{" "}
                    {formatToken(it.intent.maxSize)} · nonce{" "}
                    <span className="mono">{it.intent.nonce.toString()}</span> · deadline{" "}
                    {formatTimestamp(it.intent.deadline)}
                  </div>
                </div>
                <button
                  className="btn ghost sm"
                  onClick={(e) => {
                    e.stopPropagation();
                    store.removeIntent(it.id);
                    setSelectedIds((prev) => {
                      const n = new Set(prev);
                      n.delete(it.id);
                      return n;
                    });
                  }}
                >
                  Remove
                </button>
              </div>
            );
          })}
        </div>
      )}

      <hr className="divider" />

      <div className="inline-actions" style={{ justifyContent: "space-between" }}>
        <div className="muted">
          {selected.length} selected
          {selected.length > 0 &&
            (compat.ok ? (
              <>
                {" "}
                · <Tag color="green">compatible</Tag>
              </>
            ) : (
              <>
                {" "}
                · <span className="faint">{compat.reason}</span>
              </>
            ))}
        </div>
        <button
          className="btn primary"
          disabled={busy || !compat.ok}
          onClick={formBasket}
          title={canSubmitOnChain ? "submitMatch on-chain" : "Simulate basket formation"}
        >
          {busy ? "Submitting…" : canSubmitOnChain ? "Form Basket & Submit" : "Form Basket (simulate)"}
        </button>
      </div>

      {!canSubmitOnChain && selected.length >= 2 && compat.ok && (
        <Notice kind="mock">
          {!helix.live
            ? "Mock mode (contracts not configured) — this will simulate the submission."
            : !helix.hasWallet
              ? "Connect a wallet to submit on-chain."
              : !helix.rightChain
                ? "Switch to the target chain to submit on-chain."
                : "Selection contains mock-signed intents — only a simulated basket can be formed."}
        </Notice>
      )}

      {error && <Notice kind="err">⚠ {error}</Notice>}
      {info && <Notice kind="ok">{info}</Notice>}

      {submitPreview && (
        <details style={{ marginTop: 14 }}>
          <summary className="muted" style={{ cursor: "pointer" }}>
            Preview submitMatch payload
          </summary>
          <pre className="code">{safeStringify(submitPreview)}</pre>
        </details>
      )}
    </Card>
  );
}
