// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {HelixHook} from "../src/HelixHook.sol";
import {MockOracle} from "../src/mocks/MockOracle.sol";
import {HelixTypes} from "../src/libraries/HelixTypes.sol";
import {IntentLib} from "../src/libraries/IntentLib.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/// @notice Live CROSS-POOL smoke test: configure TWO demo pools, then submit one basket whose two
///         members live in different pools — the cross-asset hedge, permissionlessly, on-chain.
contract CrossPoolSmoke is Script {
    function run() external {
        HelixHook hook = HelixHook(vm.envAddress("HOOK"));
        MockOracle oracle = MockOracle(vm.envAddress("ORACLE"));
        PoolId poolEth = PoolId.wrap(keccak256("HELIX-SEPOLIA-ETH-USDC"));
        PoolId poolArb = PoolId.wrap(keccak256("HELIX-SEPOLIA-ARB-USDC"));

        uint256 aPk = 0xA11CE;
        uint256 bPk = 0xB0B;

        HelixTypes.Intent[] memory intents = new HelixTypes.Intent[](2);
        intents[0] = _intent(vm.addr(aPk), poolEth, 1); // alice hedges in ETH/USDC
        intents[1] = _intent(vm.addr(bPk), poolArb, 2); // bob hedges in ARB/USDC (anti-correlated)

        bytes32 ds = hook.domainSeparatorV4();
        bytes[] memory sigs = new bytes[](2);
        sigs[0] = _sign(aPk, ds, intents[0]);
        sigs[1] = _sign(bPk, ds, intents[1]);

        HelixTypes.PoolConfig memory cfg = HelixTypes.PoolConfig({
            epochLength: 1 days,
            rho: 7_500,
            marginRatioBps: 500,
            maxDivergenceBps: 300,
            initialized: true
        });

        vm.startBroadcast();
        hook.setPoolConfig(poolEth, cfg);
        hook.setPoolConfig(poolArb, cfg);
        oracle.setPrice(poolEth, 1e18);
        oracle.setPrice(poolArb, 1e18);
        bytes32 matchId = hook.submitMatch(intents, sigs);
        vm.stopBroadcast();

        console2.log("CROSS-POOL basket live. matchId:");
        console2.logBytes32(matchId);
        console2.log("pool A (ETH/USDC):");
        console2.logBytes32(PoolId.unwrap(poolEth));
        console2.log("pool B (ARB/USDC):");
        console2.logBytes32(PoolId.unwrap(poolArb));
    }

    function _intent(address lp, PoolId pool, uint256 nonce) internal view returns (HelixTypes.Intent memory) {
        return HelixTypes.Intent({
            lp: lp,
            pool: pool,
            maxDriftBps: 2_000,
            minDuration: 3_600,
            maxSize: 1_000e18,
            repFloor: 0,
            nonce: nonce,
            deadline: uint64(block.timestamp + 30 days)
        });
    }

    function _sign(uint256 pk, bytes32 ds, HelixTypes.Intent memory intent) internal view returns (bytes memory) {
        bytes32 digest = MessageHashUtils.toTypedDataHash(ds, IntentLib.hash(intent));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }
}
