// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {PoolId} from "v4-core/types/PoolId.sol";

/// @notice Minimal Chainlink AggregatorV3 surface used by the Helix oracle adapter.
interface AggregatorV3Interface {
    function decimals() external view returns (uint8);
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

/// @notice Reference-price source consumed by the Helix hook at entry and settlement.
/// @dev Returns price as token1-per-token0, WAD (1e18) scaled.
interface IHelixOracle {
    /// @notice Latest reference price for `pool`, WAD scaled (token1 per token0).
    function price(PoolId pool) external view returns (uint256);
}
