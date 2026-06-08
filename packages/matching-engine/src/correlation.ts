/** Statistics utilities for correlation-aware matching. All inputs are plain JS numbers. */

export function mean(xs: number[]): number {
  if (xs.length === 0) return 0;
  return xs.reduce((a, b) => a + b, 0) / xs.length;
}

export function std(xs: number[]): number {
  if (xs.length < 2) return 0;
  const m = mean(xs);
  const v = xs.reduce((a, b) => a + (b - m) * (b - m), 0) / (xs.length - 1);
  return Math.sqrt(v);
}

/** Pearson correlation coefficient of two equal-length series, in [-1, 1]. */
export function pearson(xs: number[], ys: number[]): number {
  const n = Math.min(xs.length, ys.length);
  if (n < 2) return 0;
  const mx = mean(xs);
  const my = mean(ys);
  let num = 0;
  let dx = 0;
  let dy = 0;
  for (let i = 0; i < n; i++) {
    const a = xs[i] - mx;
    const b = ys[i] - my;
    num += a * b;
    dx += a * a;
    dy += b * b;
  }
  const den = Math.sqrt(dx * dy);
  return den === 0 ? 0 : num / den;
}

/** Convert a price series to a simple-return series r_t = (p_t - p_{t-1}) / p_{t-1}. */
export function returnsFromPrices(prices: number[]): number[] {
  const out: number[] = [];
  for (let i = 1; i < prices.length; i++) {
    if (prices[i - 1] === 0) {
      out.push(0);
    } else {
      out.push((prices[i] - prices[i - 1]) / prices[i - 1]);
    }
  }
  return out;
}

export interface CorrelationMatrix {
  keys: string[];
  matrix: number[][]; // symmetric, unit diagonal
}

/** Pairwise Pearson correlation matrix of return series, keyed by feed/pool id. */
export function correlationMatrix(returnsByKey: Record<string, number[]>): CorrelationMatrix {
  const keys = Object.keys(returnsByKey);
  const matrix: number[][] = keys.map(() => keys.map(() => 0));
  for (let i = 0; i < keys.length; i++) {
    for (let j = i; j < keys.length; j++) {
      const c = i === j ? 1 : pearson(returnsByKey[keys[i]], returnsByKey[keys[j]]);
      matrix[i][j] = c;
      matrix[j][i] = c;
    }
  }
  return { keys, matrix };
}

/** Lookup helper for a pair of keys against a CorrelationMatrix (defaults to 0 if unknown). */
export function corrOf(cm: CorrelationMatrix, a: string, b: string): number {
  const i = cm.keys.indexOf(a);
  const j = cm.keys.indexOf(b);
  if (i < 0 || j < 0) return 0;
  return cm.matrix[i][j];
}
