import { describe, expect, it } from "vitest";
import { createWalletClient, http, keccak256, toHex } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { foundry } from "viem/chains";
import { buildIntent, intentDigest, recoverIntentSigner, signIntent } from "./intent.js";

const HOOK = "0x1640000000000000000000000000000000004444" as const;
const CHAIN_ID = 1301;
const account = privateKeyToAccount("0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d");

function sampleIntent() {
  return buildIntent({
    lp: account.address,
    pool: keccak256(toHex("ETH/USDC")),
    maxDriftBps: 2000n,
    minDuration: 3600n,
    maxSize: 1000n * 10n ** 18n,
    repFloor: 0,
    nonce: 1n,
    deadline: 9999999999n,
  });
}

describe("intent EIP-712", () => {
  it("produces a deterministic digest", () => {
    const d1 = intentDigest(CHAIN_ID, HOOK, sampleIntent());
    const d2 = intentDigest(CHAIN_ID, HOOK, sampleIntent());
    expect(d1).toBe(d2);
    expect(d1).toMatch(/^0x[0-9a-f]{64}$/);
  });

  it("signs and recovers the signer (round-trip)", async () => {
    const wc = createWalletClient({ account, chain: foundry, transport: http() });
    const intent = sampleIntent();
    const sig = await signIntent(wc, account, CHAIN_ID, HOOK, intent);
    const recovered = await recoverIntentSigner(CHAIN_ID, HOOK, intent, sig);
    expect(recovered.toLowerCase()).toBe(account.address.toLowerCase());
  });

  it("changes digest when any field changes", () => {
    const base = sampleIntent();
    const a = intentDigest(CHAIN_ID, HOOK, base);
    const b = intentDigest(CHAIN_ID, HOOK, { ...base, nonce: 2n });
    expect(a).not.toBe(b);
  });
});
