import { useCallback, useEffect, useState } from "react";
import { bigintReplacer, bigintReviver } from "./format";

/**
 * useState-like hook backed by localStorage with bigint-safe (de)serialization.
 * Never throws on a malformed payload — falls back to the initial value.
 */
export function useLocalStorage<T>(
  key: string,
  initial: T,
): [T, (next: T | ((prev: T) => T)) => void] {
  const [value, setValue] = useState<T>(() => {
    try {
      const raw = window.localStorage.getItem(key);
      if (raw == null) return initial;
      return JSON.parse(raw, bigintReviver) as T;
    } catch {
      return initial;
    }
  });

  useEffect(() => {
    try {
      window.localStorage.setItem(key, JSON.stringify(value, bigintReplacer));
    } catch {
      /* quota / serialization issues are non-fatal for the demo */
    }
  }, [key, value]);

  const set = useCallback((next: T | ((prev: T) => T)) => {
    setValue((prev) => (typeof next === "function" ? (next as (p: T) => T)(prev) : next));
  }, []);

  return [value, set];
}
