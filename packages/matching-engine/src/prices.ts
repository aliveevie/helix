import { returnsFromPrices } from "./correlation.js";

/** Source of trailing price history per feed key (e.g. a Chainlink feed or pool). */
export interface PriceProvider {
  history(feedKey: string): Promise<number[]>;
  feeds(): string[];
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

export interface SyntheticFeed {
  beta: number; // exposure to the common market factor (sign drives cross-feed correlation)
  vol: number; // idiosyncratic volatility
}

/**
 * Deterministic synthetic price provider: each feed's return is `beta·market + vol·idio`, so feeds
 * with same-sign betas are correlated and opposite-sign betas anti-correlated. Useful for demos/tests.
 */
export class SyntheticPriceProvider implements PriceProvider {
  private cache = new Map<string, number[]>();

  constructor(
    private readonly config: Record<string, SyntheticFeed>,
    private readonly length = 30,
    private readonly seed = 42,
    private readonly marketVol = 0.03,
  ) {}

  feeds(): string[] {
    return Object.keys(this.config);
  }

  private generate(): void {
    const rng = mulberry32(this.seed);
    const gauss = () => {
      // Box–Muller
      const u = Math.max(rng(), 1e-9);
      const v = rng();
      return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v);
    };
    const market: number[] = [];
    for (let t = 0; t < this.length; t++) market.push(gauss() * this.marketVol);

    for (const [key, f] of Object.entries(this.config)) {
      const prices = [1];
      for (let t = 0; t < this.length; t++) {
        const r = f.beta * market[t] + f.vol * gauss();
        prices.push(prices[prices.length - 1] * (1 + r));
      }
      this.cache.set(key, prices);
    }
  }

  async history(feedKey: string): Promise<number[]> {
    if (this.cache.size === 0) this.generate();
    return this.cache.get(feedKey) ?? [];
  }
}

/** Convenience: pull histories for every feed and compute their return series. */
export async function returnsForFeeds(provider: PriceProvider): Promise<Record<string, number[]>> {
  const out: Record<string, number[]> = {};
  for (const key of provider.feeds()) {
    out[key] = returnsFromPrices(await provider.history(key));
  }
  return out;
}
