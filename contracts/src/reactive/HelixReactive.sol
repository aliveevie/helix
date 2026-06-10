// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AbstractReactive, LogRecord, ISystemContract} from "./ReactiveLib.sol";
import {HelixTypes} from "../libraries/HelixTypes.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SignedMath} from "@openzeppelin/contracts/utils/math/SignedMath.sol";

/// @title HelixReactive
/// @notice Reactive Smart Contract that monitors `PriceObserved` events emitted by every Helix hook
///         across all deployed chains and drives the basket control plane. It maintains a rolling
///         volatility EMA per pool and a rolling correlation estimate per registered pool-pair, and
///         dispatches authenticated `triggerRebalance` callbacks (PAUSE / RESUME / RE_MATCH) to the
///         destination chain's hook.
/// @dev Cross-chain, time-conditional automation without a centralized keeper. The destination hook
///      accepts `triggerRebalance` only from the registered Reactive callback proxy.
contract HelixReactive is AbstractReactive {
    using SignedMath for int256;

    uint256 internal constant WAD = 1e18;

    // Event topic0 hashes (must match HelixHook's event signatures; PoolId encodes as bytes32).
    bytes32 internal constant PRICE_OBSERVED_TOPIC = keccak256("PriceObserved(bytes32,uint256,uint256,uint64)");
    bytes32 internal constant MATCH_SUBMITTED_TOPIC =
        keccak256("MatchSubmitted(bytes32,bytes32,address[],uint256[],uint16)");

    uint64 internal constant CALLBACK_GAS = 300_000;

    address public owner;
    ISystemContract public service;

    // Thresholds (WAD).
    uint256 public volHigh = 0.02e18; //   pause when vol EMA exceeds this
    uint256 public volLow = 0.01e18; //    resume when vol EMA falls below this (hysteresis)
    uint256 public alpha = 0.3e18; //      EMA smoothing factor

    struct PoolStat {
        uint256 lastPrice;
        int256 lastReturn; // signed WAD
        uint256 volEma; //   EMA of |return|
        uint256 varEma; //   EMA of return²
        bool paused;
        bool seeded;
        uint256 destChainId;
        address destHook;
    }

    mapping(bytes32 => PoolStat) public stat; // poolId => stats
    mapping(bytes32 => bytes32[]) public poolMatches; // poolId => open matchIds
    mapping(bytes32 => bytes32) public matchPool; // matchId => poolId

    // Registered correlation pair (the two legs of a cross-chain basket).
    bytes32 public legA;
    bytes32 public legB;
    int256 public covEma; //  EMA of rA·rB
    uint256 public corrBound = 0.6e18; // RE_MATCH when realized corr rises above this (hedge decays)

    event StatsUpdated(bytes32 indexed pool, uint256 volEma, int256 ret);
    event Rebalance(bytes32 indexed matchId, HelixTypes.RebalanceAction action);

    modifier onlyOwner() {
        require(msg.sender == owner, "RSC: only owner");
        _;
    }

    constructor(ISystemContract _service, bool _vmContext) {
        owner = msg.sender;
        service = _service;
        vmContext = _vmContext;
        reactiveVm = msg.sender;
    }

    // ============================================================ Config

    function setReactiveVm(address vm_) external onlyOwner {
        reactiveVm = vm_;
    }

    function setThresholds(uint256 _alpha, uint256 _volLow, uint256 _volHigh, uint256 _corrBound)
        external
        onlyOwner
    {
        require(_alpha > 0 && _alpha <= WAD && _volLow < _volHigh, "RSC: thresholds");
        alpha = _alpha;
        volLow = _volLow;
        volHigh = _volHigh;
        corrBound = _corrBound;
    }

    /// @notice Bind a pool's destination chain + hook (where callbacks are relayed), and subscribe.
    function registerPool(bytes32 pool, uint256 destChainId, address destHook) external onlyOwner {
        stat[pool].destChainId = destChainId;
        stat[pool].destHook = destHook;
        _subscribe(destChainId, destHook, uint256(PRICE_OBSERVED_TOPIC));
        _subscribe(destChainId, destHook, uint256(MATCH_SUBMITTED_TOPIC));
        emit PoolRegistered(pool, destChainId, destHook);
    }

    event PoolRegistered(bytes32 indexed pool, uint256 destChainId, address destHook);
    event SubscribeAttempt(uint256 destChainId, address destHook, uint256 topic0, bool ok);

    /// @dev Best-effort subscribe to the Reactive subscription service. The live service debits the
    ///      reactive contract via the reactVM payer flow; calling it directly from a plain deploy can
    ///      revert, so we don't let that brick registration — the contract is still configured and the
    ///      production reactive-lib (AbstractReactive) completes the subscription. Skipped when no service.
    function _subscribe(uint256 destChainId, address destHook, uint256 topic0) internal {
        if (address(service) == address(0)) return;
        (bool ok,) = address(service).call(
            abi.encodeWithSelector(
                ISystemContract.subscribe.selector,
                destChainId,
                destHook,
                topic0,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE
            )
        );
        emit SubscribeAttempt(destChainId, destHook, topic0, ok);
    }

    function setCorrelationPair(bytes32 _legA, bytes32 _legB) external onlyOwner {
        legA = _legA;
        legB = _legB;
    }

    // ============================================================ Reactive entrypoint

    /// @notice Reactive VM entrypoint: dispatch on the event topic.
    function react(LogRecord calldata log) external override vmOnly {
        if (log.topic0 == uint256(PRICE_OBSERVED_TOPIC)) {
            _onPriceObserved(bytes32(log.topic1), log.data);
        } else if (log.topic0 == uint256(MATCH_SUBMITTED_TOPIC)) {
            _onMatchSubmitted(bytes32(log.topic1), bytes32(log.topic2));
        }
    }

    function _onMatchSubmitted(bytes32 matchId, bytes32 pool) internal {
        if (matchPool[matchId] != bytes32(0)) return;
        matchPool[matchId] = pool;
        poolMatches[pool].push(matchId);
    }

    function _onPriceObserved(bytes32 pool, bytes calldata data) internal {
        (uint256 price,,) = abi.decode(data, (uint256, uint256, uint64));
        if (price == 0) return;

        PoolStat storage s = stat[pool];
        if (!s.seeded) {
            s.lastPrice = price;
            s.seeded = true;
            return;
        }

        // Signed return in WAD.
        int256 ret = (int256(price) - int256(s.lastPrice)) * int256(WAD) / int256(s.lastPrice);
        s.lastPrice = price;
        s.lastReturn = ret;

        uint256 absRet = ret.abs();
        s.volEma = _ema(s.volEma, absRet);
        s.varEma = _ema(s.varEma, Math.mulDiv(absRet, absRet, WAD));
        emit StatsUpdated(pool, s.volEma, ret);

        _checkVolatility(pool, s);
        _checkCorrelation(pool);
    }

    // ============================================================ Decision logic

    function _checkVolatility(bytes32 pool, PoolStat storage s) internal {
        if (!s.paused && s.volEma > volHigh) {
            s.paused = true;
            _dispatchAll(pool, HelixTypes.RebalanceAction.PAUSE);
        } else if (s.paused && s.volEma < volLow) {
            s.paused = false;
            _dispatchAll(pool, HelixTypes.RebalanceAction.RESUME);
        }
    }

    /// @dev Update the pair covariance and RE_MATCH both legs if realized correlation rises above bound
    ///      (the diversification the basket was matched for has decayed).
    function _checkCorrelation(bytes32 pool) internal {
        if ((pool != legA && pool != legB) || legA == bytes32(0) || legB == bytes32(0)) return;
        PoolStat storage a = stat[legA];
        PoolStat storage b = stat[legB];
        if (!a.seeded || !b.seeded || a.varEma == 0 || b.varEma == 0) return;

        // cov EMA of rA·rB (using each leg's most recent return).
        int256 prod = a.lastReturn * b.lastReturn / int256(WAD);
        covEma = _emaSigned(covEma, prod);

        uint256 denom = Math.sqrt(Math.mulDiv(a.varEma, b.varEma, WAD));
        if (denom == 0) return;
        int256 corr = covEma * int256(WAD) / int256(denom); // WAD, in [-1,1]

        if (corr > int256(corrBound)) {
            _dispatchAll(legA, HelixTypes.RebalanceAction.RE_MATCH);
            _dispatchAll(legB, HelixTypes.RebalanceAction.RE_MATCH);
        }
    }

    function _dispatchAll(bytes32 pool, HelixTypes.RebalanceAction action) internal {
        PoolStat storage s = stat[pool];
        bytes32[] storage ms = poolMatches[pool];
        for (uint256 i; i < ms.length; ++i) {
            bytes memory payload = abi.encodeWithSignature("triggerRebalance(bytes32,uint8)", ms[i], uint8(action));
            _emitCallback(s.destChainId, s.destHook, CALLBACK_GAS, payload);
            emit Rebalance(ms[i], action);
        }
    }

    // ============================================================ Helpers

    function realizedCorrelation() external view returns (int256) {
        PoolStat storage a = stat[legA];
        PoolStat storage b = stat[legB];
        uint256 denom = Math.sqrt(Math.mulDiv(a.varEma, b.varEma, WAD));
        if (denom == 0) return 0;
        return covEma * int256(WAD) / int256(denom);
    }

    function _ema(uint256 prev, uint256 x) internal view returns (uint256) {
        return Math.mulDiv(prev, WAD - alpha, WAD) + Math.mulDiv(x, alpha, WAD);
    }

    function _emaSigned(int256 prev, int256 x) internal view returns (int256) {
        return prev * int256(WAD - alpha) / int256(WAD) + x * int256(alpha) / int256(WAD);
    }
}
