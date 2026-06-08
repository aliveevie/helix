import { useEffect, useState } from "react";
import { DEMO_POOLS } from "../config";
import { useHelix } from "../lib/useHelix";
import { mockBreakerState, MOCK_BREAKER_LABELS } from "../lib/mock";
import { WalletButton } from "./WalletButton";

const BREAKER_PILL = ["ok", "warn", "bad"] as const;

export function Header() {
  const helix = useHelix();
  const [state, setState] = useState<number>(0);
  const [isMock, setIsMock] = useState(true);

  // Watch the headline pool's circuit-breaker state.
  const watchPool = DEMO_POOLS[0]!.id;

  useEffect(() => {
    let cancelled = false;
    async function load() {
      if (helix.client) {
        try {
          const s = await helix.client.breakerState(watchPool);
          if (!cancelled) {
            setState(s);
            setIsMock(false);
          }
          return;
        } catch {
          /* fall through to mock */
        }
      }
      if (!cancelled) {
        setState(mockBreakerState(watchPool));
        setIsMock(true);
      }
    }
    void load();
    const t = setInterval(load, 15000);
    return () => {
      cancelled = true;
      clearInterval(t);
    };
  }, [helix.client, watchPool]);

  const label = MOCK_BREAKER_LABELS[state] ?? "UNKNOWN";
  const pillKind = BREAKER_PILL[state] ?? "warn";

  return (
    <header className="header">
      <div className="header-inner">
        <div className="brand">
          <img src="/helix.svg" alt="Helix" />
          <div className="brand-text">
            <span className="wordmark gradient-text">Helix</span>
            <span className="tagline">Cross-Pool IL Mutualization for Uniswap v4</span>
          </div>
        </div>
        <div className="header-spacer" />
        <div className="header-controls">
          <span
            className={`pill ${pillKind}`}
            title={`CircuitBreaker state for the headline pool${isMock ? " (mock)" : ""}`}
          >
            <span className="dot" />
            Breaker: {label}
            {isMock ? " ·mock" : ""}
          </span>
          <WalletButton />
        </div>
      </div>
    </header>
  );
}
