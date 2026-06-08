import { createConfig, http } from "wagmi";
import { injected } from "wagmi/connectors";
import { SUPPORTED_CHAINS, helixChain, anvilChain } from "./config";

/**
 * wagmi v2 config. Uses the injected connector (MetaMask / any EIP-1193
 * wallet). Transports are keyed by chain id so reads route to the right RPC.
 */
export const wagmiConfig = createConfig({
  chains: SUPPORTED_CHAINS,
  connectors: [injected()],
  transports: {
    [helixChain.id]: http(),
    [anvilChain.id]: http(),
  },
  multiInjectedProviderDiscovery: true,
});

declare module "wagmi" {
  interface Register {
    config: typeof wagmiConfig;
  }
}
