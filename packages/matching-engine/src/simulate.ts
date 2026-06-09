import { ilAbsolute } from "./portfolio.js";

/** A basket member for the Monte-Carlo: its entry price and notional size. */
export interface SimMember {
  entryPrice: number;
  size: number;
}

export interface MemberStat {
  reductionPct: number; // % drop in the VARIANCE of this member's realized IL (can be negative)
  varStandalone: number;
  varMutualized: number;
}

export interface SimResult {
  scenarios: number;
  rho: number;
  /**
   * Ex-ante IL-variance reduction (%): the drop in the variance of a *uniformly-random* member's
   * realized IL — i.e. what an LP expects before knowing which position it will hold. Always ≥ 0 for
   * imperfectly-correlated members (diversification). This is the insurance an LP buys by opting in.
   */
  exAnteReductionPct: number;
  perMember: MemberStat[]; // realized, ex-post per slot — some members win, some pay (adverse selection)
}

function mulberry32(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** Lognormal terminal-price samples around 1.0 with volatility `sigma` (deterministic given `seed`). */
export function lognormalPrices(n: number, sigma: number, seed = 7): number[] {
  const rng = mulberry32(seed);
  const out: number[] = [];
  for (let i = 0; i < n; i++) {
    const u = Math.max(rng(), 1e-12);
    const v = rng();
    const z = Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v);
    out.push(Math.exp(sigma * z - (sigma * sigma) / 2)); // martingale-corrected
  }
  return out;
}

function variance(xs: number[]): number {
  const n = xs.length;
  if (n < 2) return 0;
  const m = xs.reduce((a, b) => a + b, 0) / n;
  return xs.reduce((a, b) => a + (b - m) * (b - m), 0) / (n - 1);
}

/**
 * Monte-Carlo the realized IL of each basket member across `prices` settlement scenarios, with and
 * without ρ-mutualization, and measure how much each member's IL *standard deviation* shrinks. Members
 * who entered at different prices have imperfectly- (often negatively-) correlated IL profiles, so
 * pooling genuinely reduces each one's IL variance — this quantifies it from data, not an assumption.
 */
export function simulateBasket(members: SimMember[], rho: number, prices: number[]): SimResult {
  const n = members.length;
  const sizeTotal = members.reduce((a, m) => a + m.size, 0);
  const standalone: number[][] = members.map(() => []);
  const mutualized: number[][] = members.map(() => []);

  for (const p1 of prices) {
    const il = members.map((m) => ilAbsolute(m.size, m.entryPrice, p1));
    const ilTotal = il.reduce((a, b) => a + b, 0);
    for (let i = 0; i < n; i++) {
      const fair = sizeTotal === 0 ? 0 : (members[i].size / sizeTotal) * ilTotal;
      const adj = rho * (il[i] - fair); // member receives (+) when worse than fair
      standalone[i].push(il[i]);
      mutualized[i].push(il[i] - adj); // effective IL after redistribution
    }
  }

  const perMember: MemberStat[] = members.map((_, i) => {
    const s = variance(standalone[i]);
    const mu = variance(mutualized[i]);
    return { varStandalone: s, varMutualized: mu, reductionPct: s === 0 ? 0 : (1 - mu / s) * 100 };
  });

  // Ex-ante: size-weighted mean variance, standalone vs mutualized. ≥ 0 for imperfectly-correlated members.
  let wStd = 0;
  let wMut = 0;
  for (let i = 0; i < n; i++) {
    const w = sizeTotal === 0 ? 0 : members[i].size / sizeTotal;
    wStd += w * perMember[i].varStandalone;
    wMut += w * perMember[i].varMutualized;
  }
  const exAnteReductionPct = wStd === 0 ? 0 : (1 - wMut / wStd) * 100;

  return { scenarios: prices.length, rho, exAnteReductionPct, perMember };
}
