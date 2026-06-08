import {
  type Account,
  type Address,
  type Hex,
  type WalletClient,
  hashTypedData,
  recoverTypedDataAddress,
} from "viem";
import { type Intent, IntentEip712Types, helixDomain } from "./types.js";

export interface BuildIntentArgs {
  lp: Address;
  pool: Hex;
  maxDriftBps: bigint;
  minDuration: bigint;
  maxSize: bigint;
  repFloor?: number;
  nonce: bigint;
  deadline: bigint;
}

/** Construct a well-formed intent with sane defaults. */
export function buildIntent(args: BuildIntentArgs): Intent {
  return {
    lp: args.lp,
    pool: args.pool,
    maxDriftBps: args.maxDriftBps,
    minDuration: args.minDuration,
    maxSize: args.maxSize,
    repFloor: args.repFloor ?? 0,
    nonce: args.nonce,
    deadline: args.deadline,
  };
}

/** The EIP-712 digest a signer commits to (equals the contract's `_hashTypedDataV4(IntentLib.hash(intent))`). */
export function intentDigest(chainId: number, hook: Address, intent: Intent): Hex {
  return hashTypedData({
    domain: helixDomain(chainId, hook),
    types: IntentEip712Types,
    primaryType: "Intent",
    message: intent,
  });
}

/** Sign an intent with a viem account/wallet. Returns the 65-byte signature accepted by `submitMatch`. */
export async function signIntent(
  walletClient: WalletClient,
  account: Account,
  chainId: number,
  hook: Address,
  intent: Intent,
): Promise<Hex> {
  return walletClient.signTypedData({
    account,
    domain: helixDomain(chainId, hook),
    types: IntentEip712Types,
    primaryType: "Intent",
    message: intent,
  });
}

/** Recover the signer of an intent signature — used by the engine to pre-validate before submitting. */
export async function recoverIntentSigner(
  chainId: number,
  hook: Address,
  intent: Intent,
  signature: Hex,
): Promise<Address> {
  return recoverTypedDataAddress({
    domain: helixDomain(chainId, hook),
    types: IntentEip712Types,
    primaryType: "Intent",
    message: intent,
    signature,
  });
}
