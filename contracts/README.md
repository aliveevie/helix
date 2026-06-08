# Helix Contracts

Solidity 0.8.26 · Foundry · Uniswap v4-core types.

## Layout

```
src/
  HelixHook.sol             v4 hook: matching, entry, settlement, RSC callback
  SettlementRegistry.sol    margin escrow + zero-sum, conservation-checked redistribution
  ReputationAccumulator.sol ERC-8004-aligned reputation registry
  CircuitBreaker.sol        per-pool volatility FSM with hysteresis
  base/BaseHook.sol         self-contained v4 hook base (PoolManager-gated callbacks)
  libraries/
    HelixTypes.sol          structs / enums / constants
    ILMath.sol              closed-form CPMM impermanent-loss math
    Mutualization.sol       ρ-weighted, exactly-zero-sum redistribution
    IntentLib.sol           EIP-712 intent hashing
  interfaces/               IHelixHook, ISettlementRegistry, IReputation, ICircuitBreaker, IHelixOracle
  reactive/                 ReactiveLib (vendored RN surface) + HelixReactive (the RSC)
  mocks/                    MockERC20, MockOracle, MockPoolManager (extsload-faithful)
script/Deploy.s.sol         CREATE2 hook-address mining + full wiring
test/                       unit · fuzz · invariant
```

## Setup & test

```bash
./setup.sh          # vendors forge-std, v4-core, v4-periphery, openzeppelin, solmate into lib/
forge build
forge test          # 31 tests: unit, fuzz, invariant, integration
forge test --gas-report
FOUNDRY_PROFILE=deep forge test --match-path "test/invariant/*"   # deeper invariant campaign
```

## Dependency strategy

The hook is built against **stable `v4-core` types, interfaces and libraries only** (`IPoolManager`,
`IHooks`, `Hooks`, `StateLibrary`, `PoolKey`/`PoolId`, `BalanceDelta`). The heavy `PoolManager`
implementation is never compiled — the suite drives the hook callbacks directly through a faithful
`extsload`-backed `MockPoolManager`, keeping builds fast and deterministic and avoiding the
moving-target churn of `v4-periphery` (whose `BaseHook` we vendor a minimal equivalent of).

## Enforced invariants

| Invariant | Where |
| --- | --- |
| Conservation — `Σ payouts ≤ Σ margins (+ surplus)` | `SettlementRegistry`, `test/invariant`, `test/fuzz` |
| Zero-sum redistribution — `Σ adjustments == 0` exactly | `Mutualization`, `test/unit/MathUnit` |
| Margin solvency — escrow backs every live obligation | `test/invariant` |
| Settlement idempotency — a `SETTLED` match can't re-settle | `SettlementRegistry`, `test/invariant` |
| Oracle resistance — revert if `|Δchainlink−twap| > δ` | `HelixHook.settle`, `test/unit/ControlPlane` |

## Modeling notes

- **IL model.** Each matched position is valued as a 50/50 constant-product LP. IL is the closed form
  `V_hold(P1) − V_pool(P1) = (x0·P1 + y0) − 2·√(x0·y0·P1)`, always ≥ 0, used purely for *relative*
  redistribution inside a basket. Domain: notional ≤ 1e27 WAD, price ∈ [1e-3, 1e3].
- **Value units.** The registry tracks margins in WAD and converts to the token at transfer boundaries
  with `scale = 10^(18−decimals)`, always rounding payouts **down** (so out ≤ in). With an 18-decimal
  value token, `scale == 1` and conservation is exact.
- **Sign convention.** `adjustmentᵢ = ρ·(ILᵢ − IL_fairᵢ)`: a member whose realized IL was *worse* than
  its capital-weighted fair share receives a positive adjustment (compensation); effective IL becomes
  `(1−ρ)·ILᵢ + ρ·IL_fairᵢ` — the basket average at `ρ = 1`.
