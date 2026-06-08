import type { Abi } from "viem";

import HelixHookAbi from "./abis/HelixHook.json" with { type: "json" };
import SettlementRegistryAbi from "./abis/SettlementRegistry.json" with { type: "json" };
import ReputationAccumulatorAbi from "./abis/ReputationAccumulator.json" with { type: "json" };
import CircuitBreakerAbi from "./abis/CircuitBreaker.json" with { type: "json" };
import HelixReactiveAbi from "./abis/HelixReactive.json" with { type: "json" };
import MockERC20Abi from "./abis/MockERC20.json" with { type: "json" };
import MockOracleAbi from "./abis/MockOracle.json" with { type: "json" };

export const abis = {
  HelixHook: HelixHookAbi as unknown as Abi,
  SettlementRegistry: SettlementRegistryAbi as unknown as Abi,
  ReputationAccumulator: ReputationAccumulatorAbi as unknown as Abi,
  CircuitBreaker: CircuitBreakerAbi as unknown as Abi,
  HelixReactive: HelixReactiveAbi as unknown as Abi,
  MockERC20: MockERC20Abi as unknown as Abi,
  MockOracle: MockOracleAbi as unknown as Abi,
} as const;
