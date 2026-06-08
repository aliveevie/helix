import { useState } from "react";
import { ADDRESSES_CONFIGURED, helixChain, TARGET_CHAIN_ID } from "./config";
import { BasketsPanel } from "./components/BasketsPanel";
import { CreateIntentPanel } from "./components/CreateIntentPanel";
import { Header } from "./components/Header";
import { MempoolPanel } from "./components/MempoolPanel";
import { ReputationPanel } from "./components/ReputationPanel";
import { Notice } from "./components/ui";

type Tab = "intents" | "matching" | "baskets" | "reputation";

const TABS: { id: Tab; label: string }[] = [
  { id: "intents", label: "Create Intent" },
  { id: "matching", label: "Mempool · Matching" },
  { id: "baskets", label: "Baskets" },
  { id: "reputation", label: "Reputation" },
];

export default function App() {
  const [tab, setTab] = useState<Tab>("intents");

  return (
    <>
      <Header />
      <main className="app">
        <section className="hero">
          <h1>
            Mutualized <span className="gradient-text">Impermanent Loss</span>
            <br />
            for Uniswap v4 LPs
          </h1>
          <p>
            Helix matches LP positions into baskets, then redistributes value at settlement so every
            member converges toward the basket's capital-weighted average IL. Zero-sum, self-funded
            from posted margins, auto-rebalanced by a Reactive Smart Contract.
          </p>
          <div className="hero-stats">
            <div className="stat">
              <div className="k">Settlement</div>
              <div className="v gradient-text">Zero-Sum</div>
            </div>
            <div className="stat">
              <div className="k">Intents</div>
              <div className="v gradient-text">EIP-712</div>
            </div>
            <div className="stat">
              <div className="k">Reputation</div>
              <div className="v gradient-text">ERC-8004</div>
            </div>
            <div className="stat">
              <div className="k">Rebalancer</div>
              <div className="v gradient-text">Reactive</div>
            </div>
          </div>
        </section>

        {!ADDRESSES_CONFIGURED && (
          <Notice kind="mock">
            <span>
              <b>Mock mode.</b> Core contract addresses are still placeholders (all zero), so every
              read falls back to deterministic mock data and writes are simulated. Set the{" "}
              <span className="mono">VITE_*</span> address env vars (see README) to go live on{" "}
              <b>{helixChain.name}</b> (chainId {TARGET_CHAIN_ID}).
            </span>
          </Notice>
        )}

        <div className="tabs" role="tablist">
          {TABS.map((t) => (
            <button
              key={t.id}
              role="tab"
              aria-selected={tab === t.id}
              className={tab === t.id ? "tab active" : "tab"}
              onClick={() => setTab(t.id)}
            >
              {t.label}
            </button>
          ))}
        </div>

        <div className="section-stack">
          {tab === "intents" && (
            <div className="grid-2">
              <CreateIntentPanel />
              <MempoolPanel />
            </div>
          )}
          {tab === "matching" && <MempoolPanel />}
          {tab === "baskets" && <BasketsPanel />}
          {tab === "reputation" && <ReputationPanel />}
        </div>

        <footer className="footer">
          <span>
            Helix · Cross-Pool IL Mutualization for Uniswap v4 — HelixHook · SettlementRegistry ·
            ReputationAccumulator · CircuitBreaker
          </span>
          <span className="mono">
            chain {TARGET_CHAIN_ID} · {ADDRESSES_CONFIGURED ? "live" : "mock"}
          </span>
        </footer>
      </main>
    </>
  );
}
