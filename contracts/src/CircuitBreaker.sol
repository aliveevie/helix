// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ICircuitBreaker} from "./interfaces/ICircuitBreaker.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title CircuitBreaker
/// @notice Per-pool volatility FSM with hysteresis. The rolling vol index is an EMA of |price return|.
///         Separate entry/exit thresholds prevent oscillation; the resume-to-NORMAL path is reserved
///         for the RSC (via the hook), so the breaker can pause new exposure but never force an unwind.
contract CircuitBreaker is ICircuitBreaker {
    uint256 internal constant WAD = 1e18;

    /// @dev EMA smoothing factor (WAD). vol = vol·(1−α) + |ret|·α.
    uint256 public immutable alpha;
    /// @dev NORMAL→ELEVATED entry threshold (WAD).
    uint256 public immutable high;
    /// @dev ELEVATED→HALTED critical threshold (WAD).
    uint256 public immutable crit;
    /// @dev ELEVATED→NORMAL exit threshold (WAD), low < high for hysteresis.
    uint256 public immutable low;

    address public owner;
    address public hook; // authorized writer (the Helix hook)

    mapping(PoolId => State) internal _state;
    mapping(PoolId => uint256) public override volIndex;
    mapping(PoolId => uint256) internal _lastPrice;

    modifier onlyHook() {
        require(msg.sender == hook, "CB: only hook");
        _;
    }

    constructor(uint256 alpha_, uint256 low_, uint256 high_, uint256 crit_) {
        require(alpha_ > 0 && alpha_ <= WAD, "CB: alpha");
        require(low_ < high_ && high_ < crit_, "CB: thresholds");
        alpha = alpha_;
        low = low_;
        high = high_;
        crit = crit_;
        owner = msg.sender;
    }

    /// @notice One-time binding of the authorized hook.
    function setHook(address hook_) external {
        require(msg.sender == owner, "CB: only owner");
        require(hook == address(0), "CB: hook set");
        require(hook_ != address(0), "CB: zero");
        hook = hook_;
    }

    /// @inheritdoc ICircuitBreaker
    function state(PoolId pool) external view override returns (State) {
        return _state[pool];
    }

    /// @inheritdoc ICircuitBreaker
    function onPriceObserved(PoolId pool, uint256 price) external override onlyHook {
        require(price > 0, "CB: price=0");
        uint256 prev = _lastPrice[pool];
        _lastPrice[pool] = price;
        if (prev == 0) return; //                          first observation seeds last price only

        // |return| in WAD.
        uint256 diff = price > prev ? price - prev : prev - price;
        uint256 ret = Math.mulDiv(diff, WAD, prev);

        // EMA update.
        uint256 vol = Math.mulDiv(volIndex[pool], WAD - alpha, WAD) + Math.mulDiv(ret, alpha, WAD);
        volIndex[pool] = vol;

        _maybeTransition(pool, vol);
    }

    function _maybeTransition(PoolId pool, uint256 vol) internal {
        State s = _state[pool];
        State next = s;

        if (s == State.NORMAL) {
            if (vol > high) next = State.ELEVATED;
        } else if (s == State.ELEVATED) {
            if (vol > crit) next = State.HALTED;
            else if (vol < low) next = State.NORMAL;
        } else {
            // HALTED: automatic easing only down to ELEVATED; full RESUME requires the RSC.
            if (vol < high) next = State.ELEVATED;
        }

        if (next != s) {
            _state[pool] = next;
            emit StateChanged(pool, s, next, vol);
        }
    }

    /// @inheritdoc ICircuitBreaker
    function forcePause(PoolId pool) external override onlyHook {
        if (_state[pool] != State.HALTED) {
            _state[pool] = State.HALTED;
            emit ForcedState(pool, State.HALTED);
        }
    }

    /// @inheritdoc ICircuitBreaker
    function forceResume(PoolId pool) external override onlyHook {
        if (_state[pool] != State.NORMAL) {
            _state[pool] = State.NORMAL;
            emit ForcedState(pool, State.NORMAL);
        }
    }
}
