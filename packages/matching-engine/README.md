# @helix/matching-engine

Permissionless matching engine for Helix — correlation-aware basket formation, a Monte-Carlo
IL-variance simulator, and on-chain submission via `@helix/sdk`. The engine holds no privileged role:
`submitMatch` re-verifies every intent on-chain, so a malicious or buggy engine can only produce matches
the hook rejects.

```bash
pnpm --filter @helix/matching-engine start   # offline demo: correlation matrix + baskets + Monte-Carlo
pnpm --filter @helix/matching-engine test    # 15 tests
```

## What it does

1. **Correlation** (`correlation.ts`) — pairwise Pearson matrix from trailing price/return history.
2. **Portfolio math** (`portfolio.ts`) — closed-form CPMM IL (mirrors on-chain `ILMath`), IL-volatility,
   basket variance.
3. **Optimizer** (`optimizer.ts`) — greedily forms compatible baskets (same pool, distinct LPs,
   reputation-floor-clearing) that minimize aggregate IL variance.
4. **Monte-Carlo** (`simulate.ts`) — measures the **ex-ante IL-variance reduction** an LP gets by joining
   a basket, across random settlement scenarios. This is the insurance thesis, quantified from data:
   ex-ante everyone's expected variance drops; ex-post it's zero-sum.
5. **Engine** (`engine.ts`) — ingest signed intents → market view → plan baskets → `submit` via the SDK.

```ts
import { MatchingEngine, SyntheticPriceProvider, simulateBasket, lognormalPrices } from "@helix/matching-engine";

const sim = simulateBasket(
  [{ entryPrice: 0.7, size: 1000 }, { entryPrice: 1.4, size: 1000 }],
  1.0,
  lognormalPrices(5000, 0.4, 7),
);
console.log(sim.exAnteReductionPct); // measured % reduction in expected IL variance
```
