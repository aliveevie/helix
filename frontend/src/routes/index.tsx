import { createFileRoute } from "@tanstack/react-router";
import { useEffect, useState } from "react";

export const Route = createFileRoute("/")({
  head: () => ({
    meta: [
      { title: "Helix — Cross-Pool IL Mutualization for Uniswap v4" },
      { name: "description", content: "Helix mutualizes impermanent loss across matched LP baskets on Uniswap v4. Sign EIP-712 intents, match permissionlessly, settle on-chain." },
      { property: "og:title", content: "Helix — Cross-Pool IL Mutualization for Uniswap v4" },
      { property: "og:description", content: "Mutualize impermanent loss across matched Uniswap v4 LP positions. Live on Sepolia." },
    ],
  }),
  component: Index,
});

function Index() {
  // Wagmi + viem rely on browser APIs; mount client-only.
  const [mounted, setMounted] = useState(false);
  const [App, setApp] = useState<React.ComponentType | null>(null);
  useEffect(() => {
    setMounted(true);
    import("@/components/helix/HelixApp").then((m) => setApp(() => m.HelixApp));
  }, []);

  if (!mounted || !App) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <div className="text-center">
          <div className="text-3xl sm:text-4xl font-semibold tracking-tight text-gradient">Helix</div>
          <div className="mt-2 text-sm text-[var(--color-muted-foreground)]">
            Cross-Pool IL Mutualization for Uniswap v4
          </div>
          <div className="mt-6 mono text-xs text-[var(--color-muted-foreground)]">loading…</div>
        </div>
      </div>
    );
  }
  return <App />;
}
