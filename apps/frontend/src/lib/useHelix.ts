import { HelixClient } from "@helix/sdk";
import { useMemo } from "react";
import type { PublicClient, WalletClient } from "viem";
import { useAccount, useChainId, usePublicClient, useWalletClient } from "wagmi";
import { ADDRESSES, ADDRESSES_CONFIGURED, TARGET_CHAIN_ID } from "../config";

export interface HelixContextValue {
  client: HelixClient | null;
  /** True when wallet connected AND core addresses are real (not zero). */
  live: boolean;
  /** True whenever we cannot do real on-chain reads → use mock data. */
  mock: boolean;
  connected: boolean;
  chainId: number;
  /** Wallet on the configured target chain? */
  rightChain: boolean;
  hasWallet: boolean;
}

/**
 * Builds a HelixClient from the active wagmi clients. Returns a `mock` flag the
 * UI uses to fall back to deterministic local data. Never throws.
 */
export function useHelix(): HelixContextValue {
  const { isConnected } = useAccount();
  const chainId = useChainId();
  const publicClient = usePublicClient() as PublicClient | undefined;
  const { data: walletClient } = useWalletClient();

  return useMemo<HelixContextValue>(() => {
    const rightChain = chainId === TARGET_CHAIN_ID;
    const hasWallet = Boolean(walletClient);

    let client: HelixClient | null = null;
    if (publicClient && ADDRESSES_CONFIGURED) {
      try {
        client = new HelixClient(
          publicClient,
          ADDRESSES,
          (walletClient as WalletClient | undefined) ?? undefined,
        );
      } catch {
        client = null;
      }
    }

    const live = Boolean(client) && ADDRESSES_CONFIGURED;
    return {
      client,
      live,
      mock: !live,
      connected: isConnected,
      chainId,
      rightChain,
      hasWallet,
    };
  }, [isConnected, chainId, publicClient, walletClient]);
}
