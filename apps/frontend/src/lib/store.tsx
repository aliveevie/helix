import { createContext, useContext, type ReactNode } from "react";
import type { KnownBasket, SignedIntent } from "./types";
import { useLocalStorage } from "./useLocalStorage";

interface Store {
  intents: SignedIntent[];
  addIntent: (i: SignedIntent) => void;
  removeIntent: (id: string) => void;
  clearIntents: () => void;

  baskets: KnownBasket[];
  addBasket: (b: KnownBasket) => void;
  removeBasket: (matchId: string) => void;
}

const StoreCtx = createContext<Store | null>(null);

export function StoreProvider({ children }: { children: ReactNode }) {
  const [intents, setIntents] = useLocalStorage<SignedIntent[]>("helix.intents", []);
  const [baskets, setBaskets] = useLocalStorage<KnownBasket[]>("helix.baskets", []);

  const store: Store = {
    intents,
    addIntent: (i) => setIntents((prev) => [i, ...prev.filter((p) => p.id !== i.id)]),
    removeIntent: (id) => setIntents((prev) => prev.filter((p) => p.id !== id)),
    clearIntents: () => setIntents([]),

    baskets,
    addBasket: (b) =>
      setBaskets((prev) => [
        b,
        ...prev.filter((p) => p.matchId.toLowerCase() !== b.matchId.toLowerCase()),
      ]),
    removeBasket: (matchId) =>
      setBaskets((prev) => prev.filter((p) => p.matchId.toLowerCase() !== matchId.toLowerCase())),
  };

  return <StoreCtx.Provider value={store}>{children}</StoreCtx.Provider>;
}

export function useStore(): Store {
  const ctx = useContext(StoreCtx);
  if (!ctx) throw new Error("useStore must be used within StoreProvider");
  return ctx;
}
