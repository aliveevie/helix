// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {HelixReactive} from "../src/reactive/HelixReactive.sol";
import {ISystemContract} from "../src/reactive/ReactiveLib.sol";

/// @notice Deploy the Helix Reactive Smart Contract to the Reactive Network (Lasna/Kopli) and subscribe
///         it to the origin-chain hook's PriceObserved / MatchSubmitted events.
/// @dev Run on the Reactive Network:
///        REACTIVE_RPC=<lasna_rpc> HOOK=<origin_hook> DEST_CHAIN_ID=11155111 \
///        forge script script/DeployReactive.s.sol --rpc-url $REACTIVE_RPC \
///          --account helix-deployer --broadcast
///      Afterwards, on the origin chain call `hook.setReactiveProxy(<reactive callback proxy>)` so the
///      hook authenticates the RSC's `triggerRebalance` callbacks.
contract DeployReactive is Script {
    // Canonical Reactive Network system contract.
    address internal constant REACTIVE_SYSTEM = 0x0000000000000000000000000000000000fffFfF;

    function run() external {
        address hookAddr = vm.envOr("HOOK", address(0x0E00cAc14C70Cf2EA46b33fe17E55Ac02DEb5640));
        uint256 destChainId = vm.envOr("DEST_CHAIN_ID", uint256(11155111)); // Sepolia
        bytes32 pool = vm.envOr("POOL_ID", keccak256("HELIX-ETH-USDC-CHAINLINK"));

        vm.startBroadcast();
        // vmContext = true: we're deploying on the Reactive Network, where `react` is VM-driven.
        HelixReactive rsc = new HelixReactive(ISystemContract(REACTIVE_SYSTEM), true);
        rsc.registerPool(pool, destChainId, hookAddr); // subscribes to the hook's events + sets callback target
        vm.stopBroadcast();

        console2.log("HelixReactive:", address(rsc));
        console2.log("subscribed to hook:", hookAddr);
        console2.log("dest chain id:", destChainId);
        console2.log("Next: on the origin chain, hook.setReactiveProxy(<reactive callback proxy>)");
    }
}
