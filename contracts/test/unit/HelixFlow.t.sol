// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {HelixBase} from "../utils/HelixBase.t.sol";
import {HelixTypes} from "../../src/libraries/HelixTypes.sol";
import {IHelixHook} from "../../src/interfaces/IHelixHook.sol";
import {ICircuitBreaker} from "../../src/interfaces/ICircuitBreaker.sol";
import {ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";

/// @notice End-to-end match → enter → settle flow, asserting conservation, redistribution and reputation.
contract HelixFlow is HelixBase {
    address internal alice;
    uint256 internal alicePk;
    address internal bob;
    uint256 internal bobPk;
    address internal settler = makeAddr("settler");

    function setUp() public {
        deployHelix();
        (alice, alicePk) = makeLp("alice");
        (bob, bobPk) = makeLp("bob");
    }

    function _open2() internal returns (bytes32 matchId) {
        HelixTypes.Intent memory ia = buildIntent(alice, 2000e18, 5000, 0, 1);
        HelixTypes.Intent memory ib = buildIntent(bob, 2000e18, 5000, 0, 2);
        HelixTypes.Intent[] memory intents = new HelixTypes.Intent[](2);
        bytes[] memory sigs = new bytes[](2);
        intents[0] = ia;
        intents[1] = ib;
        sigs[0] = signIntent(alicePk, ia);
        sigs[1] = signIntent(bobPk, ib);
        matchId = hook.submitMatch(intents, sigs);

        // Members enter at different entry prices ⇒ different IL outcomes ⇒ real redistribution.
        oracle.setPrice(poolId, 1e18);
        enterBalanced(matchId, alice, 1000e18);
        oracle.setPrice(poolId, 2e18);
        enterBalanced(matchId, bob, 1000e18);
    }

    function test_fullFlow_conservationAndRedistribution() public {
        bytes32 matchId = _open2();

        HelixTypes.Match memory m = hook.getMatch(matchId);
        assertEq(uint8(m.status), uint8(HelixTypes.MatchStatus.OPEN), "match should be OPEN");
        assertEq(m.enteredCount, 2);

        uint256 marginA = registry.marginOf(matchId, alice);
        uint256 marginB = registry.marginOf(matchId, bob);
        uint256 totalMargin = marginA + marginB;
        assertEq(valueToken.balanceOf(address(registry)), totalMargin, "registry holds exactly the margins");

        // Settle at an intermediate price.
        oracle.setPrice(poolId, 1.5e18);
        vm.warp(m.epochEnd + 1);

        uint256 a0 = valueToken.balanceOf(alice);
        uint256 b0 = valueToken.balanceOf(bob);

        vm.prank(settler);
        hook.settle(matchId);

        uint256 outA = valueToken.balanceOf(alice) - a0;
        uint256 outB = valueToken.balanceOf(bob) - b0;
        uint256 feeOut = valueToken.balanceOf(settler);

        // CONSERVATION: total paid out never exceeds total escrowed.
        assertLe(outA + outB + feeOut, totalMargin, "payouts must not exceed deposits");
        // With an 18-decimal token (scale==1) it is exact.
        assertEq(outA + outB + feeOut, totalMargin, "exact conservation at scale==1");

        // REDISTRIBUTION direction: Alice (entered low, larger IL) is compensated; Bob (smaller IL) pays in.
        assertGt(outA, marginA, "worse-IL member receives");
        assertLt(outB, marginB, "better-IL member pays");

        // Reputation credited to both honoring members.
        assertEq(reputation.scoreOf(alice), 1);
        assertEq(reputation.scoreOf(bob), 1);

        // Idempotency: cannot settle again.
        m = hook.getMatch(matchId);
        assertEq(uint8(m.status), uint8(HelixTypes.MatchStatus.SETTLED));
        vm.expectRevert(IHelixHook.MatchNotOpen.selector);
        hook.settle(matchId);
    }

    function test_settle_revertsBeforeEpochEnd() public {
        bytes32 matchId = _open2();
        oracle.setPrice(poolId, 1.5e18);
        vm.expectRevert(IHelixHook.EpochNotEnded.selector);
        hook.settle(matchId);
    }

    function test_submitMatch_revertsOnBadSignature() public {
        HelixTypes.Intent memory ia = buildIntent(alice, 2000e18, 5000, 0, 1);
        HelixTypes.Intent memory ib = buildIntent(bob, 2000e18, 5000, 0, 2);
        HelixTypes.Intent[] memory intents = new HelixTypes.Intent[](2);
        bytes[] memory sigs = new bytes[](2);
        intents[0] = ia;
        intents[1] = ib;
        sigs[0] = signIntent(alicePk, ia);
        sigs[1] = signIntent(alicePk, ib); // wrong signer for bob's intent
        vm.expectRevert(abi.encodeWithSelector(IHelixHook.BadSignature.selector, 1));
        hook.submitMatch(intents, sigs);
    }

    function test_submitMatch_revertsOnReplayedNonce() public {
        _open2();
        // Reuse alice nonce 1.
        HelixTypes.Intent memory ia = buildIntent(alice, 2000e18, 5000, 0, 1);
        HelixTypes.Intent memory ib = buildIntent(bob, 2000e18, 5000, 0, 3);
        HelixTypes.Intent[] memory intents = new HelixTypes.Intent[](2);
        bytes[] memory sigs = new bytes[](2);
        intents[0] = ia;
        intents[1] = ib;
        sigs[0] = signIntent(alicePk, ia);
        sigs[1] = signIntent(bobPk, ib);
        vm.expectRevert(abi.encodeWithSelector(IHelixHook.NonceUsed.selector, 0));
        hook.submitMatch(intents, sigs);
    }

    function test_earlyExit_forfeitsAndPenalizes() public {
        bytes32 matchId = _open2();
        uint256 marginA = registry.marginOf(matchId, alice);
        uint256 a0 = valueToken.balanceOf(alice);

        vm.prank(alice);
        hook.earlyExit(matchId);

        // 20% forfeited, 80% returned.
        assertEq(valueToken.balanceOf(alice) - a0, marginA * 8000 / 10000, "80% returned");
        assertEq(registry.marginOf(matchId, alice), 0);
        assertEq(reputation.scoreOf(alice), 0, "no credit");

        HelixTypes.Match memory m = hook.getMatch(matchId);
        assertEq(m.enteredCount, 1, "alice removed from basket");
    }

    function test_owner_isExplicitConstructorArg() public {
        // Owner is the address passed at construction (here the test), NOT msg.sender — this guards the
        // CREATE2 footgun where msg.sender is the deterministic factory.
        assertEq(hook.owner(), address(this), "owner must be the explicit admin");

        // Owner-gated function works for the owner...
        hook.setReactiveProxy(address(0xBEEF));
        assertEq(hook.reactiveCallbackProxy(), address(0xBEEF));

        // ...and reverts for a non-owner.
        vm.prank(address(0xDEAD));
        vm.expectRevert(bytes("HELIX: only owner"));
        hook.setReactiveProxy(address(0x1234));
    }

    function test_submitMatch_revertsOnDuplicateLp() public {
        // Same LP signs two intents (distinct nonces) and both land in one basket ⇒ rejected.
        HelixTypes.Intent memory i1 = buildIntent(alice, 2000e18, 5000, 0, 1);
        HelixTypes.Intent memory i2 = buildIntent(alice, 2000e18, 5000, 0, 2);
        HelixTypes.Intent[] memory intents = new HelixTypes.Intent[](2);
        bytes[] memory sigs = new bytes[](2);
        intents[0] = i1;
        intents[1] = i2;
        sigs[0] = signIntent(alicePk, i1);
        sigs[1] = signIntent(alicePk, i2);
        vm.expectRevert(abi.encodeWithSelector(IHelixHook.ConstraintViolated.selector, 0));
        hook.submitMatch(intents, sigs);
    }

    function test_cancelMatch_refundsStuckPartialEntry() public {
        HelixTypes.Intent memory ia = buildIntent(alice, 2000e18, 5000, 0, 1);
        HelixTypes.Intent memory ib = buildIntent(bob, 2000e18, 5000, 0, 2);
        HelixTypes.Intent[] memory intents = new HelixTypes.Intent[](2);
        bytes[] memory sigs = new bytes[](2);
        intents[0] = ia;
        intents[1] = ib;
        sigs[0] = signIntent(alicePk, ia);
        sigs[1] = signIntent(bobPk, ib);
        bytes32 matchId = hook.submitMatch(intents, sigs);

        // Only alice enters; bob never does ⇒ the match is stuck PENDING with alice's margin escrowed.
        oracle.setPrice(poolId, 1e18);
        enterBalanced(matchId, alice, 1000e18);

        HelixTypes.Match memory m = hook.getMatch(matchId);
        assertEq(uint8(m.status), uint8(HelixTypes.MatchStatus.PENDING));
        uint256 marginA = registry.marginOf(matchId, alice);
        assertGt(marginA, 0);

        // Cannot cancel while the entry window is still open.
        vm.expectRevert(IHelixHook.EntryWindowOpen.selector);
        hook.cancelMatch(matchId);

        // After the window, anyone can cancel; alice is refunded in full (no penalty — basket never opened).
        uint256 a0 = valueToken.balanceOf(alice);
        vm.warp(block.timestamp + hook.entryWindow() + 1);
        hook.cancelMatch(matchId);

        assertEq(valueToken.balanceOf(alice) - a0, marginA, "alice fully refunded");
        assertEq(registry.marginOf(matchId, alice), 0);
        m = hook.getMatch(matchId);
        assertEq(uint8(m.status), uint8(HelixTypes.MatchStatus.CANCELLED));
    }

    function test_cancelMatch_revertsOnOpenMatch() public {
        bytes32 matchId = _open2();
        vm.warp(block.timestamp + hook.entryWindow() + 1);
        vm.expectRevert(IHelixHook.NotPending.selector);
        hook.cancelMatch(matchId);
    }

    function test_beforeRemoveLiquidity_protectsOpenMatch() public {
        bytes32 matchId = _open2();
        // hookData carrying the open matchId must block mid-epoch withdrawal.
        ModifyLiquidityParams memory params =
            ModifyLiquidityParams({tickLower: -60, tickUpper: 60, liquidityDelta: -1e18, salt: bytes32(0)});
        vm.prank(address(pm));
        vm.expectRevert(IHelixHook.PositionInOpenMatch.selector);
        hook.beforeRemoveLiquidity(alice, key, params, abi.encode(matchId));
    }
}
