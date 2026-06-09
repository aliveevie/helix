# Helix — one-page pitch

**A Uniswap v4 hook that turns impermanent loss from a solo gamble into mutual insurance.**

## The problem
Every Uniswap LP eats impermanent loss alone. Today's "fixes" make it worse: perps and options need
margin, expertise, and a counterparty; insurance funds need a capitalized treasury and a token; dynamic-fee
hooks only nudge the fee. None of them let LPs *pool their risk*.

## The solution
LPs sign an off-chain **EIP-712 intent**. A permissionless engine matches them into a **basket** — ideally
across **anti-correlated pools**. The hook tracks each member's IL over an epoch and, at settlement,
**redistributes value so every member converges to the basket's capital-weighted average IL**. It's
**zero-sum** within the basket, **self-funded** from settlement margins, needs **no insurance fund, no
perps, no token, no operator**, and **never moves LP capital** out of Uniswap.

> **It's IL insurance.** *Ex-ante* — before you know whether you'll be the lucky or unlucky LP — pooling
> cuts your expected IL variance by a measured **40–54%**. *Ex-post* it's zero-sum: some win, some pay. At
> moderate ρ the trade is **Pareto-improving for both sides**.

## Why it wins (proof, not promises)

| Claim | Evidence (run it) |
| --- | --- |
| It actually works against **real Uniswap v4** | Fork test drives `initialize → afterAddLiquidity → swap → settle` against the canonical Sepolia `PoolManager` (`0xE03A1074…`). `FORK_RPC_URL=… forge test --match-test test_fork_fullLifecycle…` |
| The value loop is **visible & real** | `forge test --match-contract Showcase -vv`: 3 LPs with IL of 0.45% / 2.54% / **15.08%** all converge to **6.02%**; variance 417 396 → 0; on-chain `settle` conserves value. |
| It's genuinely **cross-pool** (the name) | A basket spans pools; each member priced at its own pool; the engine **uses the correlation matrix** to pair anti-correlated assets (ARB↔ETH ≈ 47 vs ETH↔WBTC ≈ 3). `test/unit/CrossPool.t.sol` |
| The demand is **measured** | Monte-Carlo (`simulate.ts`): ex-ante IL-variance −40% to −54%, honest about ex-post asymmetry. |
| It's **safe** | 41 Foundry tests incl. fuzz + invariants: conservation, exact zero-sum, **solvency-bounded ρ**, margin solvency, settlement idempotency; oracle-divergence guard; hysteresis circuit breaker; RSC auto-pause. |
| It's **live** | All contracts deployed + **Sourcify-verified on Sepolia**; a real permissionless `submitMatch` on-chain; a **live `ChainlinkOracle`** reading the real ETH/USD feed. |

## Ecosystem fit (UHI)
Maps squarely onto the **Impermanent Loss & Yield Systems** theme. Stacks integrations that are *real*, not
namedropped: **Uniswap v4 hook** (load-bearing), **Chainlink** (live feed), **ERC-8004** (conformant
reputation registry: tagged, revocable feedback + aggregation), **Reactive Network** (vol/correlation RSC
with authenticated `triggerRebalance`).

## 3-minute demo
1. **Problem** (20s) — LPs fear IL; hedges need perps/options/funds.
2. **Live** (40s) — connect → mint USDV → sign intent → generate counterparty → real `submitMatch` on the
   Sourcify-verified hook.
3. **Money shot** (60s) — `Showcase`/fork: two LPs enter, price moves, `settle`; watch IL converge to the
   basket average and variance collapse — real numbers.
4. **Safety** (30s) — `forge test` green: conservation, zero-sum, solvency-bound, breaker, RSC.
5. **Why it wins** (15s) — permissionless, self-funded, cross-pool, production pathway; the only IL
   mutualization primitive that lives entirely inside Uniswap.

*Repo:* `README.md` · *deploys:* `deployments/sepolia.json` · *UI:* `docs/LOVABLE_PROMPT.md`
