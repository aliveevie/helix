import type { Address, Hex } from "viem";
import type { Intent } from "@helix/sdk";
import { basketVariance, varianceReductionPct, weights } from "./portfolio.js";

export interface SignedIntent {
  intent: Intent;
  signature: Hex;
}

export interface BasketCandidate {
  pool: Hex;
  members: SignedIntent[];
  weights: number[];
  varianceReductionPct: number;
  expectedVariance: number;
  repFloor: number;
}

export interface OptimizerOptions {
  maxBasket?: number; //   max members per basket (default 3)
  minMembers?: number; //  min members per basket (default 2)
  rhoIntra?: number; //    assumed intra-pool IL correlation (default 0.4)
  reputationOf?: (lp: Address) => number; // on-chain reputation lookup (default 0)
}

function intraCorr(rho: number) {
  return (i: number, j: number) => (i === j ? 1 : rho);
}

/** A basket is valid only if every member clears the strictest counterparty reputation floor. */
function satisfiesReputation(members: Intent[], reputationOf: (lp: Address) => number): boolean {
  const maxFloor = members.reduce((m, it) => Math.max(m, it.repFloor), 0);
  return members.every((it) => reputationOf(it.lp) >= maxFloor);
}

/**
 * Greedily form correlation-diversified baskets, one pool at a time. Each basket is grown from a seed
 * by repeatedly adding the compatible member that most reduces the basket's aggregate IL variance.
 */
export function formBaskets(signed: SignedIntent[], opts: OptimizerOptions = {}): BasketCandidate[] {
  const maxBasket = opts.maxBasket ?? 3;
  const minMembers = opts.minMembers ?? 2;
  const rho = opts.rhoIntra ?? 0.4;
  const reputationOf = opts.reputationOf ?? (() => 0);
  const corr = intraCorr(rho);

  // Group by pool (on-chain baskets are single-pool).
  const byPool = new Map<string, SignedIntent[]>();
  for (const s of signed) {
    const k = s.intent.pool;
    (byPool.get(k) ?? byPool.set(k, []).get(k)!).push(s);
  }

  const baskets: BasketCandidate[] = [];

  for (const [pool, group] of byPool) {
    const pool_ = group.slice();
    while (pool_.length >= minMembers) {
      // Seed with the highest-IL-volatility intent (it benefits most from mutualization).
      pool_.sort((a, b) => Number(b.intent.maxSize) - Number(a.intent.maxSize));
      const basket: SignedIntent[] = [pool_.shift()!];

      while (basket.length < maxBasket && pool_.length > 0) {
        let bestIdx = -1;
        let bestVar = Infinity;
        for (let i = 0; i < pool_.length; i++) {
          const trial = [...basket, pool_[i]].map((s) => s.intent);
          if (!satisfiesReputation(trial, reputationOf)) continue;
          const v = basketVariance(trial, corr);
          if (v < bestVar) {
            bestVar = v;
            bestIdx = i;
          }
        }
        if (bestIdx < 0) break;
        basket.push(pool_.splice(bestIdx, 1)[0]);
      }

      const intents = basket.map((s) => s.intent);
      if (basket.length >= minMembers && satisfiesReputation(intents, reputationOf)) {
        baskets.push({
          pool: pool as Hex,
          members: basket,
          weights: weights(intents),
          varianceReductionPct: varianceReductionPct(intents, corr),
          expectedVariance: basketVariance(intents, corr),
          repFloor: intents.reduce((m, it) => Math.max(m, it.repFloor), 0),
        });
      } else {
        // Leftover members couldn't form a compliant basket; stop on this pool.
        break;
      }
    }
  }

  // Best baskets first.
  baskets.sort((a, b) => b.varianceReductionPct - a.varianceReductionPct);
  return baskets;
}

/** Split a candidate into the `(intents[], signatures[])` arrays `submitMatch` expects. */
export function toSubmitArgs(candidate: BasketCandidate): { intents: Intent[]; signatures: Hex[] } {
  return {
    intents: candidate.members.map((m) => m.intent),
    signatures: candidate.members.map((m) => m.signature),
  };
}
