import { MatchStatus, RebalanceAction } from "@helix/sdk";
import type { Address, Hex } from "viem";
import type { DecodedMatch } from "./types";

/**
 * Deterministic mock data so the demo is fully functional with NO chain.
 * Everything is clearly labelled "mock" in the UI.
 */

const MOCK_LPS: Address[] = [
  "0xAbC1230000000000000000000000000000000001",
  "0xDeF4560000000000000000000000000000000002",
  "0x9876540000000000000000000000000000000003",
];

/** Stable hash → number in [0, mod) from a hex string. */
function seedFrom(id: string, mod: number): number {
  let acc = 0;
  for (let i = 2; i < id.length; i++) {
    acc = (acc * 31 + id.charCodeAt(i)) % 1_000_000_007;
  }
  return acc % mod;
}

export function mockMatch(matchId: Hex): DecodedMatch {
  const s = seedFrom(matchId, 1000);
  const memberCount = 2 + (s % 2); // 2 or 3
  const lps = MOCK_LPS.slice(0, memberCount);
  const nowSec = Math.floor(Date.now() / 1000);
  // Half the mocks are still open, half already settled.
  const settled = s % 3 === 0;
  return {
    pool: ("0x" + (s % 4 === 0 ? "1" : s % 4 === 1 ? "2" : s % 4 === 2 ? "3" : "4").repeat(64)) as Hex,
    epochEnd: BigInt(nowSec + (settled ? -3600 : 3600 + (s % 7200))),
    minDuration: BigInt(3600),
    rho: 4000 + (s % 5000), // correlation in bps, 0.40 – 0.90
    requiredRatioBps: 10500, // 105% margin ratio
    enteredCount: memberCount,
    status: settled ? MatchStatus.SETTLED : MatchStatus.OPEN,
    pending: s % 5 === 0 ? RebalanceAction.PAUSE : RebalanceAction.NONE,
    lps,
    keys: lps.map((_, i) => ("0x" + String(i + 1).repeat(64).slice(0, 64)) as Hex),
    sizes: lps.map((_, i) => BigInt(50 + i * 25) * 10n ** 18n),
  };
}

/** Mock reputation score, deterministic per address. */
export function mockScore(lp: Address): number {
  return 600 + seedFrom(lp.toLowerCase(), 400); // 600 – 1000
}

/** Mock circuit-breaker state: 0 NORMAL, 1 ELEVATED, 2 HALTED. */
export function mockBreakerState(poolId: Hex): number {
  return seedFrom(poolId, 10) < 7 ? 0 : seedFrom(poolId, 10) < 9 ? 1 : 2;
}

export function mockMarginOf(matchId: Hex, _lp: Address): bigint {
  void _lp;
  return BigInt(100 + seedFrom(matchId, 50)) * 10n ** 18n;
}

export const MOCK_BREAKER_LABELS = ["NORMAL", "ELEVATED", "HALTED"] as const;
