import { EXPLORER } from "./config";

export function short(addr?: string | null, head = 6, tail = 4) {
  if (!addr) return "—";
  if (addr.length <= head + tail + 2) return addr;
  return `${addr.slice(0, head)}…${addr.slice(-tail)}`;
}

export function txUrl(hash: string) {
  return `${EXPLORER}/tx/${hash}`;
}
export function addrUrl(a: string) {
  return `${EXPLORER}/address/${a}`;
}

export function fmtNum(v: bigint | number | string, decimals = 18, max = 4) {
  try {
    const bi = typeof v === "bigint" ? v : BigInt(v as never);
    const neg = bi < 0n;
    const abs = neg ? -bi : bi;
    const base = 10n ** BigInt(decimals);
    const whole = abs / base;
    const frac = abs % base;
    const fracStr = frac.toString().padStart(decimals, "0").slice(0, max).replace(/0+$/, "");
    return `${neg ? "-" : ""}${whole.toString()}${fracStr ? "." + fracStr : ""}`;
  } catch {
    return String(v);
  }
}

export function bpsToPct(bps: number | bigint) {
  const n = typeof bps === "bigint" ? Number(bps) : bps;
  return `${(n / 100).toFixed(2)}%`;
}
