import type { HelixAddresses } from "@helix/sdk";
import { defineChain } from "viem";
import { foundry } from "viem/chains";
import deployments from "../deployments.json";

/**
 * Helix frontend configuration.
 *
 * Everything here is overridable via `VITE_*` env vars (see README). Defaults
 * fall back to the zero-address placeholders in `deployments.json`, which means
 * the app boots cleanly with NO chain connection (mock mode).
 */

const ZERO = "0x0000000000000000000000000000000000000000" as const;

type Hex = `0x${string}`;

function envAddr(key: string, fallback: string): Hex {
  const v = import.meta.env[key as keyof ImportMetaEnv] as string | undefined;
  const candidate = (v && v.length > 0 ? v : fallback) || ZERO;
  // Loose validation: must look like a 20-byte hex address.
  if (/^0x[0-9a-fA-F]{40}$/.test(candidate)) return candidate as Hex;
  return ZERO;
}

function envStr(key: string, fallback: string): string {
  const v = import.meta.env[key as keyof ImportMetaEnv] as string | undefined;
  return v && v.length > 0 ? v : fallback;
}

function envNum(key: string, fallback: number): number {
  const v = import.meta.env[key as keyof ImportMetaEnv] as string | undefined;
  const n = v ? Number(v) : NaN;
  return Number.isFinite(n) ? n : fallback;
}

// --- Chain ---------------------------------------------------------------

export const TARGET_CHAIN_ID = envNum("VITE_CHAIN_ID", deployments.chainId ?? 31337);

const RPC_URL = envStr("VITE_RPC_URL", "http://127.0.0.1:8545");

/**
 * A configurable "Unichain Sepolia"-like chain. When `VITE_CHAIN_ID` matches
 * foundry's 31337 we expose anvil directly; otherwise we synthesize a custom
 * chain from the env so the app can target any testnet without code changes.
 */
export const helixChain =
  TARGET_CHAIN_ID === foundry.id
    ? { ...foundry, rpcUrls: { default: { http: [RPC_URL] } } }
    : defineChain({
        id: TARGET_CHAIN_ID,
        name: envStr("VITE_CHAIN_NAME", "Unichain Sepolia"),
        nativeCurrency: {
          name: envStr("VITE_NATIVE_NAME", "Ether"),
          symbol: envStr("VITE_NATIVE_SYMBOL", "ETH"),
          decimals: 18,
        },
        rpcUrls: { default: { http: [RPC_URL] } },
        blockExplorers: {
          default: {
            name: envStr("VITE_EXPLORER_NAME", "Explorer"),
            url: envStr("VITE_EXPLORER_URL", "https://sepolia.uniscan.xyz"),
          },
        },
        testnet: true,
      });

// We always also support local anvil for convenience.
export const anvilChain = {
  ...foundry,
  rpcUrls: { default: { http: [envStr("VITE_ANVIL_RPC_URL", "http://127.0.0.1:8545")] } },
};

// De-duplicate in case the target IS foundry.
export const SUPPORTED_CHAINS =
  helixChain.id === anvilChain.id
    ? ([helixChain] as const)
    : ([helixChain, anvilChain] as const);

// --- Addresses -----------------------------------------------------------

const d = deployments.addresses;

export const ADDRESSES: HelixAddresses = {
  hook: envAddr("VITE_HOOK_ADDRESS", d.hook),
  registry: envAddr("VITE_REGISTRY_ADDRESS", d.registry),
  reputation: envAddr("VITE_REPUTATION_ADDRESS", d.reputation),
  breaker: envAddr("VITE_BREAKER_ADDRESS", d.breaker),
  oracle: envAddr("VITE_ORACLE_ADDRESS", d.oracle),
  valueToken: envAddr("VITE_VALUE_TOKEN_ADDRESS", d.valueToken),
  poolManager: envAddr("VITE_POOL_MANAGER_ADDRESS", d.poolManager ?? ZERO),
};

/** True when the core contracts are still placeholders → run in mock mode. */
export const ADDRESSES_CONFIGURED =
  ADDRESSES.hook !== ZERO &&
  ADDRESSES.registry !== ZERO &&
  ADDRESSES.reputation !== ZERO &&
  ADDRESSES.breaker !== ZERO;

// --- Demo pools ----------------------------------------------------------

/** Pre-baked pool ids for the demo's pool selector (bytes32). */
export interface DemoPool {
  id: Hex;
  label: string;
}

export const DEMO_POOLS: DemoPool[] = [
  {
    id: "0x1111111111111111111111111111111111111111111111111111111111111111",
    label: "ETH / USDC · 0.05%",
  },
  {
    id: "0x2222222222222222222222222222222222222222222222222222222222222222",
    label: "WBTC / ETH · 0.30%",
  },
  {
    id: "0x3333333333333333333333333333333333333333333333333333333333333333",
    label: "UNI / ETH · 0.30%",
  },
  {
    id: "0x4444444444444444444444444444444444444444444444444444444444444444",
    label: "DAI / USDC · 0.01%",
  },
];
