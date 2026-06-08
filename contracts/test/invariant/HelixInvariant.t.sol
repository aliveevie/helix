// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import {HelixHook} from "../../src/HelixHook.sol";
import {CircuitBreaker} from "../../src/CircuitBreaker.sol";
import {ReputationAccumulator} from "../../src/ReputationAccumulator.sol";
import {SettlementRegistry} from "../../src/SettlementRegistry.sol";
import {HelixTypes} from "../../src/libraries/HelixTypes.sol";
import {IntentLib} from "../../src/libraries/IntentLib.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockOracle} from "../../src/mocks/MockOracle.sol";
import {MockPoolManager} from "../../src/mocks/MockPoolManager.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {BalanceDelta, toBalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";

/// @notice Drives randomized create→enter→settle/earlyExit sequences and records value-flow ghosts.
contract HelixHandler is Test {
    using PoolIdLibrary for PoolKey;

    HelixHook public hook;
    SettlementRegistry public registry;
    MockOracle public oracle;
    MockPoolManager public pm;
    MockERC20 public valueToken;
    PoolKey public key;
    PoolId public poolId;

    address[] public lps;
    uint256[] internal pks;
    uint256 internal nonceCursor = 1;

    bytes32[] public openMatches;
    bytes32[] public allMatches;
    mapping(bytes32 => bool) public isSettled;

    // Ghost accounting.
    uint256 public totalDeposited;
    uint256 public totalPaidOut;

    constructor(
        HelixHook _hook,
        SettlementRegistry _registry,
        MockOracle _oracle,
        MockPoolManager _pm,
        MockERC20 _valueToken,
        PoolKey memory _key,
        address[] memory _lps,
        uint256[] memory _pks
    ) {
        hook = _hook;
        registry = _registry;
        oracle = _oracle;
        pm = _pm;
        valueToken = _valueToken;
        key = _key;
        poolId = _key.toId();
        lps = _lps;
        pks = _pks;
    }

    function _sign(uint256 pk, HelixTypes.Intent memory intent) internal view returns (bytes memory) {
        bytes32 digest = MessageHashUtils.toTypedDataHash(hook.domainSeparatorV4(), IntentLib.hash(intent));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    function _enter(bytes32 matchId, address lp, uint256 notional, uint256 p0) internal {
        oracle.setPrice(poolId, p0);
        uint256 y0 = notional / 2;
        uint256 x0 = Math.mulDiv(notional / 2, 1e18, p0);
        BalanceDelta delta = toBalanceDelta(-int128(int256(x0)), -int128(int256(y0)));
        ModifyLiquidityParams memory params =
            ModifyLiquidityParams({tickLower: -60, tickUpper: 60, liquidityDelta: 1e18, salt: bytes32(0)});
        uint256 balBefore = valueToken.balanceOf(address(registry));
        vm.prank(address(pm));
        hook.afterAddLiquidity(lp, key, params, delta, toBalanceDelta(0, 0), abi.encode(matchId, lp));
        totalDeposited += valueToken.balanceOf(address(registry)) - balBefore;
    }

    /// @notice Create a 2–3 member match and enter all members at randomized entry prices.
    function createAndEnter(uint256 seed) public {
        uint256 n = bound(seed, 2, 3);
        HelixTypes.Intent[] memory intents = new HelixTypes.Intent[](n);
        bytes[] memory sigs = new bytes[](n);
        for (uint256 i; i < n; ++i) {
            address lp = lps[(seed + i) % lps.length];
            uint256 pk = pks[(seed + i) % lps.length];
            intents[i] = HelixTypes.Intent({
                lp: lp,
                pool: poolId,
                maxDriftBps: 30_000,
                minDuration: 1 hours,
                maxSize: 80_000e18,
                repFloor: 0,
                nonce: nonceCursor++,
                deadline: uint64(block.timestamp + 365 days)
            });
            sigs[i] = _sign(pk, intents[i]);
        }
        // Distinct LPs required (a member can't be matched against themselves in one basket here).
        if (n == 3 && (intents[0].lp == intents[1].lp || intents[1].lp == intents[2].lp || intents[0].lp == intents[2].lp))
        {
            return;
        }
        if (intents[0].lp == intents[1].lp) return;

        try hook.submitMatch(intents, sigs) returns (bytes32 matchId) {
            for (uint256 i; i < n; ++i) {
                uint256 notional = bound(uint256(keccak256(abi.encode(seed, i))), 100e18, 30_000e18);
                uint256 p0 = bound(uint256(keccak256(abi.encode(seed, "p", i))), 0.7e18, 1.5e18);
                _enter(matchId, intents[i].lp, notional, p0);
            }
            openMatches.push(matchId);
            allMatches.push(matchId);
        } catch {}
    }

    /// @notice Settle a pending open match after warping past its epoch; verifies idempotency.
    function settle(uint256 seed) public {
        if (openMatches.length == 0) return;
        uint256 idx = seed % openMatches.length;
        bytes32 matchId = openMatches[idx];
        HelixTypes.Match memory m = hook.getMatch(matchId);
        if (m.status != HelixTypes.MatchStatus.OPEN) {
            _removeOpen(idx);
            return;
        }
        if (block.timestamp <= m.epochEnd) vm.warp(m.epochEnd + 1);
        oracle.setPrice(poolId, bound(uint256(keccak256(abi.encode(seed, "s"))), 0.7e18, 1.5e18));

        uint256 balBefore = valueToken.balanceOf(address(registry));
        try hook.settle(matchId) {
            totalPaidOut += balBefore - valueToken.balanceOf(address(registry));
            isSettled[matchId] = true;
            _removeOpen(idx);
            // Idempotency: a settled match must not settle again.
            try hook.settle(matchId) {
                revert("idempotency violated");
            } catch {}
        } catch {}
    }

    /// @notice A random member leaves a live match early (forfeit + penalty).
    function earlyExit(uint256 seed) public {
        if (openMatches.length == 0) return;
        bytes32 matchId = openMatches[seed % openMatches.length];
        HelixTypes.Match memory m = hook.getMatch(matchId);
        if (m.status != HelixTypes.MatchStatus.OPEN || block.timestamp >= m.epochEnd) return;
        address lp = m.lps[seed % m.lps.length];
        if (registry.marginOf(matchId, lp) == 0) return;

        uint256 balBefore = valueToken.balanceOf(address(registry));
        vm.prank(lp);
        try hook.earlyExit(matchId) {
            totalPaidOut += balBefore - valueToken.balanceOf(address(registry));
        } catch {}
    }

    /// @notice Create a 2-member match, enter only one member, then cancel it after the entry window.
    function createPartialThenCancel(uint256 seed) public {
        address lp0 = lps[seed % lps.length];
        uint256 k0 = pks[seed % lps.length];
        address lp1 = lps[(seed + 1) % lps.length];
        uint256 k1 = pks[(seed + 1) % lps.length];
        if (lp0 == lp1) return;

        HelixTypes.Intent[] memory intents = new HelixTypes.Intent[](2);
        bytes[] memory sigs = new bytes[](2);
        intents[0] = _intent(lp0, nonceCursor++);
        intents[1] = _intent(lp1, nonceCursor++);
        sigs[0] = _sign(k0, intents[0]);
        sigs[1] = _sign(k1, intents[1]);

        try hook.submitMatch(intents, sigs) returns (bytes32 matchId) {
            uint256 notional = bound(uint256(keccak256(abi.encode(seed, "pc"))), 100e18, 30_000e18);
            uint256 p0 = bound(uint256(keccak256(abi.encode(seed, "pcp"))), 0.7e18, 1.5e18);
            _enter(matchId, lp0, notional, p0); // only lp0 enters ⇒ stuck PENDING

            vm.warp(block.timestamp + 2 hours); // past the entry window
            uint256 balBefore = valueToken.balanceOf(address(registry));
            try hook.cancelMatch(matchId) {
                totalPaidOut += balBefore - valueToken.balanceOf(address(registry));
            } catch {}
        } catch {}
    }

    function _intent(address lp, uint256 nonce) internal view returns (HelixTypes.Intent memory) {
        return HelixTypes.Intent({
            lp: lp,
            pool: poolId,
            maxDriftBps: 30_000,
            minDuration: 1 hours,
            maxSize: 80_000e18,
            repFloor: 0,
            nonce: nonce,
            deadline: uint64(block.timestamp + 365 days)
        });
    }

    function _removeOpen(uint256 idx) internal {
        openMatches[idx] = openMatches[openMatches.length - 1];
        openMatches.pop();
    }

    function allMatchesLength() external view returns (uint256) {
        return allMatches.length;
    }

    function liveMargin() external view returns (uint256 sum) {
        for (uint256 i; i < allMatches.length; ++i) {
            HelixTypes.Match memory m = hook.getMatch(allMatches[i]);
            for (uint256 j; j < m.lps.length; ++j) {
                sum += registry.marginOf(allMatches[i], m.lps[j]);
            }
        }
    }
}

/// @notice Invariant suite: global conservation, margin solvency and settlement idempotency.
contract HelixInvariant is Test {
    using PoolIdLibrary for PoolKey;

    uint160 internal constant HOOK_FLAGS =
        Hooks.AFTER_INITIALIZE_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
        | Hooks.AFTER_SWAP_FLAG;

    MockERC20 internal token0;
    MockERC20 internal valueToken;
    MockOracle internal oracle;
    MockPoolManager internal pm;
    CircuitBreaker internal breaker;
    ReputationAccumulator internal reputation;
    SettlementRegistry internal registry;
    HelixHook internal hook;
    HelixHandler internal handler;
    PoolKey internal key;
    PoolId internal poolId;

    function setUp() public {
        token0 = new MockERC20("Token0", "TK0", 18);
        valueToken = new MockERC20("USD Value", "USDV", 18);
        oracle = new MockOracle();
        pm = new MockPoolManager();
        breaker = new CircuitBreaker(0.3e18, 0.01e18, 0.02e18, 0.05e18);
        reputation = new ReputationAccumulator();
        registry = new SettlementRegistry(address(valueToken), 50);

        HelixTypes.PoolConfig memory cfg = HelixTypes.PoolConfig({
            epochLength: 1 days,
            rho: 10_000,
            marginRatioBps: 500,
            maxDivergenceBps: 300,
            initialized: false
        });
        address hookAddr = address(uint160(HOOK_FLAGS) | (uint160(0x4444) << 144));
        deployCodeTo(
            "HelixHook.sol:HelixHook",
            abi.encode(IPoolManager(address(pm)), oracle, breaker, reputation, registry, cfg),
            hookAddr
        );
        hook = HelixHook(hookAddr);
        breaker.setHook(hookAddr);
        reputation.setHook(hookAddr);
        registry.setHook(hookAddr);

        (Currency c0, Currency c1) = address(token0) < address(valueToken)
            ? (Currency.wrap(address(token0)), Currency.wrap(address(valueToken)))
            : (Currency.wrap(address(valueToken)), Currency.wrap(address(token0)));
        key = PoolKey({currency0: c0, currency1: c1, fee: 3000, tickSpacing: 60, hooks: IHooks(hookAddr)});
        poolId = key.toId();
        vm.prank(address(pm));
        hook.afterInitialize(address(this), key, uint160(1 << 96), 0);

        address[] memory lps = new address[](4);
        uint256[] memory pks = new uint256[](4);
        for (uint256 i; i < 4; ++i) {
            (address a, uint256 k) = makeAddrAndKey(string(abi.encodePacked("lp", vm.toString(i))));
            lps[i] = a;
            pks[i] = k;
            valueToken.mint(a, 1e30);
            vm.prank(a);
            valueToken.approve(address(registry), type(uint256).max);
        }

        handler = new HelixHandler(hook, registry, oracle, pm, valueToken, key, lps, pks);
        targetContract(address(handler));
    }

    /// @notice The registry never pays out more than was ever deposited; its balance reconciles exactly.
    function invariant_globalConservation() public view {
        assertLe(handler.totalPaidOut(), handler.totalDeposited(), "out <= in");
        assertEq(
            valueToken.balanceOf(address(registry)),
            handler.totalDeposited() - handler.totalPaidOut(),
            "registry balance reconciles"
        );
    }

    /// @notice Escrowed balance always fully backs every live margin obligation.
    function invariant_marginSolvency() public view {
        assertGe(valueToken.balanceOf(address(registry)), handler.liveMargin(), "escrow backs live margins");
    }
}
