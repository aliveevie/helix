import type { Address, Hex } from "viem";
import { type HelixClient } from "@helix/sdk";
import { type CorrelationMatrix, correlationMatrix } from "./correlation.js";
import { type PriceProvider, returnsForFeeds } from "./prices.js";
import { type BasketCandidate, type OptimizerOptions, type SignedIntent, formBaskets, toSubmitArgs } from "./optimizer.js";

export interface EngineConfig extends OptimizerOptions {
  /** Maps an on-chain poolId (bytes32) to the feed key used for its price history. */
  feedOfPool?: Record<string, string>;
}

export interface RunResult {
  correlation: CorrelationMatrix;
  baskets: BasketCandidate[];
}

/**
 * Stateless-ish matching engine: ingests signed intents, builds a cross-feed correlation view, forms
 * diversified baskets, and (optionally) submits them on-chain through the SDK's `HelixClient`. The
 * engine holds no privileged role — `submitMatch` re-verifies everything on-chain.
 */
export class MatchingEngine {
  private signed: SignedIntent[] = [];

  constructor(
    private readonly priceProvider: PriceProvider,
    private readonly config: EngineConfig = {},
    private readonly client?: HelixClient,
  ) {}

  /** Add a signed intent to the local mempool. */
  ingest(item: SignedIntent): void {
    this.signed.push(item);
  }

  ingestMany(items: SignedIntent[]): void {
    for (const i of items) this.ingest(i);
  }

  get mempool(): readonly SignedIntent[] {
    return this.signed;
  }

  clear(): void {
    this.signed = [];
  }

  /** Cross-feed correlation matrix from trailing price history. */
  async marketView(): Promise<CorrelationMatrix> {
    return correlationMatrix(await returnsForFeeds(this.priceProvider));
  }

  /** Form baskets, optionally gated by an on-chain reputation lookup. */
  plan(reputationOf?: (lp: Address) => number): BasketCandidate[] {
    return formBaskets(this.signed, { ...this.config, reputationOf: reputationOf ?? this.config.reputationOf });
  }

  /** Compute the market view and the planned baskets in one shot. */
  async runOnce(reputationOf?: (lp: Address) => number): Promise<RunResult> {
    return { correlation: await this.marketView(), baskets: this.plan(reputationOf) };
  }

  /** Submit a basket on-chain (requires a wallet-backed HelixClient). */
  async submit(candidate: BasketCandidate): Promise<Hex> {
    if (!this.client) throw new Error("MatchingEngine: no HelixClient configured for submission");
    const { intents, signatures } = toSubmitArgs(candidate);
    return this.client.submitMatch(intents, signatures);
  }
}
