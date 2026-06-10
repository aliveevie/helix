import { parseAbi, type Address, type Hex } from "viem";
import { sepolia } from "viem/chains";

export const CHAIN = sepolia;
export const CHAIN_ID = 11155111;
export const RPC_URL = "https://ethereum-sepolia-rpc.publicnode.com";
export const EXPLORER = "https://sepolia.etherscan.io";

export const ADDR = {
  hook: "0x6704c3F3FeF5F7596E68470B3430b14b8c99d640" as Address,
  registry: "0xEbeea487E52578A35668efEcfAEE8dC6082baa2d" as Address,
  reputation: "0x2996cFF1F07aFFc2D5ddBD530603F58edbd59b89" as Address,
  breaker: "0x3c02963015cf88c12Ffb2a44Ed4e04AaE2f1dF7c" as Address,
  oracle: "0x252F8edDf8A208169787B95FDC63a68E0E08875B" as Address,
  valueToken: "0x15cc1B894b3A3a668211B43172Ce034E2D7d5BAD" as Address,
} as const;

// v2 cross-pool deploy: two initialized demo pools — a basket may span both.
export const DEMO_POOL_ID =
  "0x9e1d00d0ce2a12e530a4b694022e420ef1b6bee1d612b70ef40132363057acb8" as Hex; // ETH/USDC (demo)
export const DEMO_POOL_ID_B =
  "0xdf9b8c5db6a98f7288a1cfab22629dca89bc44374df7912c0ccededb09726bf5" as Hex; // ARB/USDC (demo)
// Live cross-pool basket formed on-chain at deploy time (one basket, two pools):
export const DEMO_CROSS_POOL_MATCH_ID =
  "0x4c8e09b91f79e485cd65e96898344f120c5a37b94ba74e09fe1c59a4a260b441" as Hex;

export const hookAbi = parseAbi([
  "function submitMatch((address lp,bytes32 pool,uint256 maxDriftBps,uint64 minDuration,uint128 maxSize,uint16 repFloor,uint256 nonce,uint64 deadline)[] intents, bytes[] signatures) returns (bytes32 matchId)",
  "function settle(bytes32 matchId)",
  "function cancelMatch(bytes32 matchId)",
  "function getMatch(bytes32 matchId) view returns ((bytes32 pool,uint64 createdAt,uint64 epochEnd,uint64 minDuration,uint16 rho,uint16 requiredRatioBps,uint32 enteredCount,uint8 status,uint8 pending,address[] lps,bytes32[] keys,uint256[] sizes,bytes32[] pools))",
  "function nonceUsed(address lp, uint256 nonce) view returns (bool)",
  "function domainSeparatorV4() view returns (bytes32)",
  "function entryWindow() view returns (uint64)",
  "function owner() view returns (address)",
  "event MatchSubmitted(bytes32 indexed matchId, bytes32 indexed pool, address[] lps, uint256[] sizes, uint16 rho)",
  "event MatchSettled(bytes32 indexed matchId, uint256 p1, uint256 ilTotal, address settler)",
]);

export const breakerAbi = parseAbi([
  "function state(bytes32 pool) view returns (uint8)",
  "function volIndex(bytes32 pool) view returns (uint256)",
]);

export const reputationAbi = parseAbi([
  "function scoreOf(address lp) view returns (uint16)",
]);

export const registryAbi = parseAbi([
  "function marginOf(bytes32 matchId, address lp) view returns (uint256)",
  "function settlerFeeBps() view returns (uint16)",
]);

export const valueTokenAbi = parseAbi([
  "function balanceOf(address) view returns (uint256)",
  "function decimals() view returns (uint8)",
  "function approve(address spender, uint256 amount) returns (bool)",
  "function mint(address to, uint256 amount)",
]);

export const EIP712_DOMAIN = {
  name: "Helix",
  version: "1",
  chainId: CHAIN_ID,
  verifyingContract: ADDR.hook,
} as const;

export const EIP712_TYPES = {
  Intent: [
    { name: "lp", type: "address" },
    { name: "pool", type: "bytes32" },
    { name: "maxDriftBps", type: "uint256" },
    { name: "minDuration", type: "uint64" },
    { name: "maxSize", type: "uint128" },
    { name: "repFloor", type: "uint16" },
    { name: "nonce", type: "uint256" },
    { name: "deadline", type: "uint64" },
  ],
} as const;

export const STATUS_LABEL = ["NONE", "PENDING", "OPEN", "SETTLED", "CANCELLED"];
export const BREAKER_LABEL = ["NORMAL", "ELEVATED", "HALTED"];
export const PENDING_LABEL = ["NONE", "RE_MATCH", "PAUSE", "RESUME"];
