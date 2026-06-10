import { ADDR } from "@/lib/helix/config";
import { addrUrl, short } from "@/lib/helix/format";

const ENTRIES: { label: string; addr: string }[] = [
  { label: "HelixHook", addr: ADDR.hook },
  { label: "Settlement", addr: ADDR.registry },
  { label: "Reputation (ERC-8004)", addr: ADDR.reputation },
  { label: "CircuitBreaker", addr: ADDR.breaker },
  { label: "Oracle", addr: ADDR.oracle },
  { label: "USDV (Value Token)", addr: ADDR.valueToken },
];

export function ContractsFooter() {
  return (
    <footer className="surface p-6 mt-10">
      <div className="text-xs uppercase tracking-wider text-[var(--color-muted-foreground)] mb-3">Contracts (Sepolia)</div>
      <div className="grid sm:grid-cols-2 md:grid-cols-3 gap-2 text-sm">
        {ENTRIES.map((e) => (
          <a key={e.addr} href={addrUrl(e.addr)} target="_blank" rel="noreferrer"
             className="flex items-center justify-between rounded-md border border-[var(--color-border)] px-3 py-2 hover:border-[var(--color-cyan)] transition">
            <span>{e.label}</span>
            <span className="mono text-xs text-[var(--color-muted-foreground)]">{short(e.addr, 6, 4)}</span>
          </a>
        ))}
      </div>
      <div className="mt-4 text-[11px] text-[var(--color-muted-foreground)]">
        Helix · Cross-Pool IL Mutualization for Uniswap v4 · Testnet demo
      </div>
    </footer>
  );
}
