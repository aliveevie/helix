import type { Address, Hex, TypedDataDomain } from "viem";

/// Matches `HelixTypes.Intent` and the EIP-712 type string in `IntentLib`.
export interface Intent {
  lp: Address;
  pool: Hex; //          PoolId (bytes32)
  maxDriftBps: bigint;
  minDuration: bigint; // uint64 (seconds)
  maxSize: bigint; //    uint128 — matched notional (token1 WAD units)
  repFloor: number; //   uint16
  nonce: bigint;
  deadline: bigint; //   uint64
}

/// EIP-712 type definition consumed by viem's signTypedData. Field order/types MUST match
/// `IntentLib.INTENT_TYPEHASH` exactly, or on-chain signature recovery will fail.
export const IntentEip712Types = {
  Intent: [
    { name: "lp", type: "address" },
    { name: "pool", type: "bytes32" },
    { name: "maxDriftBps", type: "uint256" },
    { name: "minDuration", type: "uint64" },
    { name: "maxSize", type: "uint128" },
    { name: "repFloor", type: "uint16" },
    { name: "nonce", type: "uint256" },
    { name: "deadline", type: "uint64" },
  ],
} as const;

export interface HelixAddresses {
  hook: Address;
  registry: Address;
  reputation: Address;
  breaker: Address;
  oracle: Address;
  valueToken: Address;
  poolManager?: Address;
}

export function helixDomain(chainId: number, hook: Address): TypedDataDomain {
  return { name: "Helix", version: "1", chainId, verifyingContract: hook };
}

export enum RebalanceAction {
  NONE = 0,
  RE_MATCH = 1,
  PAUSE = 2,
  RESUME = 3,
}

export enum MatchStatus {
  NONE = 0,
  PENDING = 1,
  OPEN = 2,
  SETTLED = 3,
}
