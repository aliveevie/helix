# Helix — Intent Hub (UI)

Front-end for **Helix**, a Uniswap v4 hook that mutualizes impermanent loss across matched LP baskets.
Sign EIP-712 intents, match permissionlessly, and inspect baskets — wired to the **live Sepolia**
deployment. Built with TanStack Start + React 19, wagmi v2 / viem v2, Tailwind v4 and shadcn/ui.

## Run locally

> Use **npm** (the original `bun.lock` pinned Lovable's private package registry, which 403s outside
> the Lovable sandbox; `package-lock.json` makes the project installable anywhere).

```bash
npm install
npm run dev      # http://localhost:8080
npm run build    # production build (client + SSR)
```

Connect an injected wallet (MetaMask) on **Sepolia**. Reads work without a wallet via a public RPC.

## Live contracts (Sepolia, chainId 11155111)

Configured in `src/lib/helix/config.ts`, all source-verified on Sourcify.

| Contract | Address |
| --- | --- |
| HelixHook | `0x0E00cAc14C70Cf2EA46b33fe17E55Ac02DEb5640` |
| SettlementRegistry | `0x8f450Fc17Fa1f84d8b69bC9816C543be503C8195` |
| ReputationAccumulator | `0x7584Ec7599c39600b92d663B95fD1887ee48D87D` |
| CircuitBreaker | `0x7FBB5B8D97F1B562C7e2b1fDD30A3BEFBc7fBdf2` |
| MockOracle | `0x3334aeA99e7B838bCecb7b3931245052639D4599` |
| Value token (USDV, 18-dec) | `0x15cc1B894b3A3a668211B43172Ce034E2D7d5BAD` |

Demo pool (the only initialized pool; `submitMatch` targets it):
`0xc5c1d554eeeae12d02e0f6096e9a28461c6df84e39c7976d3025a48c9ccda2e5`

## What you can do in the UI

- **Faucet** — mint test USDV.
- **Create Intent** — sign an EIP-712 matching intent (stored in a local mempool).
- **Matching** — select ≥2 intents from distinct LPs and `submitMatch` on-chain. "Generate counterparty"
  creates a throwaway in-browser signer so a single wallet can form a 2-LP basket.
- **Baskets** — look up a `matchId`, view status/members/epoch/ρ/margins, and `cancelMatch` a stuck
  PENDING basket after its entry window.
- **Reputation** — read any address's ERC-8004 score.
- Live **circuit-breaker** status pill.

Entering a position and settlement run through the Uniswap v4 PoolManager's `afterAddLiquidity` callback
and aren't user-callable from the browser in this mock deployment — those actions are shown as
informational.

## Protocol / contracts

The Solidity core, tests, matching engine, SDK and deploy scripts live in the main Helix repo.
