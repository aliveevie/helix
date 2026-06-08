import { describe, expect, it } from "vitest";
import { correlationMatrix, corrOf, pearson, returnsFromPrices } from "./correlation.js";

describe("correlation", () => {
  it("pearson is 1 for identical, -1 for mirrored", () => {
    expect(pearson([1, 2, 3, 4], [1, 2, 3, 4])).toBeCloseTo(1, 6);
    expect(pearson([1, 2, 3, 4], [4, 3, 2, 1])).toBeCloseTo(-1, 6);
  });

  it("returnsFromPrices computes simple returns", () => {
    const r = returnsFromPrices([100, 110, 99]);
    expect(r[0]).toBeCloseTo(0.1, 6);
    expect(r[1]).toBeCloseTo(-0.1, 6);
  });

  it("correlationMatrix is symmetric with unit diagonal", () => {
    const cm = correlationMatrix({
      a: [0.01, -0.02, 0.03, -0.01],
      b: [-0.01, 0.02, -0.03, 0.01], // mirror of a ⇒ ~ -1
      c: [0.02, 0.01, 0.04, 0.0],
    });
    expect(cm.matrix[0][0]).toBe(1);
    expect(cm.matrix[1][1]).toBe(1);
    expect(corrOf(cm, "a", "b")).toBeCloseTo(-1, 6);
    expect(corrOf(cm, "a", "b")).toBeCloseTo(corrOf(cm, "b", "a"), 12);
  });
});
