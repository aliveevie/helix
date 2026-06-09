// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {ChainlinkOracle} from "../src/ChainlinkOracle.sol";
import {PoolId} from "v4-core/types/PoolId.sol";

/// @notice Deploy a live ChainlinkOracle bound to the canonical Sepolia ETH/USD Data Feed, proving the
///         oracle plane runs on a real Chainlink feed (not a mock).
contract DeployChainlink is Script {
    // Chainlink ETH/USD on Sepolia.
    address internal constant ETH_USD_FEED = 0x694AA1769357215DE4FAC081bf1f309aDC325306;

    function run() external {
        PoolId pool = PoolId.wrap(keccak256("HELIX-ETH-USDC-CHAINLINK"));

        vm.startBroadcast();
        ChainlinkOracle oracle = new ChainlinkOracle(1 days);
        oracle.setFeed(pool, ETH_USD_FEED, false);
        vm.stopBroadcast();

        console2.log("ChainlinkOracle:", address(oracle));
        console2.log("demo poolId:");
        console2.logBytes32(PoolId.unwrap(pool));
        console2.log("live ETH/USD price (WAD):", oracle.price(pool));
    }
}
