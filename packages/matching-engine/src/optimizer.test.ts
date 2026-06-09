import { describe, expect, it } from "vitest";
import type { Address, Hex, Intent } from "@helix/sdk";
import { type SignedIntent, formBaskets, formCrossPoolBaskets, toSubmitArgs } from "./optimizer.js";
import { correlationMatrix } from "./correlation.js";

const POOL_A = ("0x" + "11".repeat(32)) as Hex;
const POOL_B = ("0x" + "22".repeat(32)) as Hex;

let n = 0;
function si(pool: Hex, sizeEth: number, driftBps: number, repFloor = 0, lp?: Address): SignedIntent {
  return {
    intent: {
      lp: lp ?? (("0x" + (++n).toString(16).padStart(40, "0")) as Address),
      pool,
      maxDriftBps: BigInt(driftBps),
      minDuration: 3600n,
      maxSize: BigInt(sizeEth) * 10n ** 18n,
      repFloor,
      nonce: BigInt(n),
      deadline: 0n,
    },
    signature: "0x00" as Hex,
  };
}

describe("basket optimizer", () => {
  it("groups by pool and never mixes pools in a basket", () => {
    const baskets = formBaskets([
      si(POOL_A, 1000, 2000),
      si(POOL_A, 500, 2000),
      si(POOL_B, 800, 1500),
      si(POOL_B, 300, 1500),
    ]);
    expect(baskets.length).toBe(2);
    for (const b of baskets) {
      expect(b.members.every((m) => m.intent.pool === b.pool)).toBe(true);
    }
  });

  it("respects maxBasket and minMembers", () => {
    const items = Array.from({ length: 5 }, (_, i) => si(POOL_A, 100 * (i + 1), 2000));
    const baskets = formBaskets(items, { maxBasket: 2, minMembers: 2 });
    expect(baskets.every((b) => b.members.length <= 2)).toBe(true);
    expect(baskets.every((b) => b.members.length >= 2)).toBe(true);
  });

  it("excludes members who cannot clear the counterparty reputation floor", () => {
    const trusted = ("0x" + "aa".repeat(20)) as Address;
    const newbie = ("0x" + "bb".repeat(20)) as Address;
    // `trusted` requires a counterparty reputation of 100; `newbie` has score 0 ⇒ no compatible basket.
    const items = [si(POOL_A, 1000, 2000, 100, trusted), si(POOL_A, 1000, 2000, 0, newbie)];
    const baskets = formBaskets(items, {
      reputationOf: (lp) => (lp === trusted ? 500 : 0),
    });
    expect(baskets.length).toBe(0);
  });

  it("forms CROSS-POOL baskets that pair anti-correlated pools (correlation matrix is used)", () => {
    const POOL_ETH = ("0x" + "e1".repeat(32)) as Hex;
    const POOL_ARB = ("0x" + "a2".repeat(32)) as Hex;
    // ETH and ARB return series are mirror images ⇒ correlation ≈ -1.
    const cm = correlationMatrix({
      eth: [0.02, -0.01, 0.03, -0.02, 0.01],
      arb: [-0.02, 0.01, -0.03, 0.02, -0.01],
    });
    const feedOfPool = (p: Hex) => (p === POOL_ETH ? "eth" : "arb");

    const items = [si(POOL_ETH, 1000, 2000), si(POOL_ARB, 1000, 2000)];
    const baskets = formCrossPoolBaskets(items, cm, { feedOfPool, maxBasket: 2, minMembers: 2 });

    expect(baskets.length).toBe(1);
    const pools = new Set(baskets[0].members.map((m) => m.intent.pool));
    expect(pools.size).toBe(2); // genuinely spans two pools
    // anti-correlated pooling gives a large measured variance reduction
    expect(baskets[0].varianceReductionPct).toBeGreaterThan(20);
  });

  it("forms a basket when reputation floors are met and reports variance reduction", () => {
    const a = ("0x" + "aa".repeat(20)) as Address;
    const b = ("0x" + "bb".repeat(20)) as Address;
    const items = [si(POOL_A, 1000, 2000, 50, a), si(POOL_A, 800, 2500, 50, b)];
    const baskets = formBaskets(items, { reputationOf: () => 100 });
    expect(baskets.length).toBe(1);
    expect(baskets[0].varianceReductionPct).toBeGreaterThan(0);
    const { intents, signatures } = toSubmitArgs(baskets[0]);
    expect(intents.length).toBe(2);
    expect(signatures.length).toBe(2);
  });
});
