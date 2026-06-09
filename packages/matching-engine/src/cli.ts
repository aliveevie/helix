/**
 * Helix matching engine — offline demo.
 *
 * Generates synthetic LP intents across correlated pools, signs them with throwaway keys, runs the
 * engine, and prints the cross-pool correlation matrix and the diversified baskets it would submit.
 * No chain required:  `pnpm --filter @helix/matching-engine start`
 */
import { type Address, type Hex, keccak256, toHex } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { buildIntent, helixDomain, IntentEip712Types, type Intent } from "@helix/sdk";
import {
  MatchingEngine,
  SyntheticPriceProvider,
  formCrossPoolBaskets,
  lognormalPrices,
  simulateBasket,
  type SignedIntent,
} from "./index.js";

const HOOK = "0x1640000000000000000000000000000000004444" as Address;
const CHAIN_ID = 1301;

const POOLS = {
  "ETH/USDC": keccak256(toHex("ETH/USDC")),
  "WBTC/USDC": keccak256(toHex("WBTC/USDC")),
  "ARB/USDC": keccak256(toHex("ARB/USDC")),
} as const;

// Feeds: ETH and WBTC co-move (positive beta); ARB is anti-correlated (negative beta) — a good hedge.
const provider = new SyntheticPriceProvider({
  "ETH/USDC": { beta: 1.0, vol: 0.02 },
  "WBTC/USDC": { beta: 0.9, vol: 0.025 },
  "ARB/USDC": { beta: -0.8, vol: 0.03 },
});

async function sign(pk: Hex, intent: Intent): Promise<Hex> {
  const account = privateKeyToAccount(pk);
  return account.signTypedData({
    domain: helixDomain(CHAIN_ID, HOOK),
    types: IntentEip712Types,
    primaryType: "Intent",
    message: intent,
  });
}

function pk(i: number): Hex {
  return `0x${(i + 1).toString(16).padStart(64, "0")}` as Hex;
}

async function main() {
  const engine = new MatchingEngine(provider, { maxBasket: 3, minMembers: 2, rhoIntra: 0.4 });

  // Synthetic intents: several LPs per pool with varied sizes and drift tolerances.
  const specs: Array<{ pool: Hex; sizeEth: number; driftBps: number }> = [
    { pool: POOLS["ETH/USDC"], sizeEth: 1000, driftBps: 1500 },
    { pool: POOLS["ETH/USDC"], sizeEth: 250, driftBps: 2500 },
    { pool: POOLS["ETH/USDC"], sizeEth: 600, driftBps: 2000 },
    { pool: POOLS["WBTC/USDC"], sizeEth: 800, driftBps: 1800 },
    { pool: POOLS["WBTC/USDC"], sizeEth: 300, driftBps: 1200 },
    { pool: POOLS["ARB/USDC"], sizeEth: 500, driftBps: 3000 },
    { pool: POOLS["ARB/USDC"], sizeEth: 500, driftBps: 3000 },
  ];

  const now = BigInt(Math.floor(Date.now() / 1000));
  let idx = 0;
  for (const s of specs) {
    const account = privateKeyToAccount(pk(idx));
    const intent = buildIntent({
      lp: account.address,
      pool: s.pool,
      maxDriftBps: BigInt(s.driftBps),
      minDuration: 3600n,
      maxSize: BigInt(Math.round(s.sizeEth)) * 10n ** 18n,
      repFloor: 0,
      nonce: BigInt(idx),
      deadline: now + 86400n,
    });
    const signature = await sign(pk(idx), intent);
    engine.ingest({ intent, signature } satisfies SignedIntent);
    idx++;
  }

  const { correlation, baskets } = await engine.runOnce();

  console.log("\n\x1b[36m═══ Helix Matching Engine ═══\x1b[0m\n");
  console.log("Cross-pool correlation matrix (trailing returns):");
  const names = correlation.keys.map(keyToName);
  const pad = (s: string, n = 11) => s.padStart(n);
  console.log("  " + pad("") + names.map((n) => pad(n)).join(""));
  correlation.matrix.forEach((row, i) => {
    console.log("  " + pad(names[i]) + row.map((c) => pad(c.toFixed(2))).join(""));
  });

  console.log(`\nFormed \x1b[32m${baskets.length}\x1b[0m basket(s):\n`);
  baskets.forEach((b, i) => {
    console.log(
      `  Basket ${i + 1}  pool=${keyToName(b.pool)}  members=${b.members.length}  ` +
        `div-score=\x1b[32m${b.varianceReductionPct.toFixed(1)}\x1b[0m  repFloor=${b.repFloor}`,
    );
    b.members.forEach((m, j) => {
      const sizeEth = Number(m.intent.maxSize) / 1e18;
      console.log(
        `    • ${m.intent.lp.slice(0, 10)}…  size=${sizeEth.toFixed(0)}  ` +
          `drift=${Number(m.intent.maxDriftBps) / 100}%  w=${(b.weights[j] * 100).toFixed(1)}%`,
      );
    });
    console.log("");
  });

  // Cross-pool baskets: the matching engine USES the correlation matrix to hedge across assets.
  const crossPool = formCrossPoolBaskets([...engine.mempool], correlation, {
    feedOfPool: (p) => keyToName(p as string),
    maxBasket: 2,
    minMembers: 2,
  });
  console.log("\x1b[36m═══ Cross-pool baskets (correlation-diversified, hedging across assets) ═══\x1b[0m");
  crossPool.forEach((b, i) => {
    const poolsList = b.members.map((m) => keyToName(m.intent.pool)).join("  +  ");
    console.log(`  Basket ${i + 1}:  ${poolsList}   div-score=\x1b[32m${b.varianceReductionPct.toFixed(1)}\x1b[0m (from the live correlation matrix)`);
  });
  console.log("");

  // Monte-Carlo: MEASURED IL-variance reduction (not an assumption).
  const prices = lognormalPrices(5000, 0.4, 7);
  console.log("\x1b[36m═══ Monte-Carlo: measured IL-variance reduction (5000 scenarios, σ=0.40) ═══\x1b[0m");
  console.log("  Helix is IL insurance: before you know which slot you'll hold, pooling cuts your expected IL variance.");
  const basket = [
    { entryPrice: 0.7, size: 1000 },
    { entryPrice: 1.4, size: 1000 },
  ];
  for (const rho of [0.5, 1.0]) {
    const sim = simulateBasket(basket, rho, prices);
    console.log(
      `  ρ=${rho.toFixed(2)}  →  ex-ante IL variance falls \x1b[32m${sim.exAnteReductionPct.toFixed(0)}%\x1b[0m ` +
        `(ex-post per slot: ${sim.perMember.map((m) => m.reductionPct.toFixed(0) + "%").join(", ")})`,
    );
  }
  console.log("    → ex-post some slots win and some pay (zero-sum) — that's the insurance working, and ρ<1 keeps skin in the game.\n");
}

function keyToName(key: string): string {
  for (const [name, id] of Object.entries(POOLS)) if (id === key) return name;
  return key.slice(0, 8);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
