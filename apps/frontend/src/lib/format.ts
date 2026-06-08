import { formatUnits } from "viem";

/** 1e18 fixed-point (WAD) scale used by Helix margins / value tokens. */
export const WAD = 10n ** 18n;

/** Shorten an address / hash for display: 0x1234…abcd */
export function short(value: string | undefined, lead = 6, tail = 4): string {
  if (!value) return "—";
  if (value.length <= lead + tail + 2) return value;
  return `${value.slice(0, lead)}…${value.slice(-tail)}`;
}

/** Format a WAD-scaled bigint as a human number, trimming trailing zeros. */
export function formatWad(value: bigint, maxFractionDigits = 4): string {
  const s = formatUnits(value, 18);
  const n = Number(s);
  if (!Number.isFinite(n)) return s;
  return n.toLocaleString("en-US", {
    minimumFractionDigits: 0,
    maximumFractionDigits: maxFractionDigits,
  });
}

/** Format a plain token amount given decimals. */
export function formatToken(value: bigint, decimals = 18, maxFractionDigits = 4): string {
  const n = Number(formatUnits(value, decimals));
  if (!Number.isFinite(n)) return formatUnits(value, decimals);
  return n.toLocaleString("en-US", {
    minimumFractionDigits: 0,
    maximumFractionDigits: maxFractionDigits,
  });
}

/** Basis points → percent string, e.g. 250 → "2.50%". */
export function bpsToPct(bps: bigint | number): string {
  const v = typeof bps === "bigint" ? Number(bps) : bps;
  return `${(v / 100).toFixed(2)}%`;
}

/** Seconds → compact duration, e.g. 90000 → "1d 1h". */
export function formatDuration(seconds: bigint | number): string {
  let s = typeof seconds === "bigint" ? Number(seconds) : seconds;
  if (!Number.isFinite(s) || s < 0) return "—";
  const d = Math.floor(s / 86400);
  s -= d * 86400;
  const h = Math.floor(s / 3600);
  s -= h * 3600;
  const m = Math.floor(s / 60);
  const parts: string[] = [];
  if (d) parts.push(`${d}d`);
  if (h) parts.push(`${h}h`);
  if (m && !d) parts.push(`${m}m`);
  if (parts.length === 0) parts.push(`${Math.floor(s)}s`);
  return parts.slice(0, 2).join(" ");
}

/** Unix seconds → locale timestamp. */
export function formatTimestamp(unixSeconds: bigint | number): string {
  const s = typeof unixSeconds === "bigint" ? Number(unixSeconds) : unixSeconds;
  if (!Number.isFinite(s) || s <= 0) return "—";
  return new Date(s * 1000).toLocaleString();
}

/** Seconds remaining until a unix timestamp (clamped at 0). */
export function secondsUntil(unixSeconds: bigint | number): number {
  const target = typeof unixSeconds === "bigint" ? Number(unixSeconds) : unixSeconds;
  const now = Math.floor(Date.now() / 1000);
  return Math.max(0, target - now);
}

/**
 * JSON.stringify replacer that serializes bigints as `"<n>n"` so they
 * round-trip without throwing. Pair with `bigintReviver` to parse back.
 */
export function bigintReplacer(_key: string, value: unknown): unknown {
  return typeof value === "bigint" ? `${value.toString()}n` : value;
}

export function bigintReviver(_key: string, value: unknown): unknown {
  if (typeof value === "string" && /^-?\d+n$/.test(value)) {
    return BigInt(value.slice(0, -1));
  }
  return value;
}

/** Safe stringify for display that never throws on bigint. */
export function safeStringify(value: unknown, space = 2): string {
  return JSON.stringify(value, bigintReplacer, space);
}
