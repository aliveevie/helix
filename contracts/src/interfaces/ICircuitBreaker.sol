// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {PoolId} from "v4-core/types/PoolId.sol";

/// @title ICircuitBreaker
/// @notice Per-pool volatility finite-state machine with hysteresis.
interface ICircuitBreaker {
    enum State {
        NORMAL, //   new matches + settlement + rebalance allowed
        ELEVATED, // settlement + rebalance allowed; new matches paused
        HALTED //    open positions protected; only settlement of expired matches allowed

    }

    event StateChanged(PoolId indexed pool, State indexed from, State indexed to, uint256 volIndex);
    event ForcedState(PoolId indexed pool, State indexed to);

    /// @notice Current breaker state for `pool`.
    function state(PoolId pool) external view returns (State);

    /// @notice Feed a fresh price observation; updates the vol index and may transition state.
    function onPriceObserved(PoolId pool, uint256 price) external;

    /// @notice Rolling volatility index (WAD) for `pool`.
    function volIndex(PoolId pool) external view returns (uint256);

    /// @notice Force a PAUSE (→HALTED) or RESUME (→NORMAL); callable only by the authorized hook.
    function forcePause(PoolId pool) external;
    function forceResume(PoolId pool) external;
}
