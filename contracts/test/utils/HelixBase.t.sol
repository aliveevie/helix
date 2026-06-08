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
import {ModifyLiquidityParams, SwapParams} from "v4-core/types/PoolOperation.sol";

/// @notice Shared deployment + EIP-712 + v4-callback harness for the Helix test suite.
abstract contract HelixBase is Test {
    using PoolIdLibrary for PoolKey;

    // Permission bits this hook deploys to (afterInitialize | afterAddLiquidity | beforeRemoveLiquidity | afterSwap).
    uint160 internal constant HOOK_FLAGS =
        Hooks.AFTER_INITIALIZE_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
        | Hooks.AFTER_SWAP_FLAG;

    uint256 internal constant WAD = 1e18;

    MockERC20 internal token0;
    MockERC20 internal valueToken; // token1 / margin token (18-dec ⇒ scale == 1)
    MockOracle internal oracle;
    MockPoolManager internal pm;
    CircuitBreaker internal breaker;
    ReputationAccumulator internal reputation;
    SettlementRegistry internal registry;
    HelixHook internal hook;

    PoolKey internal key;
    PoolId internal poolId;

    address internal reactiveProxy = makeAddr("reactiveProxy");

    uint16 internal constant SETTLER_FEE_BPS = 50; // 0.5%

    function deployHelix() internal {
        token0 = new MockERC20("Token0", "TK0", 18);
        valueToken = new MockERC20("USD Value", "USDV", 18);
        oracle = new MockOracle();
        pm = new MockPoolManager();
        breaker = new CircuitBreaker(0.3e18, 0.01e18, 0.02e18, 0.05e18);
        reputation = new ReputationAccumulator();
        registry = new SettlementRegistry(address(valueToken), SETTLER_FEE_BPS);

        HelixTypes.PoolConfig memory cfg = HelixTypes.PoolConfig({
            epochLength: 1 days,
            rho: 10_000, //          full mutualization by default
            marginRatioBps: 500, //  5% baseline margin
            maxDivergenceBps: 300, // 3% chainlink/TWAP divergence tolerance
            initialized: false
        });

        // Deploy the hook at an address whose low bits encode the declared permissions.
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
        hook.setReactiveProxy(reactiveProxy);

        // Sort currencies and build the pool key.
        (Currency c0, Currency c1) = address(token0) < address(valueToken)
            ? (Currency.wrap(address(token0)), Currency.wrap(address(valueToken)))
            : (Currency.wrap(address(valueToken)), Currency.wrap(address(token0)));
        key = PoolKey({currency0: c0, currency1: c1, fee: 3000, tickSpacing: 60, hooks: IHooks(hookAddr)});
        poolId = key.toId();

        // Initialize the pool through the hook (binds config).
        vm.prank(address(pm));
        hook.afterInitialize(address(this), key, sqrtPriceFromWad(1e18), 0);
    }

    // --------------------------------------------------------------- helpers

    function makeLp(string memory label) internal returns (address addr, uint256 pk) {
        (addr, pk) = makeAddrAndKey(label);
        valueToken.mint(addr, 1_000_000e18);
        vm.prank(addr);
        valueToken.approve(address(registry), type(uint256).max);
    }

    function buildIntent(address lp, uint128 size, uint256 driftBps, uint16 repFloor, uint256 nonce)
        internal
        view
        returns (HelixTypes.Intent memory)
    {
        return HelixTypes.Intent({
            lp: lp,
            pool: poolId,
            maxDriftBps: driftBps,
            minDuration: 1 hours,
            maxSize: size,
            repFloor: repFloor,
            nonce: nonce,
            deadline: uint64(block.timestamp + 1 days)
        });
    }

    function signIntent(uint256 pk, HelixTypes.Intent memory intent) internal view returns (bytes memory) {
        bytes32 digest = MessageHashUtils.toTypedDataHash(hook.domainSeparatorV4(), IntentLib.hash(intent));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    /// @notice Drive the v4 afterAddLiquidity callback for `lp` entering `matchId` with (x0,y0).
    function enterMember(bytes32 matchId, address lp, uint256 x0, uint256 y0) internal {
        BalanceDelta delta = toBalanceDelta(-int128(int256(x0)), -int128(int256(y0)));
        ModifyLiquidityParams memory params =
            ModifyLiquidityParams({tickLower: -60, tickUpper: 60, liquidityDelta: 1e18, salt: bytes32(0)});
        vm.prank(address(pm));
        hook.afterAddLiquidity(lp, key, params, delta, toBalanceDelta(0, 0), abi.encode(matchId, lp));
    }

    /// @notice Enter a member with a balanced LP composition of `notional` value at the current oracle price.
    function enterBalanced(bytes32 matchId, address lp, uint256 notional) internal {
        uint256 p0 = oracle.price(poolId);
        uint256 y0 = notional / 2;
        uint256 x0 = Math.mulDiv(notional / 2, WAD, p0);
        enterMember(matchId, lp, x0, y0);
    }

    /// @notice Drive an afterSwap observation by setting the mock pool spot price first.
    function observeSwap(uint256 priceWad) internal {
        pm.setSlot0(poolId, sqrtPriceFromWad(priceWad));
        ModifyLiquidityParams memory _p;
        SwapParams memory sp = SwapParams({zeroForOne: true, amountSpecified: -1e18, sqrtPriceLimitX96: 0});
        vm.prank(address(pm));
        hook.afterSwap(address(this), key, sp, toBalanceDelta(0, 0), "");
        _p; // silence
    }

    function sqrtPriceFromWad(uint256 priceWad) internal pure returns (uint160) {
        // sqrtPriceX96 = sqrt(price/1e18) · 2^96 = sqrt(price · 2^192 / 1e18)
        return uint160(Math.sqrt(Math.mulDiv(priceWad, 1 << 192, WAD)));
    }
}
