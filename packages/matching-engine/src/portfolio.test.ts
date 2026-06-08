import { describe, expect, it } from "vitest";
import type { Address, Hex, Intent } from "@helix/sdk";
import { ilFraction, maxILFraction, varianceReductionPct } from "./portfolio.js";

const POOL = ("0x" + "11".repeat(32)) as Hex;

function intent(sizeEth: number, driftBps: number): Intent {
  return {
    lp: ("0x" + "ab".repeat(20)) as Address,
    pool: POOL,
    maxDriftBps: BigInt(driftBps),
    minDuration: 3600n,
    maxSize: BigInt(sizeEth) * 10n ** 18n,
    repFloor: 0,
    nonce: 0n,
    deadline: 0n,
  };
}

describe("portfolio IL math", () => {
  it("ilFraction is 0 at no move, ~5.72% at a 2x move", () => {
    expect(ilFraction(1)).toBe(0);
    expect(ilFraction(2)).toBeCloseTo(0.0572, 4);
  });

  it("maxILFraction grows with drift", () => {
    expect(maxILFraction(1000)).toBeLessThan(maxILFraction(3000));
  });

  it("variance reduction is positive for imperfectly-correlated members", () => {
    const members = [intent(1000, 2000), intent(1000, 2000), intent(500, 2500)];
    const corr = (i: number, j: number) => (i === j ? 1 : 0.4);
    expect(varianceReductionPct(members, corr)).toBeGreaterThan(0);
  });

  it("no reduction when members are perfectly correlated", () => {
    const members = [intent(1000, 2000), intent(1000, 2000)];
    const corr = () => 1; // ρ = 1 everywhere
    expect(varianceReductionPct(members, corr)).toBeCloseTo(0, 6);
  });
});
