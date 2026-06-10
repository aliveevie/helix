# Helix — Slide Deck

> One file, one slide per section. Each slide has **Title**, **On-slide content**, and **Speaker notes**.
> Target length ≈ 6–7 minutes + 2-minute live demo. Live demo: https://helix-ui-five.vercel.app ·
> Repo: https://github.com/aliveevie/helix

---

## Slide 1 — Title

**Title:** Helix

**On-slide content:**
- **Mutual insurance for impermanent loss, built into Uniswap v4.**
- LPs pool their IL risk through signed intents — zero-sum, self-funded, no insurance fund, no perps.
- Live on Sepolia · github.com/aliveevie/helix · helix-ui-five.vercel.app

**Speaker notes:**
> Helix is a Uniswap v4 hook that turns impermanent loss from something every LP suffers alone into a
> risk they can pool — like mutual insurance. Everything I'll show is live: deployed and verified on
> Sepolia, with a working app you can open right now. Let me start with the problem.

---

## Slide 2 — The problem

**Title:** Every LP eats impermanent loss alone

**On-slide content:**
- Providing liquidity means taking on IL — the gap between holding and pooling when price moves.
- Today's hedges each carry a cost: perps and options need margin, a counterparty, and active management;
  insurance funds need a capitalized treasury and a token; dynamic-fee hooks only adjust the fee.
- None let LPs simply **share** the risk with each other.

**Speaker notes:**
> IL is the core risk of being an LP, and the tools to manage it are heavy. You can short a perp, buy an
> option, or rely on a protocol's insurance treasury — all of which add cost, complexity, or a token to
> trust. What's missing is the simplest idea in insurance: a group of people exposed to the same kind of
> risk pooling it so no single member takes the full hit.

---

## Slide 3 — The idea

**Title:** Pool the loss, converge to the average

**On-slide content:**
- LPs sign an off-chain **intent**; a permissionless engine matches them into a **basket**.
- At settlement, the hook redistributes value so each member converges to the basket's
  **capital-weighted average IL** instead of absorbing its own in full.
- **Zero-sum** within the basket · **self-funded** from posted margins · capital never leaves Uniswap.

**Speaker notes:**
> The mechanism is straightforward. You sign an intent describing the kind of match you want. An engine
> pairs you with others into a basket. Over an epoch the hook tracks each member's IL, and at settlement
> it moves value between members so everyone ends up near the basket average. The member who got unlucky
> is compensated by the member who got lucky. It nets to zero inside the basket and it's funded entirely
> by margins the members post up front — no external pool, and your liquidity stays in the Uniswap pool
> the whole time.

---

## Slide 4 — How it works

**Title:** Match → Enter → Monitor → Settle

**On-slide content:**
1. **Intent** — LP signs an EIP-712 intent (pool, max drift, size, duration, reputation floor).
2. **submitMatch** — anyone submits a basket; the hook re-verifies every signature and constraint on-chain.
3. **Enter** — `afterAddLiquidity` snapshots the position and escrows a settlement margin.
4. **Monitor** — `afterSwap` feeds a TWAP + a circuit breaker; a Reactive contract watches volatility.
5. **Settle** — after the epoch, anyone settles; IL is computed and redistributed; a small settler fee is paid.

**Speaker notes:**
> Four steps. Intents are signed off-chain, so matching is cheap and permissionless — but the hook
> re-checks every signature, deadline, and constraint on-chain, so a bad or malicious matching engine
> can only produce matches the hook rejects. Entry snapshots the position and locks a margin. While the
> basket is open, every swap updates a price accumulator and feeds a volatility breaker. After the epoch
> anyone can trigger settlement and earn a small fee for doing it — the protocol never depends on a
> privileged operator.

---

## Slide 5 — The accounting

**Title:** Zero-sum by construction

**On-slide content:**
```
ILᵢ          = V_hold(P1) − V_pool(P1)        (≥ 0, per member)
IL_fairᵢ     = wᵢ · Σ ILⱼ                      (capital-weighted share)
adjustmentᵢ  = ρ · (ILᵢ − IL_fairᵢ)           (worse-than-fair ⇒ receives)
Σ adjustmentᵢ = 0                              (exactly)
```
- ρ tunes how much risk is pooled: ρ=1 → everyone realizes the basket average; ρ<1 → keep skin in the game.
- Settlement is **solvency-bounded**: ρ is capped to the posted margins, so a settlement can never under-fund a member.

**Speaker notes:**
> The redistribution is one clean formula. Each member's adjustment is rho times the difference between
> their own IL and their fair share, and those adjustments sum to exactly zero — that's the guarantee
> that it's self-funded. Rho is the dial: at one, every member converges to the same average; below one,
> they keep part of their own outcome, which preserves the incentive to manage their position. And there's
> a safety bound — at settlement we cap rho to whatever the posted margins can actually fund, so the
> system can never promise more than it holds.

---

## Slide 6 — The value, quantified

**Title:** Three LPs, one outcome

**On-slide content:**
```
LP      entry price   standalone IL        after pooling (ρ=1)
A       1.00          0.45%
B       2.00          2.54%        →        all three: 6.02%
C       0.50          15.08%
IL-rate variance across members:  417,396  →  0   (eliminated)
```
- **Ex-ante** (before you know which position you'll hold): pooling cuts expected IL variance **40–54%**
  (Monte-Carlo, 5,000 scenarios).
- Settlement payouts equal posted margins to the wei — conservation holds on-chain.

**Speaker notes:**
> Here's it working with real numbers from the contract. Three LPs entered the same pool at very
> different prices, so at settlement their losses range from under half a percent to fifteen percent.
> After pooling at rho one, all three realize the same six percent — the basket average. The spread
> between members collapses to zero. And if you simulate it across thousands of price paths, before you
> know whether you'll be the lucky or the unlucky LP, joining a basket cuts your expected IL variance by
> forty to fifty-four percent. That's the insurance, measured — not assumed.

---

## Slide 7 — Cross-pool hedging

**Title:** Diversify across assets, not just timing

**On-slide content:**
- A basket can span **multiple pools** — each member priced at its own pool, mutualized together.
- The matching engine uses a live correlation matrix to pair **anti-correlated** assets:
  - ETH/USDC + ARB/USDC → diversification score **47**
  - ETH/USDC + WBTC/USDC → score **3** (move together, little benefit)
- A real cross-pool basket spanning ETH/USDC + ARB/USDC is live on-chain.

**Speaker notes:**
> Pooling within one pool already helps. But the bigger lever is pooling across assets that don't move
> together. A basket in Helix can span different pools, each member priced against its own market, and
> the engine deliberately pairs anti-correlated assets — pooling ETH with ARB is far more protective than
> pooling ETH with WBTC, because the first pair hedges and the second just moves together. There's a live
> basket on Sepolia right now that spans two different pools in a single match.

---

## Slide 8 — Architecture

**Title:** Four planes, one hook

**On-slide content:**
- **Liquidity** — canonical Uniswap v4 pools (Helix never moves LP capital).
- **Accounting** — the hook, a settlement registry, and an **ERC-8004** reputation registry.
- **Control** — a hysteresis circuit breaker + a **Reactive Network** contract for volatility/correlation.
- **Coordination** — the off-chain matching engine + SDK (no on-chain authority).
- Prices cross-check **Chainlink** against the pool TWAP and reject settlement on divergence.

**Speaker notes:**
> The system separates cleanly into four planes. Liquidity stays in the canonical Uniswap pools — we only
> observe it. The accounting plane holds match state, margins, and reputation, where reputation is a
> conformant ERC-8004 registry. The control plane decides when matching and settlement are allowed: a
> circuit breaker with hysteresis, plus a Reactive Network contract that watches volatility and
> correlation across chains and can pause or re-match a basket. And the coordination plane — the engine
> and SDK — has no special powers; it just proposes matches the hook independently verifies.

---

## Slide 9 — Safety

**Title:** Guarantees, not hopes

**On-slide content:**
- **Conservation** — payouts never exceed escrowed margins (fuzzed + invariant-tested, incl. cross-pool).
- **Exact zero-sum** redistribution; **settlement idempotency**; **margin solvency** at all times.
- **Solvency-bounded ρ** — settlement can't under-fund a member.
- **Oracle-resistant** — Chainlink vs TWAP divergence guard; hysteresis breaker; Reactive auto-pause.
- 41 Foundry tests (unit · fuzz · invariant · integration) + a real-PoolManager fork lifecycle.

**Speaker notes:**
> Because this moves real value between people, the properties are enforced, not assumed. Conservation —
> the contract can never pay out more than it took in — is proven by fuzzing and long invariant runs,
> including across cross-pool baskets. Redistribution sums to zero exactly, settlement can't run twice,
> and margins always back the obligations. Prices are cross-checked between Chainlink and the pool's own
> TWAP, and settlement reverts if they disagree. All of it is covered by forty-one tests plus a fork test
> that runs the entire lifecycle against the real Uniswap v4 PoolManager.

---

## Slide 10 — Live on-chain

**Title:** Deployed, verified, working

**On-slide content:**
- All contracts on **Sepolia**, source-verified on Sourcify. Hook: `0x6704…d640`.
- Live **ChainlinkOracle** reading the real ETH/USD feed.
- Live **cross-pool basket** formed via permissionless `submitMatch` (one basket, two pools).
- Live **Reactive** contract on Lasna, subscribed to the hook's events; callbacks authorized on Sepolia.
- App: **helix-ui-five.vercel.app** · Records: `deployments/sepolia.json`

**Speaker notes:**
> None of this is a mock. Every contract is deployed and verified on Sepolia. The oracle is reading a real
> Chainlink ETH/USD feed. There's a real cross-pool basket that was formed permissionlessly on-chain. The
> Reactive contract is deployed on the Reactive testnet, subscribed to the hook's events, and the hook is
> wired to accept its callbacks — so the auto-rebalance loop is live end to end. And there's a deployed
> app, which I'll show you now.

---

## Slide 11 — Demo

**Title:** Live walkthrough

**On-slide content:**
- **App:** helix-ui-five.vercel.app (Sepolia)
- Flow: connect wallet → mint test USDV → sign an intent → generate a counterparty → **submitMatch** (real tx)
- Inspect the basket: status, members, per-pool, margins.
- **The value loop:** `forge test --match-contract Showcase -vv` → watch IL converge to the basket average.

**Speaker notes (demo script — ~2 min):**
> 1. **(20s)** Open the app on Sepolia, connect a wallet, and mint some test USDV from the faucet card.
> 2. **(30s)** Go to Create Intent — pick the demo pool, set a drift bound and size, and sign. The intent
>    appears in the local mempool with its EIP-712 signature.
> 3. **(20s)** Hit "Generate counterparty" so a single wallet can form a two-member basket, then select
>    both and click submitMatch. That's a real transaction — open it on Etherscan.
> 4. **(20s)** Load the resulting match: it shows two members across two pools, with margins escrowed.
> 5. **(30s)** Now the money shot — run the Showcase test. Three LPs enter at very different prices, the
>    price moves, settlement runs, and you watch their wildly different impermanent losses collapse onto
>    the single basket-average number, conservation checked to the wei.
>
> *Fallback if the network is slow:* show the already-on-chain cross-pool match (in `deployments/sepolia.json`)
> on Etherscan, and run the Showcase test locally — it needs no network.

---

## Slide 12 — Roadmap

**Title:** From testnet to production

**On-slide content:**
- **Cross-chain baskets** — coordinate settlement across chains via Circle CCTP (specified; next build).
- **Concentrated-liquidity IL** — extend the model from full-range to tick-range positions, plus a fee term.
- **Deeper matching** — richer correlation/variance optimization and reputation-weighted priority.
- **Audits + mainnet** — formalize the invariants and harden for a production deployment.

**Speaker notes:**
> The core is live; here's the path forward. The Reactive contract already coordinates across chains, so
> the natural next step is cross-chain baskets settling value with Circle's CCTP. The IL model today uses
> a clean full-range baseline for relative redistribution — extending it to concentrated, tick-range
> positions and adding a fee term makes it match exactly what active v4 LPs run. Then deeper matching,
> formal audits, and mainnet.

---

## Slide 13 — Close

**Title:** Helix

**On-slide content:**
- **Mutual insurance for impermanent loss, native to Uniswap v4.**
- Permissionless · self-funded · zero-sum · cross-pool · live on Sepolia.
- **helix-ui-five.vercel.app** · **github.com/aliveevie/helix**

**Speaker notes:**
> To sum up: Helix lets Uniswap LPs pool impermanent loss like mutual insurance — permissionless,
> self-funded, conservation-guaranteed, and already live across Uniswap v4, Chainlink, ERC-8004, and the
> Reactive Network. The app and the full repo are on screen. Thank you.
