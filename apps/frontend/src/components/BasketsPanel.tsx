import { MatchStatus, RebalanceAction } from "@helix/sdk";
import { useCallback, useEffect, useState } from "react";
import type { Address, Hex } from "viem";
import { DEMO_POOLS } from "../config";
import {
  bpsToPct,
  formatTimestamp,
  formatToken,
  secondsUntil,
  formatDuration,
  short,
} from "../lib/format";
import { mockMatch } from "../lib/mock";
import { useStore } from "../lib/store";
import type { DecodedMatch, KnownBasket } from "../lib/types";
import { useHelix } from "../lib/useHelix";
import { Card, Empty, Notice, Tag } from "./ui";

const STATUS_LABEL: Record<number, string> = {
  [MatchStatus.NONE]: "NONE",
  [MatchStatus.PENDING]: "PENDING",
  [MatchStatus.OPEN]: "OPEN",
  [MatchStatus.SETTLED]: "SETTLED",
};
const STATUS_COLOR: Record<number, "dim" | "cyan" | "green" | "amber"> = {
  [MatchStatus.NONE]: "dim",
  [MatchStatus.PENDING]: "amber",
  [MatchStatus.OPEN]: "cyan",
  [MatchStatus.SETTLED]: "green",
};
const ACTION_LABEL: Record<number, string> = {
  [RebalanceAction.NONE]: "none",
  [RebalanceAction.RE_MATCH]: "re-match",
  [RebalanceAction.PAUSE]: "pause",
  [RebalanceAction.RESUME]: "resume",
};

function poolLabel(id: string): string {
  return DEMO_POOLS.find((p) => p.id.toLowerCase() === id.toLowerCase())?.label ?? short(id, 8, 6);
}

/** Coerce the SDK's `unknown` getMatch return (a struct tuple) into DecodedMatch. */
function decodeMatch(raw: unknown): DecodedMatch | null {
  if (!raw || typeof raw !== "object") return null;
  const m = raw as Record<string, unknown>;
  try {
    return {
      pool: m.pool as Hex,
      epochEnd: BigInt(m.epochEnd as bigint | number),
      minDuration: BigInt(m.minDuration as bigint | number),
      rho: Number(m.rho),
      requiredRatioBps: Number(m.requiredRatioBps),
      enteredCount: Number(m.enteredCount),
      status: Number(m.status),
      pending: Number(m.pending),
      lps: (m.lps as Address[]) ?? [],
      keys: (m.keys as Hex[]) ?? [],
      sizes: ((m.sizes as (bigint | number)[]) ?? []).map((x) => BigInt(x)),
    };
  } catch {
    return null;
  }
}

function BasketRow({ basket }: { basket: KnownBasket }) {
  const helix = useHelix();
  const store = useStore();
  const [match, setMatch] = useState<DecodedMatch | null>(null);
  const [loading, setLoading] = useState(true);
  const [isMock, setIsMock] = useState(true);
  const [settleBusy, setSettleBusy] = useState(false);
  const [msg, setMsg] = useState<{ kind: "ok" | "err"; text: string } | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    if (helix.client && !basket.mock) {
      try {
        const raw = await helix.client.getMatch(basket.matchId);
        const decoded = decodeMatch(raw);
        if (decoded && decoded.status !== MatchStatus.NONE) {
          setMatch(decoded);
          setIsMock(false);
          setLoading(false);
          return;
        }
      } catch {
        /* fall through to mock */
      }
    }
    setMatch(mockMatch(basket.matchId));
    setIsMock(true);
    setLoading(false);
  }, [helix.client, basket.matchId, basket.mock]);

  useEffect(() => {
    void load();
  }, [load]);

  async function onSettle() {
    setMsg(null);
    if (!helix.client || !helix.hasWallet || isMock) {
      setMsg({
        kind: "err",
        text: isMock
          ? "Cannot settle a mock basket on-chain."
          : "Connect a wallet on the target chain to settle.",
      });
      return;
    }
    setSettleBusy(true);
    try {
      const tx = await helix.client.settle(basket.matchId);
      setMsg({ kind: "ok", text: `settle() sent · tx ${short(tx, 10, 8)}` });
      void load();
    } catch (err) {
      setMsg({ kind: "err", text: err instanceof Error ? err.message : String(err) });
    } finally {
      setSettleBusy(false);
    }
  }

  const status = match?.status ?? MatchStatus.NONE;
  const canSettle =
    status === MatchStatus.OPEN &&
    !isMock &&
    helix.hasWallet &&
    helix.rightChain &&
    secondsUntil(match?.epochEnd ?? 0n) === 0;

  return (
    <div className="row" style={{ flexDirection: "column", alignItems: "stretch", gap: 12 }}>
      <div className="inline-actions" style={{ justifyContent: "space-between" }}>
        <div className="grow">
          <div className="row-title">
            {match ? poolLabel(match.pool) : "Basket"}{" "}
            <Tag color={STATUS_COLOR[status] ?? "dim"}>{STATUS_LABEL[status] ?? "?"}</Tag>{" "}
            {isMock ? <Tag color="violet">mock</Tag> : <Tag color="green">on-chain</Tag>}
          </div>
          <div className="row-sub">
            {basket.label ?? "basket"} · id <span className="mono">{short(basket.matchId, 10, 8)}</span>
            {basket.submitTx && (
              <>
                {" "}
                · tx <span className="mono">{short(basket.submitTx, 8, 6)}</span>
              </>
            )}
          </div>
        </div>
        <div className="inline-actions">
          <button className="btn ghost sm" onClick={() => void load()} disabled={loading}>
            {loading ? "…" : "Refresh"}
          </button>
          <button
            className="btn ghost sm"
            onClick={() => store.removeBasket(basket.matchId)}
            title="Forget this basket (local only)"
          >
            Forget
          </button>
        </div>
      </div>

      {match && (
        <dl className="kv">
          <dt>Status</dt>
          <dd>{STATUS_LABEL[status] ?? "?"}</dd>
          <dt>Members</dt>
          <dd>{match.enteredCount}</dd>
          <dt>Epoch end</dt>
          <dd>{formatTimestamp(match.epochEnd)}</dd>
          <dt>Time left</dt>
          <dd>
            {status === MatchStatus.SETTLED
              ? "settled"
              : secondsUntil(match.epochEnd) === 0
                ? "expired (settleable)"
                : formatDuration(secondsUntil(match.epochEnd))}
          </dd>
          <dt>ρ (correlation)</dt>
          <dd>{bpsToPct(match.rho)}</dd>
          <dt>Required margin</dt>
          <dd>{bpsToPct(match.requiredRatioBps)}</dd>
          <dt>Pending action</dt>
          <dd>{ACTION_LABEL[match.pending] ?? "?"}</dd>
        </dl>
      )}

      {match && match.lps.length > 0 && (
        <div>
          <div className="muted" style={{ marginBottom: 6 }}>
            Members
          </div>
          <div className="list">
            {match.lps.map((lp, i) => (
              <div key={lp + i} className="row" style={{ padding: "9px 12px" }}>
                <span className="mono grow">{short(lp, 10, 8)}</span>
                <span className="faint mono">
                  {match.sizes[i] !== undefined ? `${formatToken(match.sizes[i]!)} sz` : ""}
                </span>
              </div>
            ))}
          </div>
        </div>
      )}

      {status === MatchStatus.OPEN && (
        <div className="inline-actions">
          <button className="btn primary sm" onClick={onSettle} disabled={settleBusy || !canSettle}>
            {settleBusy ? "Settling…" : "Settle"}
          </button>
          {!canSettle && (
            <span className="faint" style={{ fontSize: 12, alignSelf: "center" }}>
              {isMock
                ? "settle disabled in mock mode"
                : secondsUntil(match?.epochEnd ?? 0n) > 0
                  ? "settle unlocks at epoch end"
                  : !helix.hasWallet
                    ? "connect wallet to settle"
                    : !helix.rightChain
                      ? "wrong chain"
                      : ""}
            </span>
          )}
        </div>
      )}

      {msg && <Notice kind={msg.kind}>{msg.text}</Notice>}
    </div>
  );
}

export function BasketsPanel() {
  const store = useStore();
  const [input, setInput] = useState("");
  const [err, setErr] = useState<string | null>(null);

  function loadManual() {
    setErr(null);
    const v = input.trim();
    if (!/^0x[0-9a-fA-F]{64}$/.test(v)) {
      setErr("Enter a 32-byte (0x + 64 hex) matchId.");
      return;
    }
    store.addBasket({
      matchId: v as Hex,
      createdAt: Date.now(),
      mock: false,
      label: "loaded matchId",
    });
    setInput("");
  }

  return (
    <Card
      title="Baskets"
      subtitle="Track matched baskets. Read live status via getMatch; settle expired open baskets."
    >
      <div className="inline-actions" style={{ marginBottom: 16 }}>
        <input
          placeholder="Load matchId (0x…)"
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && loadManual()}
        />
        <button className="btn" onClick={loadManual}>
          Load
        </button>
      </div>
      {err && <Notice kind="err">⚠ {err}</Notice>}

      {store.baskets.length === 0 ? (
        <Empty>No baskets yet. Form one in the Matching panel or load a matchId above.</Empty>
      ) : (
        <div className="list">
          {store.baskets.map((b) => (
            <BasketRow key={b.matchId} basket={b} />
          ))}
        </div>
      )}
    </Card>
  );
}
