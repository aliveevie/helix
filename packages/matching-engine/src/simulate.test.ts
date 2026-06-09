import { describe, expect, it } from "vitest";
import { lognormalPrices, simulateBasket } from "./simulate.js";

describe("Monte-Carlo IL variance reduction", () => {
  const prices = lognormalPrices(4000, 0.35, 42);

  it("ex-ante variance reduction is positive for imperfectly-correlated members (the insurance)", () => {
    const res = simulateBasket(
      [
        { entryPrice: 0.7, size: 1000 },
        { entryPrice: 1.4, size: 1000 },
      ],
      1.0,
      prices,
    );
    expect(res.exAnteReductionPct).toBeGreaterThan(5);
  });

  it("is ex-post asymmetric — at least one member's variance RISES (honest adverse selection)", () => {
    const res = simulateBasket(
      [
        { entryPrice: 0.7, size: 1000 },
        { entryPrice: 1.4, size: 1000 },
      ],
      1.0,
      prices,
    );
    expect(res.perMember.some((m) => m.reductionPct < 0)).toBe(true);
  });

  it("yields ~no ex-ante change when members are identical (perfectly correlated IL)", () => {
    const res = simulateBasket(
      [
        { entryPrice: 1.0, size: 1000 },
        { entryPrice: 1.0, size: 1000 },
      ],
      1.0,
      prices,
    );
    expect(Math.abs(res.exAnteReductionPct)).toBeLessThan(1);
  });

  it("ex-ante reduction scales with ρ (more mutualization ⇒ more diversification)", () => {
    const members = [
      { entryPrice: 0.7, size: 1000 },
      { entryPrice: 1.4, size: 1000 },
    ];
    const half = simulateBasket(members, 0.5, prices).exAnteReductionPct;
    const full = simulateBasket(members, 1.0, prices).exAnteReductionPct;
    expect(full).toBeGreaterThan(half);
  });
});
