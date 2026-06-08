// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {HookMiner} from "./utils/HookMiner.sol";

import {HelixHook} from "../src/HelixHook.sol";
import {CircuitBreaker} from "../src/CircuitBreaker.sol";
import {ReputationAccumulator} from "../src/ReputationAccumulator.sol";
import {SettlementRegistry} from "../src/SettlementRegistry.sol";
import {HelixTypes} from "../src/libraries/HelixTypes.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockOracle} from "../src/mocks/MockOracle.sol";
import {MockPoolManager} from "../src/mocks/MockPoolManager.sol";

import {IHelixOracle} from "../src/interfaces/IHelixOracle.sol";
import {ICircuitBreaker} from "../src/interfaces/ICircuitBreaker.sol";
import {IReputation} from "../src/interfaces/IReputation.sol";
import {ISettlementRegistry} from "../src/interfaces/ISettlementRegistry.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";

/// @notice Deploys the full Helix accounting + control plane.
/// @dev Reads `POOL_MANAGER` and `VALUE_TOKEN` from the environment when present (production), otherwise
///      deploys local mocks (anvil). The hook is CREATE2-deployed at a permission-encoding address.
contract Deploy is Script {
    // Canonical deterministic CREATE2 deployer (used by forge's `new{salt}` under broadcast).
    address internal constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    uint160 internal constant HOOK_FLAGS = uint160(
        Hooks.AFTER_INITIALIZE_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
            | Hooks.AFTER_SWAP_FLAG
    );

    function run() external {
        address poolManager = vm.envOr("POOL_MANAGER", address(0));
        address valueToken = vm.envOr("VALUE_TOKEN", address(0));

        vm.startBroadcast();

        if (poolManager == address(0)) poolManager = address(new MockPoolManager());
        if (valueToken == address(0)) valueToken = address(new MockERC20("USD Value", "USDV", 18));

        MockOracle oracle = new MockOracle();
        CircuitBreaker breaker = new CircuitBreaker(0.3e18, 0.01e18, 0.02e18, 0.05e18);
        ReputationAccumulator reputation = new ReputationAccumulator();
        SettlementRegistry registry = new SettlementRegistry(valueToken, 50);

        HelixTypes.PoolConfig memory cfg = HelixTypes.PoolConfig({
            epochLength: 1 days,
            rho: 7_500,
            marginRatioBps: 500,
            maxDivergenceBps: 300,
            initialized: false
        });

        // Admin must be passed explicitly: CREATE2 makes msg.sender the factory, not the deployer.
        address admin = vm.envOr("DEPLOYER_ADDRESS", msg.sender);
        require(admin != address(0), "Deploy: set DEPLOYER_ADDRESS");

        bytes memory args = abi.encode(
            IPoolManager(poolManager),
            IHelixOracle(address(oracle)),
            ICircuitBreaker(address(breaker)),
            IReputation(address(reputation)),
            ISettlementRegistry(address(registry)),
            cfg,
            admin
        );
        (address hookAddr, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, HOOK_FLAGS, type(HelixHook).creationCode, args);

        HelixHook hook = new HelixHook{salt: salt}(
            IPoolManager(poolManager),
            IHelixOracle(address(oracle)),
            ICircuitBreaker(address(breaker)),
            IReputation(address(reputation)),
            ISettlementRegistry(address(registry)),
            cfg,
            admin
        );
        require(address(hook) == hookAddr, "Deploy: hook address mismatch");

        breaker.setHook(hookAddr);
        reputation.setHook(hookAddr);
        registry.setHook(hookAddr);

        vm.stopBroadcast();

        console2.log("PoolManager  ", poolManager);
        console2.log("ValueToken   ", valueToken);
        console2.log("Oracle       ", address(oracle));
        console2.log("CircuitBreaker", address(breaker));
        console2.log("Reputation   ", address(reputation));
        console2.log("Registry     ", address(registry));
        console2.log("HelixHook    ", hookAddr);
    }
}
