// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console2} from "forge-std/Test.sol";
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

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/interfaces/callback/IUnlockCallback.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/types/BalanceDelta.sol";
import {ModifyLiquidityParams, SwapParams} from "v4-core/types/PoolOperation.sol";
import {IERC20Minimal} from "v4-core/interfaces/external/IERC20Minimal.sol";

/// @notice Minimal unlock-callback router: provides liquidity and swaps through the real PoolManager.
contract Router is IUnlockCallback {
    using BalanceDeltaLibrary for BalanceDelta;

    IPoolManager public immutable manager;

    constructor(IPoolManager _m) {
        manager = _m;
    }

    struct Liq {
        PoolKey key;
        ModifyLiquidityParams params;
        bytes hookData;
        address payer;
    }

    struct Swp {
        PoolKey key;
        SwapParams params;
        address payer;
    }

    function modifyLiquidity(PoolKey memory key, ModifyLiquidityParams memory params, bytes memory hookData, address payer)
        external
    {
        manager.unlock(abi.encode(uint8(0), abi.encode(Liq(key, params, hookData, payer))));
    }

    function swap(PoolKey memory key, SwapParams memory params, address payer) external {
        manager.unlock(abi.encode(uint8(1), abi.encode(Swp(key, params, payer))));
    }

    function unlockCallback(bytes calldata raw) external override returns (bytes memory) {
        require(msg.sender == address(manager), "router: not manager");
        (uint8 kind, bytes memory inner) = abi.decode(raw, (uint8, bytes));
        if (kind == 0) {
            Liq memory d = abi.decode(inner, (Liq));
            (BalanceDelta delta,) = manager.modifyLiquidity(d.key, d.params, d.hookData);
            _settleDelta(d.key, delta, d.payer);
        } else {
            Swp memory d = abi.decode(inner, (Swp));
            BalanceDelta delta = manager.swap(d.key, d.params, "");
            _settleDelta(d.key, delta, d.payer);
        }
        return "";
    }

    function _settleDelta(PoolKey memory key, BalanceDelta delta, address payer) internal {
        int128 d0 = delta.amount0();
        int128 d1 = delta.amount1();
        if (d0 < 0) _pay(key.currency0, payer, uint256(uint128(-d0)));
        if (d1 < 0) _pay(key.currency1, payer, uint256(uint128(-d1)));
        if (d0 > 0) manager.take(key.currency0, payer, uint256(uint128(d0)));
        if (d1 > 0) manager.take(key.currency1, payer, uint256(uint128(d1)));
    }

    /// @dev Pay a debt to the PoolManager (sync → transfer → settle), pulling from `payer` if external.
    function _pay(Currency currency, address payer, uint256 amount) internal {
        manager.sync(currency);
        if (payer == address(this)) {
            IERC20Minimal(Currency.unwrap(currency)).transfer(address(manager), amount);
        } else {
            IERC20Minimal(Currency.unwrap(currency)).transferFrom(payer, address(manager), amount);
        }
        manager.settle();
    }
}

/// @notice Full Helix lifecycle against the REAL Uniswap v4 PoolManager on a Sepolia fork:
///         initialize a pool with the hook → two LPs enter via real afterAddLiquidity → a real swap drives
///         afterSwap/TWAP → settle redistributes IL and conserves value. Proves the hook is load-bearing
///         on canonical Uniswap, not just a mock. Skips cleanly without FORK_RPC_URL.
contract ForkLifecycle is Test {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    address internal constant POOL_MANAGER = 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543; // Sepolia v4

    uint160 internal constant HOOK_FLAGS = Hooks.AFTER_INITIALIZE_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG
        | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG | Hooks.AFTER_SWAP_FLAG;

    IPoolManager internal pm;
    Router internal router;
    MockERC20 internal token0;
    MockERC20 internal valueToken; // currency1 == margin token
    MockOracle internal oracle;
    CircuitBreaker internal breaker;
    ReputationAccumulator internal reputation;
    SettlementRegistry internal registry;
    HelixHook internal hook;
    PoolKey internal key;
    PoolId internal poolId;

    address internal alice;
    uint256 internal alicePk;
    address internal bob;
    uint256 internal bobPk;

    function _skipIfNoFork() internal returns (bool) {
        string memory rpc = vm.envOr("FORK_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true);
            return true;
        }
        vm.createSelectFork(rpc);
        return false;
    }

    function _deploy() internal {
        pm = IPoolManager(POOL_MANAGER);
        router = new Router(pm);

        MockERC20 a = new MockERC20("Token A", "TKA", 18);
        MockERC20 b = new MockERC20("USD Value", "USDV", 18);
        // sort: currency0 < currency1
        (token0, valueToken) = address(a) < address(b) ? (a, b) : (b, a);

        oracle = new MockOracle();
        breaker = new CircuitBreaker(0.3e18, 0.01e18, 0.02e18, 0.05e18);
        reputation = new ReputationAccumulator();
        registry = new SettlementRegistry(address(valueToken), 50);

        HelixTypes.PoolConfig memory cfg = HelixTypes.PoolConfig({
            epochLength: 1 hours,
            rho: 10_000,
            marginRatioBps: 500,
            maxDivergenceBps: 1000, // generous: real pool price vs oracle can differ on a fork
            initialized: false
        });
        address hookAddr = address(uint160(HOOK_FLAGS) | (uint160(0x7777) << 144));
        deployCodeTo(
            "HelixHook.sol:HelixHook",
            abi.encode(pm, oracle, breaker, reputation, registry, cfg, address(this)),
            hookAddr
        );
        hook = HelixHook(hookAddr);
        breaker.setHook(hookAddr);
        reputation.setHook(hookAddr);
        registry.setHook(hookAddr);

        key = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(valueToken)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(hookAddr)
        });
        poolId = key.toId();

        // Initialize at price 1.0 (tick 0) → afterInitialize binds config.
        pm.initialize(key, TickMath.getSqrtPriceAtTick(0));
        oracle.setPrice(poolId, 1e18);
    }

    function _fund(address who) internal {
        token0.mint(who, 1_000_000e18);
        valueToken.mint(who, 1_000_000e18);
        vm.startPrank(who);
        token0.approve(address(router), type(uint256).max);
        valueToken.approve(address(router), type(uint256).max);
        valueToken.approve(address(registry), type(uint256).max); // margin
        vm.stopPrank();
    }

    function _intent(address lp, uint128 size, uint256 nonce) internal view returns (HelixTypes.Intent memory) {
        return HelixTypes.Intent({
            lp: lp,
            pool: poolId,
            maxDriftBps: 5_000,
            minDuration: 1,
            maxSize: size,
            repFloor: 0,
            nonce: nonce,
            deadline: uint64(block.timestamp + 1 days)
        });
    }

    function _sign(uint256 pk, HelixTypes.Intent memory it) internal view returns (bytes memory) {
        bytes32 digest = MessageHashUtils.toTypedDataHash(hook.domainSeparatorV4(), IntentLib.hash(it));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    function test_fork_fullLifecycleAgainstRealV4() public {
        if (_skipIfNoFork()) return;
        _deploy();
        (alice, alicePk) = makeAddrAndKey("fork-alice");
        (bob, bobPk) = makeAddrAndKey("fork-bob");
        _fund(alice);
        _fund(bob);
        _fund(address(this)); // this swaps

        // 1) submitMatch (PENDING)
        HelixTypes.Intent[] memory intents = new HelixTypes.Intent[](2);
        bytes[] memory sigs = new bytes[](2);
        intents[0] = _intent(alice, 100_000e18, 1);
        intents[1] = _intent(bob, 100_000e18, 2);
        sigs[0] = _sign(alicePk, intents[0]);
        sigs[1] = _sign(bobPk, intents[1]);
        bytes32 matchId = hook.submitMatch(intents, sigs);

        // 2) Both LPs add liquidity through the REAL PoolManager (different ranges ⇒ different IL profiles).
        //    afterAddLiquidity fires with the real BalanceDelta → entry + margin escrow.
        _addLiquidity(alice, matchId, -6000, 6000, 1e21); // wide range
        _addLiquidity(bob, matchId, -3000, 3000, 1e21); //   tighter range ⇒ different IL profile

        HelixTypes.Match memory m = hook.getMatch(matchId);
        assertEq(uint8(m.status), uint8(HelixTypes.MatchStatus.OPEN), "basket OPEN on real pool");
        assertEq(m.enteredCount, 2);

        uint256 totalMargin = registry.marginOf(matchId, alice) + registry.marginOf(matchId, bob);
        assertEq(valueToken.balanceOf(address(registry)), totalMargin, "escrow == sum of margins");

        // 3) A real swap moves the price and drives afterSwap (TWAP + breaker + PriceObserved).
        vm.warp(block.timestamp + 60);
        // Exact-input token0 swap, capped at tick -1500 (~0.86) so the price move stays modest (> 0).
        router.swap(
            key,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -200e18,
                sqrtPriceLimitX96: TickMath.getSqrtPriceAtTick(-1500)
            }),
            address(this)
        );
        (uint160 sqrtP,,,) = pm.getSlot0(poolId);
        uint256 poolPrice = _priceFromSqrt(sqrtP);
        assertLt(poolPrice, 1e18, "real swap moved the pool price (afterSwap fired)");
        oracle.setPrice(poolId, poolPrice); // align reference with the realized pool price
        console2.log("pool price after swap (WAD):", poolPrice);

        // 4) Settle against the real basket.
        vm.warp(m.epochEnd + 1);
        uint256 a0 = valueToken.balanceOf(alice);
        uint256 b0 = valueToken.balanceOf(bob);
        address settler = makeAddr("settler");
        vm.prank(settler);
        hook.settle(matchId);

        uint256 outA = valueToken.balanceOf(alice) - a0;
        uint256 outB = valueToken.balanceOf(bob) - b0;
        uint256 feeOut = valueToken.balanceOf(settler);
        assertLe(outA + outB + feeOut, totalMargin, "conservation on real pool");

        m = hook.getMatch(matchId);
        assertEq(uint8(m.status), uint8(HelixTypes.MatchStatus.SETTLED), "settled");
        assertEq(reputation.scoreOf(alice), 1);
        assertEq(reputation.scoreOf(bob), 1);

        console2.log("== Helix full lifecycle against real Sepolia v4 PoolManager ==");
        console2.log("alice margin / returned:", registry.marginOf(matchId, alice), outA);
        console2.log("bob   returned:", outB);
        console2.log("settler fee:", feeOut);
    }

    function _addLiquidity(address lp, bytes32 matchId, int24 tl, int24 tu, uint128 liq) internal {
        vm.prank(lp);
        router.modifyLiquidity(
            key,
            ModifyLiquidityParams({tickLower: tl, tickUpper: tu, liquidityDelta: int256(uint256(liq)), salt: bytes32(0)}),
            abi.encode(matchId, lp),
            lp
        );
    }

    function _priceFromSqrt(uint160 sqrtPriceX96) internal pure returns (uint256) {
        uint256 s = uint256(sqrtPriceX96);
        uint256 num = Math.mulDiv(s, s, 1 << 96);
        return Math.mulDiv(num, 1e18, 1 << 96);
    }
}
