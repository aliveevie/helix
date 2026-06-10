import { useAccount, useReadContract, useWriteContract } from "wagmi";
import { ADDR, valueTokenAbi } from "@/lib/helix/config";
import { fmtNum, txUrl } from "@/lib/helix/format";
import { toast } from "sonner";
import { parseUnits } from "viem";

export function Faucet() {
  const { address, isConnected } = useAccount();
  const bal = useReadContract({
    address: ADDR.valueToken, abi: valueTokenAbi, functionName: "balanceOf",
    args: address ? [address] : undefined,
    query: { enabled: !!address, refetchInterval: 15_000 },
  });
  const { writeContractAsync, isPending } = useWriteContract();

  async function mint() {
    if (!address) return;
    try {
      const hash = await writeContractAsync({
        address: ADDR.valueToken, abi: valueTokenAbi, functionName: "mint",
        args: [address, parseUnits("10000", 18)],
      });
      toast.success("Mint submitted", {
        description: "View on Etherscan",
        action: { label: "Open", onClick: () => window.open(txUrl(hash), "_blank") },
      });
      setTimeout(() => bal.refetch(), 8000);
    } catch (e: any) {
      toast.error("Mint failed", { description: e?.shortMessage ?? e?.message });
    }
  }

  return (
    <section className="surface p-6">
      <div className="flex items-start justify-between gap-4 flex-wrap">
        <div>
          <h2 className="text-lg font-semibold">Faucet</h2>
          <p className="text-sm text-[var(--color-muted-foreground)] mt-1">
            Mint testnet USDV (Value Token, 18 decimals).
          </p>
        </div>
        <div className="text-right">
          <div className="text-xs uppercase tracking-wider text-[var(--color-muted-foreground)]">Balance</div>
          <div className="mono text-2xl text-gradient">
            {bal.data !== undefined ? fmtNum(bal.data as bigint, 18, 4) : "—"} <span className="text-base text-[var(--color-muted-foreground)]">USDV</span>
          </div>
        </div>
      </div>
      <div className="mt-5">
        <button className="btn-primary mono" disabled={!isConnected || isPending} onClick={mint}>
          {isPending ? "Minting…" : "Mint 10,000 USDV"}
        </button>
        {!isConnected && (
          <p className="mt-2 text-xs text-[var(--color-muted-foreground)]">Connect wallet to mint.</p>
        )}
      </div>
    </section>
  );
}
