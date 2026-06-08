import type { Intent } from "@helix/sdk";

/** Floating-point mirror of the on-chain CPMM IL fraction f(r) = 1 − 2·√r/(1+r) ∈ [0,1). */
export function ilFraction(r: number): number {
  if (r <= 0) return 0;
  const f = 1 - (2 * Math.sqrt(r)) / (1 + r);
  return f < 0 ? 0 : f;
}

/** Worst-case IL fraction over a max price drift, evaluated at the up-move and down-move. */
export function maxILFraction(driftBps: number): number {
  const d = driftBps / 10_000;
  const up = 1 + d;
  const down = 1 / (1 + d);
  return Math.max(ilFraction(up), ilFraction(down));
}

/** Notional of an intent in whole token1 units (maxSize is WAD-scaled). */
export function notional(intent: Intent): number {
  return Number(intent.maxSize) / 1e18;
}

/** IL "volatility" proxy of a position: the worst-case IL magnitude its drift bound admits. */
export function ilVolatility(intent: Intent): number {
  return maxILFraction(Number(intent.maxDriftBps)) * notional(intent);
}

/** Capital weights w_i = size_i / Σ size for a basket. */
export function weights(members: Intent[]): number[] {
  const sizes = members.map(notional);
  const total = sizes.reduce((a, b) => a + b, 0);
  if (total === 0) return members.map(() => 0);
  return sizes.map((s) => s / total);
}

/**
 * Aggregate IL variance of a basket: Var(Σ wᵢ·ILᵢ) = Σᵢ Σⱼ wᵢ wⱼ σᵢ σⱼ ρᵢⱼ,
 * where σ is `ilVolatility` and ρ is supplied by `corr(i,j)` (1 on the diagonal).
 */
export function basketVariance(members: Intent[], corr: (i: number, j: number) => number): number {
  const w = weights(members);
  const sigma = members.map(ilVolatility);
  let v = 0;
  for (let i = 0; i < members.length; i++) {
    for (let j = 0; j < members.length; j++) {
      const rho = i === j ? 1 : corr(i, j);
      v += w[i] * w[j] * sigma[i] * sigma[j] * rho;
    }
  }
  return v;
}

/**
 * Diversification ratio σ_basket / Σ wᵢσᵢ ∈ (0, 1]; below 1 means the basket's pooled IL is less
 * volatile than the weighted sum of standalone ILs. Returns the percentage variance reduction.
 */
export function varianceReductionPct(members: Intent[], corr: (i: number, j: number) => number): number {
  const w = weights(members);
  const sigma = members.map(ilVolatility);
  const weightedSumSigma = w.reduce((a, _, i) => a + w[i] * sigma[i], 0);
  if (weightedSumSigma === 0) return 0;
  const ratio = Math.sqrt(basketVariance(members, corr)) / weightedSumSigma;
  return Math.max(0, (1 - ratio) * 100);
}
