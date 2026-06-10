import { useEffect, useState } from "react";
import { HelixWagmiProvider } from "@/lib/helix/wagmi";
import { Toaster } from "sonner";
import { WalletButton } from "@/components/helix/WalletButton";
import { BreakerPill } from "@/components/helix/BreakerPill";
import { Faucet } from "@/components/helix/Faucet";
import { CreateIntent } from "@/components/helix/CreateIntent";
import { Matching } from "@/components/helix/Matching";
import { Baskets } from "@/components/helix/Baskets";
import { Reputation } from "@/components/helix/Reputation";
import { ContractsFooter } from "@/components/helix/ContractsFooter";
import { loadIntents, type StoredIntent } from "@/lib/helix/storage";

export function HelixApp() {
  const [intents, setIntents] = useState<StoredIntent[]>([]);
  const [activeMatchId, setActiveMatchId] = useState<string | undefined>();

  const refresh = () => setIntents(loadIntents());
  useEffect(() => { refresh(); }, []);

  return (
    <HelixWagmiProvider>
      <Toaster theme="dark" richColors position="top-right" />
      <div className="min-h-screen">
        <header className="mx-auto max-w-6xl px-5 pt-10 pb-6">
          <div className="flex items-start justify-between gap-4 flex-wrap">
            <div>
              <div className="flex items-center gap-3">
                <Logo />
                <h1 className="text-4xl sm:text-5xl font-semibold tracking-tight text-gradient">Helix</h1>
              </div>
              <p className="mt-2 text-sm sm:text-base text-[var(--color-muted-foreground)]">
                Cross-Pool IL Mutualization for Uniswap v4
              </p>
              <div className="mt-3 flex flex-wrap gap-2">
                <span className="chip mono">Sepolia · 11155111</span>
                <span className="chip mono">Pool: ETH/USDC (demo)</span>
                <BreakerPill />
              </div>
            </div>
            <WalletButton />
          </div>
        </header>

        <main className="mx-auto max-w-6xl px-5 pb-10 grid gap-6">
          <div className="grid gap-6 md:grid-cols-2">
            <Faucet />
            <Reputation />
          </div>
          <CreateIntent onCreated={refresh} />
          <Matching intents={intents} onChange={refresh} onMatched={setActiveMatchId} />
          <Baskets initialMatchId={activeMatchId} />
          <ContractsFooter />
        </main>
      </div>
    </HelixWagmiProvider>
  );
}

function Logo() {
  return (
    <svg width="40" height="40" viewBox="0 0 40 40" fill="none" aria-hidden>
      <defs>
        <linearGradient id="hg" x1="0" y1="0" x2="40" y2="40">
          <stop offset="0" stopColor="#7CE3F2" />
          <stop offset="1" stopColor="#A782FF" />
        </linearGradient>
      </defs>
      <path d="M8 8 C 24 12, 16 28, 32 32" stroke="url(#hg)" strokeWidth="3" strokeLinecap="round" fill="none"/>
      <path d="M8 32 C 24 28, 16 12, 32 8" stroke="url(#hg)" strokeWidth="3" strokeLinecap="round" fill="none" opacity="0.7"/>
    </svg>
  );
}
