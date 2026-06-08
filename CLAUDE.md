# CLAUDE.md

Guidance for working in this repo. Helix = a Uniswap v4 hook that mutualizes impermanent loss across
matched baskets, with a Reactive Smart Contract for auto-rebalancing. See `README.md` for the full
picture; this file captures the non-obvious operational facts.

## Layout

- `contracts/` — Foundry project (Solidity 0.8.26). The protocol core.
- `packages/sdk/` — `@helix/sdk` (EIP-712 intents, ABIs, viem client).
- `packages/matching-engine/` — `@helix/matching-engine` (correlation + basket optimizer + CLI).
- `apps/frontend/` — `@helix/frontend` (Vite + React + wagmi).

## Build & test

```bash
# Contracts — deps are vendored via shallow clone and gitignored; run setup.sh after a fresh checkout.
cd contracts && ./setup.sh && forge test          # 30 tests + 2 fork tests (skipped without RPC)

# JS workspace (pnpm)
pnpm install
pnpm --filter @helix/sdk test
pnpm --filter @helix/matching-engine test
pnpm --filter @helix/matching-engine start         # offline demo
pnpm --filter @helix/frontend build
```

## Things that will bite you

- **`via_ir = true` is required** (`contracts/foundry.toml`). `submitMatch` and `applyRedistribution`
  hit stack-too-deep without it. Keep it on.
- **`contracts/lib/` is gitignored.** A fresh checkout has no dependencies — run `contracts/setup.sh`
  (clones forge-std, v4-core, v4-periphery, openzeppelin, solmate). CI does this too.
- **Only `v4-core` types/interfaces/libraries are compiled** — never `PoolManager`. Tests drive the
  hook callbacks through `MockPoolManager`, a faithful `extsload` stand-in. Don't import periphery’s
  moving `BaseHook`; use the vendored `src/base/BaseHook.sol`.
- **Foundry test strings must be ASCII.** Non-ASCII (e.g. `Σ`) needs `unicode"..."` or it won't compile.
- **EIP-712 parity is load-bearing.** `IntentLib.INTENT_TYPEHASH` (Solidity) and `IntentEip712Types`
  (SDK `packages/sdk/src/types.ts`) must stay byte-identical in field order and types, or on-chain
  signature recovery fails. The domain is `("Helix", "1")`.
- **ABIs are generated**, not hand-written: `forge inspect <C> abi --json > packages/sdk/src/abis/<C>.json`.
  Regenerate after changing a contract's external interface.
- **Hook address encodes permissions.** Tests `deployCodeTo` at `address(uint160(FLAGS) | (0x4444 << 144))`;
  the deploy script CREATE2-mines a matching address via `HookMiner`. FLAGS = afterInitialize |
  afterAddLiquidity | beforeRemoveLiquidity | afterSwap.

## Accounting invariants (don't break these)

- Conservation: registry pays out ≤ escrowed (exact at 18-dec token, where `scale == 1`).
- `Mutualization.adjustments` sums to **exactly** zero (residual swept to the last member).
- Sign convention: `adjustmentᵢ = ρ·(ILᵢ − IL_fairᵢ)` — worse-than-fair IL *receives*.
- Settler fee is paid as `Σ` per-member contributions, never the headline `feeWad` (rounding safety).

All four are covered by `test/fuzz` and `test/invariant`; rerun them after touching the registry or
mutualization math.
