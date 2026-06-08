import {
  type Account,
  type Address,
  type Hex,
  type PublicClient,
  type WalletClient,
  maxUint256,
} from "viem";
import { abis } from "./abis.js";
import { type HelixAddresses, type Intent } from "./types.js";

/** Tuple form of an Intent as the ABI expects it (struct field order). */
function intentTuple(i: Intent) {
  return {
    lp: i.lp,
    pool: i.pool,
    maxDriftBps: i.maxDriftBps,
    minDuration: i.minDuration,
    maxSize: i.maxSize,
    repFloor: i.repFloor,
    nonce: i.nonce,
    deadline: i.deadline,
  };
}

/** Thin typed wrapper over the Helix on-chain surface. */
export class HelixClient {
  constructor(
    public readonly publicClient: PublicClient,
    public readonly addresses: HelixAddresses,
    public readonly walletClient?: WalletClient,
  ) {}

  // --- reads ---

  async getMatch(matchId: Hex) {
    return this.publicClient.readContract({
      address: this.addresses.hook,
      abi: abis.HelixHook,
      functionName: "getMatch",
      args: [matchId],
    });
  }

  async scoreOf(lp: Address): Promise<number> {
    const s = await this.publicClient.readContract({
      address: this.addresses.reputation,
      abi: abis.ReputationAccumulator,
      functionName: "scoreOf",
      args: [lp],
    });
    return Number(s);
  }

  async breakerState(poolId: Hex): Promise<number> {
    const s = await this.publicClient.readContract({
      address: this.addresses.breaker,
      abi: abis.CircuitBreaker,
      functionName: "state",
      args: [poolId],
    });
    return Number(s);
  }

  async marginOf(matchId: Hex, lp: Address): Promise<bigint> {
    return this.publicClient.readContract({
      address: this.addresses.registry,
      abi: abis.SettlementRegistry,
      functionName: "marginOf",
      args: [matchId, lp],
    }) as Promise<bigint>;
  }

  async nonceUsed(lp: Address, nonce: bigint): Promise<boolean> {
    return this.publicClient.readContract({
      address: this.addresses.hook,
      abi: abis.HelixHook,
      functionName: "nonceUsed",
      args: [lp, nonce],
    }) as Promise<boolean>;
  }

  // --- writes ---

  private requireWallet(account?: Account): { wc: WalletClient; account: Account } {
    if (!this.walletClient) throw new Error("HelixClient: walletClient required for writes");
    const acct = account ?? this.walletClient.account;
    if (!acct) throw new Error("HelixClient: account required");
    return { wc: this.walletClient, account: acct };
  }

  /** Approve the registry to pull margin (value token). */
  async approveMargin(amount: bigint = maxUint256, account?: Account): Promise<Hex> {
    const { wc, account: acct } = this.requireWallet(account);
    return wc.writeContract({
      chain: wc.chain,
      account: acct,
      address: this.addresses.valueToken,
      abi: abis.MockERC20,
      functionName: "approve",
      args: [this.addresses.registry, amount],
    });
  }

  /** Permissionlessly submit a basket of signed intents. */
  async submitMatch(intents: Intent[], signatures: Hex[], account?: Account): Promise<Hex> {
    const { wc, account: acct } = this.requireWallet(account);
    return wc.writeContract({
      chain: wc.chain,
      account: acct,
      address: this.addresses.hook,
      abi: abis.HelixHook,
      functionName: "submitMatch",
      args: [intents.map(intentTuple), signatures],
    });
  }

  /** Permissionlessly settle an expired open match (pays the caller a settler fee). */
  async settle(matchId: Hex, account?: Account): Promise<Hex> {
    const { wc, account: acct } = this.requireWallet(account);
    return wc.writeContract({
      chain: wc.chain,
      account: acct,
      address: this.addresses.hook,
      abi: abis.HelixHook,
      functionName: "settle",
      args: [matchId],
    });
  }

  /** Permissionlessly cancel a PENDING match stuck past its entry window (refunds entered margins). */
  async cancelMatch(matchId: Hex, account?: Account): Promise<Hex> {
    const { wc, account: acct } = this.requireWallet(account);
    return wc.writeContract({
      chain: wc.chain,
      account: acct,
      address: this.addresses.hook,
      abi: abis.HelixHook,
      functionName: "cancelMatch",
      args: [matchId],
    });
  }
}
