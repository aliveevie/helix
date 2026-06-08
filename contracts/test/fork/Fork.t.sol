// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {ChainlinkOracle} from "../../src/ChainlinkOracle.sol";
import {AggregatorV3Interface} from "../../src/interfaces/IHelixOracle.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";

/// @notice Fork tests against a live Chainlink feed (and optionally a live v4 PoolManager).
/// @dev Configure via env and run, e.g.:
///        FORK_RPC_URL=$MAINNET_RPC \
///        CHAINLINK_FEED=0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419 \  # ETH/USD on Ethereum mainnet
///        forge test --match-path "test/fork/*"
///      With no FORK_RPC_URL/CHAINLINK_FEED the tests skip cleanly (so CI stays green offline).
contract ForkTest is Test {
    using StateLibrary for IPoolManager;

    PoolId internal constant POOL = PoolId.wrap(bytes32(uint256(1)));

    function _fork() internal returns (bool ok) {
        string memory rpc = vm.envOr("FORK_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true);
            return false;
        }
        vm.createSelectFork(rpc);
        return true;
    }

    function test_fork_chainlinkOracleReadsLiveFeed() public {
        if (!_fork()) return;
        address feed = vm.envOr("CHAINLINK_FEED", address(0));
        if (feed == address(0)) {
            vm.skip(true);
            return;
        }

        ChainlinkOracle oracle = new ChainlinkOracle(365 days);
        oracle.setFeed(POOL, feed, false);

        uint256 p = oracle.price(POOL);
        assertGt(p, 0, "live feed price must be positive");
        // Sanity band: a USD-quoted feed normalized to WAD should land in a wide but finite range.
        assertGt(p, 1e15, "price too small");
        assertLt(p, 1e30, "price too large");
        emit log_named_uint("ChainlinkOracle price (WAD)", p);
    }

    function test_fork_poolManagerSlot0Readable() public {
        if (!_fork()) return;
        address pm = vm.envOr("POOL_MANAGER", address(0));
        bytes32 rawPool = vm.envOr("POOL_ID", bytes32(0));
        if (pm == address(0) || rawPool == bytes32(0)) {
            vm.skip(true);
            return;
        }
        (uint160 sqrtPriceX96,,,) = IPoolManager(pm).getSlot0(PoolId.wrap(rawPool));
        assertGt(uint256(sqrtPriceX96), 0, "live pool must be initialized");
        emit log_named_uint("sqrtPriceX96", uint256(sqrtPriceX96));
    }
}
