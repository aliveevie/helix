# Lovable prompt — Helix dApp UI

Copy everything inside the code block below into Lovable (or v0 / bolt). It is self-contained: network,
addresses, ABIs (viem human-readable), EIP-712 signing, flows, and the on-chain constraints.

---

````text
Build a polished, dark-themed Web3 dApp called "Helix" — a Uniswap v4 protocol that mutualizes
impermanent loss (IL) across a matched basket of LP positions. Use React + Vite + TypeScript, wagmi v2,
viem v2, and @tanstack/react-query. Wallet: the injected connector (MetaMask). Target network: Ethereum
Sepolia (chainId 11155111). Use viem `parseAbi` for the human-readable ABIs below.

DESIGN: deep navy/near-black background, an electric cyan→violet gradient accent with a soft glow,
monospace for all numbers/addresses, generous spacing, rounded cards with subtle 1px borders. A hero
header with the "Helix" wordmark and the tagline "Cross-Pool IL Mutualization for Uniswap v4". Make it
feel like a sharp, modern DeFi product. No Tailwind config gymnastics needed — hand-written CSS is fine.

NETWORK & PUBLIC RPC
- chainId: 11155111 (Sepolia)
- rpcUrl: https://ethereum-sepolia-rpc.publicnode.com
- Block explorer: https://sepolia.etherscan.io
- All reads should work without a wallet via a viem publicClient on that RPC. Writes need the wallet.

CONTRACT ADDRESSES (Sepolia, all source-verified on Sourcify)
- hook (HelixHook):           0x0E00cAc14C70Cf2EA46b33fe17E55Ac02DEb5640
- registry (Settlement):      0x8f450Fc17Fa1f84d8b69bC9816C543be503C8195
- reputation (ERC-8004):      0x7584Ec7599c39600b92d663B95fD1887ee48D87D
- breaker (CircuitBreaker):   0x7FBB5B8D97F1B562C7e2b1fDD30A3BEFBc7fBdf2
- oracle (MockOracle):        0x3334aeA99e7B838bCecb7b3931245052639D4599
- valueToken (USDV, 18 dec):  0x15cc1B894b3A3a668211B43172Ce034E2D7d5BAD

DEMO POOL (IMPORTANT)
- The only initialized pool is poolId =
  0xc5c1d554eeeae12d02e0f6096e9a28461c6df84e39c7976d3025a48c9ccda2e5
- submitMatch ONLY works against this poolId (other pools revert "HELIX: pool uninit"). Hardcode this
  poolId as the single selectable pool, labeled "ETH/USDC (demo)".

HUMAN-READABLE ABIs (viem parseAbi)

hookAbi = parseAbi([
  'function submitMatch((address lp,bytes32 pool,uint256 maxDriftBps,uint64 minDuration,uint128 maxSize,uint16 repFloor,uint256 nonce,uint64 deadline)[] intents, bytes[] signatures) returns (bytes32 matchId)',
  'function settle(bytes32 matchId)',
  'function cancelMatch(bytes32 matchId)',
  'function getMatch(bytes32 matchId) view returns ((bytes32 pool,uint64 createdAt,uint64 epochEnd,uint64 minDuration,uint16 rho,uint16 requiredRatioBps,uint32 enteredCount,uint8 status,uint8 pending,address[] lps,bytes32[] keys,uint256[] sizes))',
  'function nonceUsed(address lp, uint256 nonce) view returns (bool)',
  'function domainSeparatorV4() view returns (bytes32)',
  'function entryWindow() view returns (uint64)',
  'function owner() view returns (address)',
  'event MatchSubmitted(bytes32 indexed matchId, bytes32 indexed pool, address[] lps, uint256[] sizes, uint16 rho)',
  'event MatchSettled(bytes32 indexed matchId, uint256 p1, uint256 ilTotal, address settler)',
])

breakerAbi = parseAbi([
  'function state(bytes32 pool) view returns (uint8)',       // 0 NORMAL, 1 ELEVATED, 2 HALTED
  'function volIndex(bytes32 pool) view returns (uint256)',  // WAD (1e18)
])

reputationAbi = parseAbi([
  'function scoreOf(address lp) view returns (uint16)',       // 0..10000
])

registryAbi = parseAbi([
  'function marginOf(bytes32 matchId, address lp) view returns (uint256)', // WAD
  'function settlerFeeBps() view returns (uint16)',
  'function marginToken() view returns (address)',
])

valueTokenAbi = parseAbi([
  'function balanceOf(address) view returns (uint256)',
  'function decimals() view returns (uint8)',
  'function approve(address spender, uint256 amount) returns (bool)',
  'function mint(address to, uint256 amount)',   // open mint — for the testnet demo faucet
])

oracleAbi = parseAbi([
  'function price(bytes32 pool) view returns (uint256)',          // WAD
  'function setPrice(bytes32 pool, uint256 priceWad)',            // open — demo only
])

ENUMS
- Match status: 0 NONE, 1 PENDING, 2 OPEN, 3 SETTLED, 4 CANCELLED
- Breaker state: 0 NORMAL, 1 ELEVATED, 2 HALTED
- pending (RebalanceAction): 0 NONE, 1 RE_MATCH, 2 PAUSE, 3 RESUME

EIP-712 INTENT SIGNING (this is the core of the app)
An "intent" is an LP's off-chain signed commitment to be matched. Sign with viem's signTypedData:
  domain = { name: 'Helix', version: '1', chainId: 11155111, verifyingContract: hook }
  types  = { Intent: [
    { name: 'lp', type: 'address' },
    { name: 'pool', type: 'bytes32' },
    { name: 'maxDriftBps', type: 'uint256' },
    { name: 'minDuration', type: 'uint64' },
    { name: 'maxSize', type: 'uint128' },
    { name: 'repFloor', type: 'uint16' },
    { name: 'nonce', type: 'uint256' },
    { name: 'deadline', type: 'uint64' },
  ] }
  primaryType = 'Intent'
The signature is a 65-byte hex string. submitMatch takes parallel arrays: intents[] and signatures[].

VALIDATION RULES (mirror these client-side so submitMatch doesn't revert)
- A basket needs >= 2 intents, all with pool == the demo poolId, all distinct lp addresses.
- Each lp's nonce must be unused: check hook.nonceUsed(lp, nonce); auto-increment per lp.
- deadline must be in the future (e.g. now + 7 days, as a unix seconds bigint).
- maxSize, maxDriftBps, minDuration, repFloor are uint — enter maxSize in whole tokens and multiply by
  10^18 (it's a WAD uint128). repFloor 0 for the demo.
- The breaker must read NORMAL (0) or submitMatch reverts.

UNITS: every amount/price (maxSize, margin, volIndex, oracle price) is WAD = 1e18. Format with
viem formatUnits(value, 18). USDV has 18 decimals. NEVER JSON.stringify a bigint without a replacer.

SCREENS / FEATURES
1) Header: Helix wordmark + tagline, wallet connect (show address + ENS-less short form + chain), and a
   live circuit-breaker pill that reads breaker.state(demoPoolId) → NORMAL (green) / ELEVATED (amber) /
   HALTED (red), plus the volIndex formatted as a percentage.
2) Faucet card: a "Mint 10,000 USDV" button (valueToken.mint(userAddress, 10000e18)) and show the user's
   USDV balance. Note this is testnet play money.
3) Create Intent: a form (pool = the demo pool, fixed; maxDriftBps slider 500–5000; minDuration; maxSize
   in tokens; nonce auto-filled to the next unused). On submit, build the Intent and signTypedData. Show
   the resulting signature + the EIP-712 digest. Store signed intents in localStorage as an "intent
   mempool" (remember bigints need a custom serializer).
4) Matching: list the signed intents in the mempool. Let the user select >= 2 (distinct LPs) and click
   "Form basket & submit" → hook.submitMatch(intents, signatures). On success, save the returned matchId
   (read it from the MatchSubmitted event in the receipt) and link the tx to Etherscan.
   - SINGLE-USER DEMO HELP: most users only have one wallet. Add a "Generate counterparty" button that
     creates a throwaway in-browser signer with viem generatePrivateKey()/privateKeyToAccount(), and signs
     a second intent (with that key, its own address, nonce 0) so a single user can form a 2-LP basket.
5) Baskets: input or pick a matchId → hook.getMatch(matchId). Render: status (enum label), members (lps),
   epochEnd (countdown), rho (basis points → %), requiredRatioBps, enteredCount, and each member's margin
   via registry.marginOf. Add a "Cancel match" button (hook.cancelMatch) that is enabled only when the
   match is PENDING and block.timestamp > createdAt + entryWindow (read hook.entryWindow()).
6) Reputation: an address input → reputation.scoreOf(addr), rendered as a 0–10000 gradient meter.

ON-CHAIN CONSTRAINTS — DO NOT BUILD BROKEN BUTTONS
- submitMatch, cancelMatch, getMatch, the reads, mint, and setPrice all work from the browser.
- ENTERING a position and SETTLING are NOT callable from the browser in this demo: entry happens through
  the Uniswap v4 PoolManager's afterAddLiquidity callback (only the PoolManager can call the hook), which
  this mock setup doesn't expose to end users. So:
    • Do NOT add an "enter liquidity" button.
    • Show settle() as informational/disabled with a tooltip: "Settlement runs after the epoch once
      positions are entered via the v4 PoolManager — not available in this mock demo."
  Focus the interactive flow on: faucet → sign intents → form & submit basket → inspect basket → cancel.

POLISH
- Toasts for tx submitted/confirmed/failed with Etherscan links.
- Loading and empty states everywhere; never crash without a wallet (reads use the public RPC).
- A small "Contracts" footer listing the addresses, each linking to Sepolia Etherscan.
````

---

## Notes

- The **full JSON ABIs** (if you prefer them over the human-readable form) are in
  `packages/sdk/src/abis/*.json` in this repo.
- The demo pool is already configured (initialized + oracle price set), so `submitMatch` against it
  works immediately. New pools require the owner to call `setPoolConfig` and are out of scope for the UI.
- For a fully scripted reference of the same flows, see `packages/sdk` (`HelixClient`, `signIntent`).
