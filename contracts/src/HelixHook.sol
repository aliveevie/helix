// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseHook} from "./base/BaseHook.sol";
import {IHelixHook} from "./interfaces/IHelixHook.sol";
import {ICircuitBreaker} from "./interfaces/ICircuitBreaker.sol";
import {IReputation} from "./interfaces/IReputation.sol";
import {ISettlementRegistry} from "./interfaces/ISettlementRegistry.sol";
import {IHelixOracle} from "./interfaces/IHelixOracle.sol";
import {HelixTypes} from "./libraries/HelixTypes.sol";
import {IntentLib} from "./libraries/IntentLib.sol";
import {ILMath} from "./libraries/ILMath.sol";
import {Mutualization} from "./libraries/Mutualization.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/types/BalanceDelta.sol";
import {ModifyLiquidityParams, SwapParams} from "v4-core/types/PoolOperation.sol";

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title HelixHook
/// @notice Uniswap v4 hook that mutualizes impermanent loss across a matched basket of positions and
///         redistributes value at settlement so each member converges toward the basket's capital-weighted
///         average IL. Redistribution is self-funded from settlement margins and is zero-sum by construction.
contract HelixHook is BaseHook, IHelixHook, EIP712, ReentrancyGuard {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using BalanceDeltaLibrary for BalanceDelta;
    using HelixTypes for *;

    uint256 internal constant WAD = 1e18;
    uint256 internal constant BPS = 10_000;

    // --- Control-plane wiring ---
    ICircuitBreaker public immutable breaker;
    IReputation public immutable reputation;
    ISettlementRegistry public immutable registry;
    IHelixOracle public immutable oracle;

    address public owner;
    address public reactiveCallbackProxy; // the only address allowed to call triggerRebalance
    uint16 public earlyExitForfeitBps = 2_000; // 20% margin slice forfeited on early exit
    uint64 public entryWindow = 1 hours; // after this, an unopened PENDING match can be cancelled

    HelixTypes.PoolConfig public defaultConfig;

    // --- State ---
    mapping(PoolId => HelixTypes.PoolConfig) public poolConfig;
    mapping(bytes32 => HelixTypes.Match) internal _matches;
    mapping(bytes32 => HelixTypes.PositionRecord) public positions; // positionKey => record
    mapping(bytes32 => bytes32) public positionToMatch; // positionKey => matchId (exclusivity)
    mapping(address => mapping(uint256 => bool)) public nonceUsed; // lp => nonce => used

    // TWAP accumulator per pool + per-match open baseline.
    struct Obs {
        uint256 cumulative; // Σ price·dt
        uint256 lastPrice;
        uint64 lastTs;
    }

    mapping(PoolId => Obs) public obs;
    mapping(bytes32 => uint256) public openCum; // matchId => cumulative at open
    mapping(bytes32 => uint64) public openTs; //  matchId => timestamp at open

    uint256 internal _matchNonce;

    modifier onlyOwner() {
        require(msg.sender == owner, "HELIX: only owner");
        _;
    }

    constructor(
        IPoolManager _poolManager,
        IHelixOracle _oracle,
        ICircuitBreaker _breaker,
        IReputation _reputation,
        ISettlementRegistry _registry,
        HelixTypes.PoolConfig memory _defaultConfig
    ) BaseHook(_poolManager) EIP712("Helix", "1") {
        oracle = _oracle;
        breaker = _breaker;
        reputation = _reputation;
        registry = _registry;
        require(_defaultConfig.maxDivergenceBps > 0 && _defaultConfig.maxDivergenceBps <= BPS, "HELIX: cfg div");
        require(_defaultConfig.rho <= BPS, "HELIX: cfg rho");
        defaultConfig = _defaultConfig;
        owner = msg.sender;
    }

    // ============================================================ Admin

    function setReactiveProxy(address proxy) external onlyOwner {
        reactiveCallbackProxy = proxy;
    }

    function setDefaultConfig(HelixTypes.PoolConfig calldata cfg) external onlyOwner {
        require(cfg.maxDivergenceBps > 0 && cfg.maxDivergenceBps <= BPS && cfg.rho <= BPS, "HELIX: cfg");
        defaultConfig = cfg;
    }

    /// @notice Override a specific pool's config (only before it is initialized via the hook).
    function setPoolConfig(PoolId pool, HelixTypes.PoolConfig calldata cfg) external onlyOwner {
        require(!poolConfig[pool].initialized, "HELIX: pool live");
        require(cfg.maxDivergenceBps > 0 && cfg.maxDivergenceBps <= BPS && cfg.rho <= BPS, "HELIX: cfg");
        poolConfig[pool] = cfg;
    }

    function setEarlyExitForfeitBps(uint16 bps) external onlyOwner {
        require(bps <= 5_000, "HELIX: forfeit");
        earlyExitForfeitBps = bps;
    }

    function setEntryWindow(uint64 window) external onlyOwner {
        require(window > 0, "HELIX: window");
        entryWindow = window;
    }

    // ============================================================ Hook permissions

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: true,
            beforeAddLiquidity: false,
            afterAddLiquidity: true,
            beforeRemoveLiquidity: true,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // ============================================================ v4 lifecycle callbacks

    /// @notice Bind pool-level config when the pool is initialized.
    function afterInitialize(address, PoolKey calldata key, uint160, int24)
        external
        override
        onlyPoolManager
        returns (bytes4)
    {
        PoolId id = key.toId();
        HelixTypes.PoolConfig memory cfg = poolConfig[id];
        if (cfg.epochLength == 0) cfg = defaultConfig; // fall back to protocol defaults
        cfg.initialized = true;
        poolConfig[id] = cfg;
        return IHooks.afterInitialize.selector;
    }

    /// @notice Finalize a member's entry into a pending match: snapshot, size margin, escrow it.
    /// @dev hookData = abi.encode(bytes32 matchId, address lp). Entry token amounts are read from `delta`.
    function afterAddLiquidity(
        address,
        PoolKey calldata key,
        ModifyLiquidityParams calldata,
        BalanceDelta delta,
        BalanceDelta,
        bytes calldata hookData
    ) external override onlyPoolManager returns (bytes4, BalanceDelta) {
        if (hookData.length == 64) {
            (bytes32 matchId, address lp) = abi.decode(hookData, (bytes32, address));
            _enter(key.toId(), matchId, lp, delta);
        }
        return (IHooks.afterAddLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    /// @notice Update the pool TWAP accumulator, feed the breaker, and emit a PriceObserved event.
    function afterSwap(address, PoolKey calldata key, SwapParams calldata, BalanceDelta, bytes calldata)
        external
        override
        onlyPoolManager
        returns (bytes4, int128)
    {
        PoolId id = key.toId();
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(id);
        uint256 price = _priceFromSqrt(sqrtPriceX96);
        if (price > 0) {
            _observe(id, price);
            breaker.onPriceObserved(id, price);
            emit PriceObserved(id, price, _currentCumulative(id, uint64(block.timestamp)), uint64(block.timestamp));
        }
        return (IHooks.afterSwap.selector, int128(0));
    }

    /// @notice Protect open baskets: a matched position cannot be withdrawn mid-epoch.
    /// @dev hookData = abi.encode(bytes32 matchId) (optional). Use `earlyExit` to leave a live match.
    function beforeRemoveLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata hookData)
        external
        view
        override
        onlyPoolManager
        returns (bytes4)
    {
        if (hookData.length >= 32) {
            bytes32 matchId = abi.decode(hookData, (bytes32));
            HelixTypes.Match storage m = _matches[matchId];
            if (m.status == HelixTypes.MatchStatus.OPEN && block.timestamp < m.epochEnd) {
                revert PositionInOpenMatch();
            }
        }
        return IHooks.beforeRemoveLiquidity.selector;
    }

    // ============================================================ Matching

    /// @inheritdoc IHelixHook
    function submitMatch(HelixTypes.Intent[] calldata intents, bytes[] calldata signatures)
        external
        override
        nonReentrant
        returns (bytes32 matchId)
    {
        uint256 n = intents.length;
        require(n >= 2 && n == signatures.length, "HELIX: basket size");

        PoolId pool = intents[0].pool;
        HelixTypes.PoolConfig memory cfg = poolConfig[pool];
        require(cfg.initialized, "HELIX: pool uninit");
        if (breaker.state(pool) != ICircuitBreaker.State.NORMAL) revert BreakerNotNormal();

        address[] memory lps = new address[](n);
        uint256[] memory sizes = new uint256[](n);
        uint256 worstDrift;
        uint16 maxRepFloor;
        uint64 maxMinDuration;

        for (uint256 i; i < n; ++i) {
            HelixTypes.Intent calldata it = intents[i];
            _consumeIntent(it, signatures[i], pool, i);
            lps[i] = it.lp;
            sizes[i] = it.maxSize; // notional cap; refined to actual at entry
            if (it.maxDriftBps > worstDrift) worstDrift = it.maxDriftBps;
            if (it.repFloor > maxRepFloor) maxRepFloor = it.repFloor;
            if (it.minDuration > maxMinDuration) maxMinDuration = it.minDuration;
        }

        // Counterparty reputation floor: every member must clear the strictest floor in the basket.
        for (uint256 i; i < n; ++i) {
            if (reputation.scoreOf(lps[i]) < maxRepFloor) revert ConstraintViolated(i);
        }

        uint16 requiredRatioBps = _requiredRatioBps(cfg, worstDrift);

        matchId = keccak256(abi.encode(address(this), block.chainid, ++_matchNonce, pool, lps));
        HelixTypes.Match storage m = _matches[matchId];
        m.pool = pool;
        m.createdAt = uint64(block.timestamp);
        m.rho = cfg.rho;
        m.requiredRatioBps = requiredRatioBps;
        m.minDuration = maxMinDuration;
        m.status = HelixTypes.MatchStatus.PENDING;
        m.lps = lps;
        m.sizes = sizes;
        m.keys = new bytes32[](n);

        emit MatchSubmitted(matchId, pool, lps, sizes, cfg.rho);
    }

    /// @dev Verify one intent's pool, deadline, size, nonce and EIP-712 signature, then consume the nonce.
    function _consumeIntent(HelixTypes.Intent calldata it, bytes calldata sig, PoolId pool, uint256 i) internal {
        if (PoolId.unwrap(it.pool) != PoolId.unwrap(pool)) revert ConstraintViolated(i);
        if (block.timestamp > it.deadline) revert IntentExpired(i);
        if (it.maxSize == 0) revert ConstraintViolated(i);
        if (nonceUsed[it.lp][it.nonce]) revert NonceUsed(i);

        bytes32 digest = _hashTypedDataV4(IntentLib.hash(it));
        (address signer, ECDSA.RecoverError err,) = ECDSA.tryRecover(digest, sig);
        if (err != ECDSA.RecoverError.NoError || signer != it.lp) revert BadSignature(i);

        nonceUsed[it.lp][it.nonce] = true;
    }

    /// @dev Finalize one member's liquidity entry (called from afterAddLiquidity).
    function _enter(PoolId pool, bytes32 matchId, address lp, BalanceDelta delta) internal {
        HelixTypes.Match storage m = _matches[matchId];
        require(m.status == HelixTypes.MatchStatus.PENDING, "HELIX: not pending");
        require(PoolId.unwrap(m.pool) == PoolId.unwrap(pool), "HELIX: wrong pool");

        uint256 idx = _memberIndex(m, lp);

        bytes32 key = _positionKey(lp, pool, matchId, idx);
        require(!positions[key].entered, "HELIX: entered");

        // Entry token amounts: for an add, the LP's delta is negative (tokens paid into the pool).
        uint256 x0 = _abs(delta.amount0());
        uint256 y0 = _abs(delta.amount1());
        uint256 p0 = oracle.price(pool);
        require(p0 > 0, "HELIX: p0");

        uint256 notional = y0 + Math.mulDiv(x0, p0, WAD);
        require(notional > 0 && notional <= m.sizes[idx], "HELIX: notional");

        uint256 marginWad = Math.mulDiv(notional, m.requiredRatioBps, BPS);

        positions[key] = HelixTypes.PositionRecord({
            x0: x0,
            y0: y0,
            entryPrice: p0,
            entryTime: uint64(block.timestamp),
            margin: marginWad,
            lp: lp,
            entered: true
        });
        positionToMatch[key] = matchId;
        m.keys[idx] = key;
        m.sizes[idx] = notional; // refine cap → actual notional
        m.enteredCount += 1;

        registry.depositMargin(matchId, lp, marginWad);
        emit PositionEntered(matchId, lp, x0, y0, p0);

        if (m.enteredCount == m.lps.length) {
            HelixTypes.PoolConfig memory cfg = poolConfig[pool];
            uint64 dur = cfg.epochLength > m.minDuration ? cfg.epochLength : m.minDuration;
            m.epochEnd = uint64(block.timestamp) + dur;
            m.status = HelixTypes.MatchStatus.OPEN;
            openCum[matchId] = _currentCumulative(pool, uint64(block.timestamp));
            openTs[matchId] = uint64(block.timestamp);
            emit MatchOpened(matchId, m.epochEnd);
        }
    }

    // ============================================================ Settlement

    /// @inheritdoc IHelixHook
    function settle(bytes32 matchId) external override nonReentrant {
        HelixTypes.Match storage m = _matches[matchId];
        if (m.status != HelixTypes.MatchStatus.OPEN) revert MatchNotOpen();
        if (block.timestamp < m.epochEnd) revert EpochNotEnded();

        // Oracle-resistant price: cross-check Chainlink reference against the pool TWAP.
        uint256 pChain = oracle.price(m.pool);
        uint256 pTwap = _twapForMatch(matchId, m.pool, pChain);
        uint256 diff = pChain > pTwap ? pChain - pTwap : pTwap - pChain;
        if (Math.mulDiv(diff, BPS, pChain) > poolConfig[m.pool].maxDivergenceBps) revert OracleDivergence();
        uint256 p1 = (pChain + pTwap) / 2; // minimum-disagreement midpoint

        // Collect entered members, compute IL and adjustments over the live basket only.
        uint256 nEntered = m.enteredCount;
        require(nEntered > 0, "HELIX: empty basket");
        address[] memory lps = new address[](nEntered);
        uint256[] memory il = new uint256[](nEntered);
        uint256[] memory sizes = new uint256[](nEntered);

        uint256 ilTotal;
        uint256 j;
        for (uint256 i; i < m.keys.length; ++i) {
            HelixTypes.PositionRecord storage pos = positions[m.keys[i]];
            if (!pos.entered) continue;
            uint256 ili = ILMath.il(pos.x0, pos.y0, p1);
            lps[j] = pos.lp;
            il[j] = ili;
            sizes[j] = m.sizes[i];
            ilTotal += ili;
            unchecked {
                ++j;
            }
        }

        int256[] memory adjustments = Mutualization.adjustments(il, sizes, m.rho);

        m.status = HelixTypes.MatchStatus.SETTLED; // effects before external calls

        registry.applyRedistribution(matchId, lps, adjustments, msg.sender, ilTotal);

        // Reputation: credit members who honored the match to settlement.
        for (uint256 i; i < nEntered; ++i) {
            reputation.credit(lps[i], 1);
        }

        emit MatchSettled(matchId, p1, ilTotal, msg.sender);
    }

    /// @notice Leave a live basket early: forfeit a margin slice and take a reputation penalty.
    function earlyExit(bytes32 matchId) external nonReentrant {
        HelixTypes.Match storage m = _matches[matchId];
        require(m.status == HelixTypes.MatchStatus.OPEN, "HELIX: not open");
        require(block.timestamp < m.epochEnd, "HELIX: epoch over");

        uint256 idx = _memberIndex(m, msg.sender);
        bytes32 key = m.keys[idx];
        HelixTypes.PositionRecord storage pos = positions[key];
        require(pos.entered, "HELIX: not entered");

        pos.entered = false;
        m.enteredCount -= 1;
        m.sizes[idx] = 0;

        reputation.penalize(msg.sender, 2);
        registry.forfeitMargin(matchId, msg.sender, earlyExitForfeitBps);
        emit EarlyExit(matchId, msg.sender, earlyExitForfeitBps);
    }

    /// @inheritdoc IHelixHook
    /// @dev Refunds entered members in full (0-bps forfeit): the basket never started, so no penalty.
    function cancelMatch(bytes32 matchId) external override nonReentrant {
        HelixTypes.Match storage m = _matches[matchId];
        if (m.status != HelixTypes.MatchStatus.PENDING) revert NotPending();
        if (block.timestamp <= uint256(m.createdAt) + entryWindow) revert EntryWindowOpen();

        m.status = HelixTypes.MatchStatus.CANCELLED; // effects before external calls

        for (uint256 i; i < m.keys.length; ++i) {
            bytes32 key = m.keys[i];
            if (key == bytes32(0)) continue; // member never entered
            HelixTypes.PositionRecord storage pos = positions[key];
            if (!pos.entered) continue;
            pos.entered = false;
            registry.forfeitMargin(matchId, pos.lp, 0); // full refund
        }
        emit MatchCancelled(matchId);
    }

    // ============================================================ Reactive control plane

    /// @inheritdoc IHelixHook
    function triggerRebalance(bytes32 matchId, uint8 action) external override {
        if (msg.sender != reactiveCallbackProxy) revert NotReactive();
        HelixTypes.Match storage m = _matches[matchId];
        HelixTypes.RebalanceAction a = HelixTypes.RebalanceAction(action);
        m.pending = a;

        if (a == HelixTypes.RebalanceAction.PAUSE) {
            breaker.forcePause(m.pool);
        } else if (a == HelixTypes.RebalanceAction.RESUME) {
            breaker.forceResume(m.pool);
        }
        // RE_MATCH is consumed by the off-chain engine, which observes the queued action.
        emit RebalanceTriggered(matchId, a);
    }

    // ============================================================ Views & helpers

    /// @inheritdoc IHelixHook
    function getMatch(bytes32 matchId) external view override returns (HelixTypes.Match memory) {
        return _matches[matchId];
    }

    /// @inheritdoc IHelixHook
    function domainSeparatorV4() external view override returns (bytes32) {
        return _domainSeparatorV4();
    }

    function positionKey(address lp, PoolId pool, bytes32 matchId, uint256 idx) external pure returns (bytes32) {
        return _positionKey(lp, pool, matchId, idx);
    }

    function _positionKey(address lp, PoolId pool, bytes32 matchId, uint256 idx) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(lp, PoolId.unwrap(pool), matchId, idx));
    }

    function _memberIndex(HelixTypes.Match storage m, address lp) internal view returns (uint256) {
        uint256 len = m.lps.length;
        for (uint256 i; i < len; ++i) {
            if (m.lps[i] == lp) return i;
        }
        revert("HELIX: not member");
    }

    /// @dev requiredRatio covers ρ·worst-IL plus the settler-fee headroom, floored at the config margin.
    function _requiredRatioBps(HelixTypes.PoolConfig memory cfg, uint256 worstDriftBps)
        internal
        view
        returns (uint16)
    {
        uint256 fMaxWad = ILMath.maxILFraction(worstDriftBps);
        uint256 fMaxBps = Math.mulDiv(fMaxWad, BPS, WAD);
        uint256 coverBps = Math.mulDiv(uint256(cfg.rho) + registry.settlerFeeBps(), fMaxBps, BPS);
        uint256 r = coverBps > cfg.marginRatioBps ? coverBps : cfg.marginRatioBps;
        if (r > BPS) r = BPS; // cap at 100% of notional
        return uint16(r);
    }

    // --- TWAP accumulator ---

    function _observe(PoolId id, uint256 price) internal {
        Obs storage o = obs[id];
        if (o.lastTs != 0) {
            o.cumulative += o.lastPrice * (block.timestamp - o.lastTs);
        }
        o.lastPrice = price;
        o.lastTs = uint64(block.timestamp);
    }

    function _currentCumulative(PoolId id, uint64 ts) internal view returns (uint256) {
        Obs storage o = obs[id];
        if (o.lastTs == 0 || ts <= o.lastTs) return o.cumulative;
        return o.cumulative + o.lastPrice * (ts - o.lastTs);
    }

    /// @dev Time-weighted pool price over the match's life; falls back to the reference price if the
    ///      pool has produced no usable observation window.
    function _twapForMatch(bytes32 matchId, PoolId pool, uint256 fallbackPrice) internal view returns (uint256) {
        uint64 t0 = openTs[matchId];
        uint256 c0 = openCum[matchId];
        uint64 nowTs = uint64(block.timestamp);
        if (nowTs <= t0) return fallbackPrice;
        uint256 cNow = _currentCumulative(pool, nowTs);
        if (cNow <= c0) return fallbackPrice;
        uint256 twap = (cNow - c0) / (nowTs - t0);
        return twap == 0 ? fallbackPrice : twap;
    }

    /// @dev price = (sqrtPriceX96² / 2¹⁹²)·1e18, token1-per-token0 (assumes 18-dec value units).
    function _priceFromSqrt(uint160 sqrtPriceX96) internal pure returns (uint256) {
        uint256 s = uint256(sqrtPriceX96);
        uint256 num = Math.mulDiv(s, s, 1 << 96); // s²/2⁹⁶
        return Math.mulDiv(num, WAD, 1 << 96); //    (s²/2¹⁹²)·1e18
    }

    function _abs(int128 x) internal pure returns (uint256) {
        return x < 0 ? uint256(uint128(-x)) : uint256(uint128(x));
    }
}
