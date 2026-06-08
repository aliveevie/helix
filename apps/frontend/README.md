# Helix — Demo Frontend

A polished, dark-themed single-page app for **Helix**, a Uniswap v4 hook protocol that
**mutualizes impermanent loss (IL)** across a matched basket of LP positions.

LPs sign an off-chain **EIP-712 intent**; a permissionless matching engine pairs compatible
intents into a **basket**; at settlement the protocol redistributes value so every member converges
toward the basket's capital-weighted average IL (zero-sum, self-funded from posted margins). A
**Reactive Smart Contract** auto-rebalances or pauses baskets when volatility / correlation drifts.

Components surfaced here: `HelixHook`, `SettlementRegistry`, `ReputationAccumulator` (ERC-8004),
`CircuitBreaker` (NORMAL / ELEVATED / HALTED).

This app consumes the workspace SDK [`@helix/sdk`](../../packages/sdk) for intent building/signing,
the typed `HelixClient`, and the contract ABIs.

## Features

- **Header** — Helix wordmark + tagline, wallet connect (address + chain), live circuit-breaker
  status pill (reads `breakerState`).
- **Create Intent** — form → `buildIntent` → `signIntent` (EIP-712). Shows the digest + signature
  and stores signed intents in a local **mempool** (persisted to `localStorage`).
- **Mempool · Matching** — select ≥2 compatible (same-pool) intents → `submitMatch`. With no wallet
  / unconfigured contracts it **simulates** and shows the exact payload that would be submitted.
- **Baskets** — track matchIds (from submissions + a manual "load matchId" input), read live status
  via `getMatch` (PENDING / OPEN / SETTLED), members, epoch end, ρ correlation; `settle` button for
  expired open baskets.
- **Reputation** — address → `scoreOf`, rendered as a 0–1000 score with tier.

## Mock mode (no chain required)

The app **always runs** — `pnpm dev` and `pnpm build` work with no wallet and no deployed
contracts. When core addresses are still the zero-address placeholders (the default in
[`deployments.json`](./deployments.json)), or a read reverts, the UI transparently falls back to
**deterministic mock data** and clearly labels it `mock`. Writes are simulated. The app never
crashes on a missing wallet or chain.

To go **live**, set the contract address env vars (below) and connect an injected wallet on the
target chain.

## Running

```bash
# from the repo root, install just this app's deps:
cd apps/frontend
pnpm install

pnpm dev        # start the dev server (http://localhost:5173)
pnpm build      # tsc -b + vite build  →  dist/
pnpm preview    # serve the production build
pnpm typecheck  # tsc --noEmit (strict)
```

> The `@helix/sdk` workspace package must be built (its `dist/` is present in this repo). If you
> change the SDK, rebuild it with `pnpm --filter @helix/sdk build`.

## Configuration / env vars

Copy `.env.example` → `.env.local` and fill in. Everything is optional; unset values fall back to
`deployments.json` (all zero ⇒ mock mode). See [`src/config.ts`](./src/config.ts).

| Env var                      | Default                        | Purpose                                            |
| ---------------------------- | ------------------------------ | -------------------------------------------------- |
| `VITE_CHAIN_ID`              | `31337`                        | Target chain id. `31337` = local anvil/foundry.    |
| `VITE_CHAIN_NAME`            | `Unichain Sepolia`             | Display name for a non-foundry chain.              |
| `VITE_NATIVE_NAME`           | `Ether`                        | Native currency name.                              |
| `VITE_NATIVE_SYMBOL`         | `ETH`                          | Native currency symbol.                            |
| `VITE_RPC_URL`               | `http://127.0.0.1:8545`        | RPC endpoint for the target chain.                 |
| `VITE_ANVIL_RPC_URL`         | `http://127.0.0.1:8545`        | RPC for the always-available local anvil chain.    |
| `VITE_EXPLORER_NAME`         | `Explorer`                     | Block explorer name.                               |
| `VITE_EXPLORER_URL`          | `https://sepolia.uniscan.xyz`  | Block explorer base URL.                           |
| `VITE_HOOK_ADDRESS`          | `0x0…0`                        | `HelixHook` address.                               |
| `VITE_REGISTRY_ADDRESS`      | `0x0…0`                        | `SettlementRegistry` address.                      |
| `VITE_REPUTATION_ADDRESS`    | `0x0…0`                        | `ReputationAccumulator` address.                   |
| `VITE_BREAKER_ADDRESS`       | `0x0…0`                        | `CircuitBreaker` address.                          |
| `VITE_ORACLE_ADDRESS`        | `0x0…0`                        | Oracle address.                                    |
| `VITE_VALUE_TOKEN_ADDRESS`   | `0x0…0`                        | Value/margin token (for `approveMargin`).          |
| `VITE_POOL_MANAGER_ADDRESS`  | `0x0…0`                        | Uniswap v4 `PoolManager` (optional).               |

Addresses can also be edited directly in [`deployments.json`](./deployments.json), which `config.ts`
imports as the fallback layer beneath the env vars.

The app keeps the **foundry / anvil** chain (id `31337`) available as a secondary chain so you can
develop against a local node regardless of the configured target.

## Notes

- **bigint** values (WAD `1e18` margins, sizes, nonces, deadlines) are formatted for display and
  serialized to `localStorage` with a bigint-safe replacer/reviver — never raw `JSON.stringify`.
- No secrets or private keys live in this codebase. Signing happens entirely through the connected
  wallet.

## Stack

Vite · React 18 · TypeScript (`strict`) · wagmi v2 · viem v2 · @tanstack/react-query v5. Hand-written
dark theme CSS (no Tailwind, no component library).
