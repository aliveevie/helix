import { useEffect, useState } from "react";
import { useAccount, useConnect, useDisconnect, useChainId, useSwitchChain } from "wagmi";
import { CHAIN_ID } from "@/lib/helix/config";
import { short } from "@/lib/helix/format";

export function WalletButton() {
  const { address, isConnected } = useAccount();
  const { connectors, connect, isPending } = useConnect();
  const { disconnect } = useDisconnect();
  const chainId = useChainId();
  const { switchChain } = useSwitchChain();
  const [open, setOpen] = useState(false);

  useEffect(() => {
    if (isConnected && chainId !== CHAIN_ID && switchChain) {
      try { switchChain({ chainId: CHAIN_ID }); } catch { /* noop */ }
    }
  }, [isConnected, chainId, switchChain]);

  if (!isConnected) {
    const injected = connectors.find((c) => c.id === "injected") ?? connectors[0];
    return (
      <button
        className="btn-primary mono"
        onClick={() => injected && connect({ connector: injected })}
        disabled={isPending || !injected}
      >
        {isPending ? "Connecting…" : "Connect Wallet"}
      </button>
    );
  }

  const wrongChain = chainId !== CHAIN_ID;

  return (
    <div className="relative">
      <button className="btn-ghost mono flex items-center gap-2" onClick={() => setOpen((v) => !v)}>
        <span className={`h-2 w-2 rounded-full ${wrongChain ? "bg-[var(--danger)]" : "bg-[var(--success)]"}`} />
        {short(address)}
      </button>
      {open && (
        <div className="surface absolute right-0 mt-2 w-56 p-2 z-30">
          <div className="px-2 py-1.5 text-xs text-[var(--color-muted-foreground)]">
            {wrongChain ? "Wrong network" : "Sepolia"}
          </div>
          {wrongChain && (
            <button
              className="w-full text-left rounded-md px-2 py-1.5 hover:bg-white/5 text-sm"
              onClick={() => switchChain?.({ chainId: CHAIN_ID })}
            >
              Switch to Sepolia
            </button>
          )}
          <button
            className="w-full text-left rounded-md px-2 py-1.5 hover:bg-white/5 text-sm text-[var(--danger)]"
            onClick={() => { disconnect(); setOpen(false); }}
          >
            Disconnect
          </button>
        </div>
      )}
    </div>
  );
}
