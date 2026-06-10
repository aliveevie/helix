import type { Address, Hex } from "viem";

export type StoredIntent = {
  id: string;
  intent: {
    lp: Address;
    pool: Hex;
    maxDriftBps: string; // bigint as string
    minDuration: string;
    maxSize: string;
    repFloor: number;
    nonce: string;
    deadline: string;
  };
  signature: Hex;
  digest?: Hex;
  ephemeralKey?: Hex; // present when generated counterparty
  createdAt: number;
};

const KEY = "helix.intents.v1";

export function loadIntents(): StoredIntent[] {
  if (typeof window === "undefined") return [];
  try {
    const raw = window.localStorage.getItem(KEY);
    return raw ? (JSON.parse(raw) as StoredIntent[]) : [];
  } catch {
    return [];
  }
}

export function saveIntents(list: StoredIntent[]) {
  if (typeof window === "undefined") return;
  window.localStorage.setItem(KEY, JSON.stringify(list));
}

export function addIntent(intent: StoredIntent) {
  const list = loadIntents();
  list.unshift(intent);
  saveIntents(list);
}

export function removeIntent(id: string) {
  saveIntents(loadIntents().filter((i) => i.id !== id));
}
