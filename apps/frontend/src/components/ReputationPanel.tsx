import { useState } from "react";
import type { Address } from "viem";
import { isAddress } from "viem";
import { useAccount } from "wagmi";
import { short } from "../lib/format";
import { mockScore } from "../lib/mock";
import { useHelix } from "../lib/useHelix";
import { Card, Notice } from "./ui";

interface ScoreResult {
  address: Address;
  score: number;
  mock: boolean;
}

function scoreTier(score: number): { label: string; color: string } {
  if (score >= 850) return { label: "Excellent", color: "var(--green)" };
  if (score >= 700) return { label: "Strong", color: "var(--cyan)" };
  if (score >= 500) return { label: "Fair", color: "var(--amber)" };
  return { label: "Building", color: "var(--text-faint)" };
}

export function ReputationPanel() {
  const helix = useHelix();
  const { address } = useAccount();
  const [input, setInput] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] = useState<ScoreResult | null>(null);

  async function lookup(addr?: string) {
    const target = (addr ?? input).trim();
    setError(null);
    setResult(null);
    if (!isAddress(target)) {
      setError("Enter a valid 0x address.");
      return;
    }
    setBusy(true);
    try {
      let score: number;
      let mock = true;
      if (helix.client) {
        try {
          score = await helix.client.scoreOf(target as Address);
          mock = false;
        } catch {
          score = mockScore(target as Address);
          mock = true;
        }
      } else {
        score = mockScore(target as Address);
      }
      setResult({ address: target as Address, score, mock });
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setBusy(false);
    }
  }

  const tier = result ? scoreTier(result.score) : null;
  // ERC-8004 reputation is conventionally scaled to 1000.
  const pct = result ? Math.min(100, (result.score / 1000) * 100) : 0;

  return (
    <Card
      title="Reputation"
      subtitle="ERC-8004 reputation accumulator. Higher scores unlock larger baskets and better terms."
    >
      <div className="inline-actions" style={{ marginBottom: 14 }}>
        <input
          placeholder="0x address"
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && lookup()}
        />
        <button className="btn" onClick={() => lookup()} disabled={busy}>
          {busy ? "…" : "Look up"}
        </button>
        {address && (
          <button
            className="btn ghost"
            onClick={() => {
              setInput(address);
              void lookup(address);
            }}
          >
            Me
          </button>
        )}
      </div>

      {error && <Notice kind="err">⚠ {error}</Notice>}

      {result && tier && (
        <div>
          <div className="row" style={{ flexDirection: "column", alignItems: "stretch", gap: 14 }}>
            <div className="inline-actions" style={{ justifyContent: "space-between" }}>
              <span className="mono">{short(result.address, 12, 8)}</span>
              {result.mock ? (
                <span className="tag violet">mock</span>
              ) : (
                <span className="tag green">on-chain</span>
              )}
            </div>
            <div style={{ display: "flex", alignItems: "baseline", gap: 12 }}>
              <span className="num" style={{ fontSize: 40, fontWeight: 800, color: tier.color }}>
                {result.score}
              </span>
              <span className="muted">/ 1000 · {tier.label}</span>
            </div>
            <div
              style={{
                height: 8,
                borderRadius: 999,
                background: "var(--bg)",
                border: "1px solid var(--border-soft)",
                overflow: "hidden",
              }}
            >
              <div
                style={{
                  height: "100%",
                  width: `${pct}%`,
                  background: "var(--grad)",
                  boxShadow: "var(--glow)",
                  transition: "width 0.4s ease",
                }}
              />
            </div>
          </div>
        </div>
      )}

      {!result && !error && (
        <p className="muted">Look up any LP address to see its on-chain reputation score.</p>
      )}
    </Card>
  );
}
