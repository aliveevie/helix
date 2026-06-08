/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_CHAIN_ID?: string;
  readonly VITE_CHAIN_NAME?: string;
  readonly VITE_NATIVE_NAME?: string;
  readonly VITE_NATIVE_SYMBOL?: string;
  readonly VITE_RPC_URL?: string;
  readonly VITE_ANVIL_RPC_URL?: string;
  readonly VITE_EXPLORER_NAME?: string;
  readonly VITE_EXPLORER_URL?: string;
  readonly VITE_HOOK_ADDRESS?: string;
  readonly VITE_REGISTRY_ADDRESS?: string;
  readonly VITE_REPUTATION_ADDRESS?: string;
  readonly VITE_BREAKER_ADDRESS?: string;
  readonly VITE_ORACLE_ADDRESS?: string;
  readonly VITE_VALUE_TOKEN_ADDRESS?: string;
  readonly VITE_POOL_MANAGER_ADDRESS?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
