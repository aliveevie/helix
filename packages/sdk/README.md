# @helix/sdk

TypeScript client SDK for Helix — EIP-712 matching-intent signing, generated ABIs, and a typed viem
client over the on-chain surface.

```bash
pnpm --filter @helix/sdk build
pnpm --filter @helix/sdk test
```

## Use

```ts
import { buildIntent, signIntent, HelixClient, helixDomain } from "@helix/sdk";

// 1) Build + sign an intent (EIP-712 domain = ("Helix","1"), verifyingContract = the hook).
const intent = buildIntent({ lp, pool, maxDriftBps: 2000n, minDuration: 3600n,
  maxSize: 1000n * 10n ** 18n, nonce: 1n, deadline });
const signature = await signIntent(walletClient, account, chainId, hook, intent);

// 2) Submit / settle through the typed client.
const client = new HelixClient(publicClient, addresses, walletClient);
await client.submitMatch([intent, intent2], [signature, signature2]);
await client.settle(matchId);
```

## Exports

- `Intent`, `IntentEip712Types`, `helixDomain`, `RebalanceAction`, `MatchStatus`, `HelixAddresses`
- `buildIntent`, `intentDigest`, `signIntent`, `recoverIntentSigner`
- `HelixClient` — `submitMatch`, `settle`, `cancelMatch`, `getMatch`, `scoreOf`, `breakerState`,
  `marginOf`, `nonceUsed`, `approveMargin`
- `abis` — generated contract ABIs (regenerate with `forge inspect <C> abi --json`)

> **EIP-712 parity is load-bearing:** `IntentEip712Types` must stay byte-identical (field order + types)
> to Solidity's `IntentLib.INTENT_TYPEHASH`, or on-chain signature recovery fails.
