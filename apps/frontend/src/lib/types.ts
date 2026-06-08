import type { Intent } from "@helix/sdk";
import type { Address, Hex } from "viem";

/** A signed intent sitting in the local "mempool". */
export interface SignedIntent {
  /** Stable client-side id (digest doubles as natural key). */
  id: string;
  intent: Intent;
  signature: Hex;
  digest: Hex;
  signer: Address;
  chainId: number;
  /** ms epoch when it was signed. */
  createdAt: number;
  /** True if produced in mock mode (no wallet) — signature is synthetic. */
  mock: boolean;
}

/** A basket the user knows about (submitted or manually loaded). */
export interface KnownBasket {
  matchId: Hex;
  /** intent digests that went into the basket, if known. */
  intentIds?: string[];
  /** tx hash of the submit, if we sent it. */
  submitTx?: Hex;
  createdAt: number;
  mock: boolean;
  label?: string;
}

/** Decoded on-chain Match tuple (HelixTypes.Match). */
export interface DecodedMatch {
  pool: Hex;
  epochEnd: bigint;
  minDuration: bigint;
  rho: number;
  requiredRatioBps: number;
  enteredCount: number;
  status: number; // MatchStatus
  pending: number; // RebalanceAction
  lps: Address[];
  keys: Hex[];
  sizes: bigint[];
}
