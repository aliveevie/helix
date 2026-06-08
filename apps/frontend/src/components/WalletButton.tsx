import { useAccount, useChainId, useConnect, useDisconnect, useSwitchChain } from "wagmi";
import { TARGET_CHAIN_ID, helixChain } from "../config";
import { short } from "../lib/format";

export function WalletButton() {
  const { address, isConnected, chain } = useAccount();
  const chainId = useChainId();
  const { connect, connectors, isPending } = useConnect();
  const { disconnect } = useDisconnect();
  const { switchChain } = useSwitchChain();

  if (!isConnected) {
    const injected = connectors.find((c) => c.type === "injected") ?? connectors[0];
    return (
      <button
        className="btn primary"
        disabled={isPending || !injected}
        onClick={() => injected && connect({ connector: injected })}
      >
        {isPending ? "Connecting…" : "Connect Wallet"}
      </button>
    );
  }

  const wrongChain = chainId !== TARGET_CHAIN_ID;

  return (
    <div className="inline-actions">
      {wrongChain ? (
        <button
          className="btn"
          onClick={() => switchChain({ chainId: TARGET_CHAIN_ID })}
          title={`Switch to ${helixChain.name}`}
        >
          ⚠ Switch to {helixChain.name}
        </button>
      ) : (
        <span className="pill ok" title={chain?.name}>
          <span className="dot" />
          {chain?.name ?? helixChain.name}
        </span>
      )}
      <button className="btn" onClick={() => disconnect()} title={address}>
        <span className="mono">{short(address)}</span>
      </button>
    </div>
  );
}
