// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {HelixBase} from "../utils/HelixBase.t.sol";
import {HelixTypes} from "../../src/libraries/HelixTypes.sol";
import {IHelixHook} from "../../src/interfaces/IHelixHook.sol";
import {ICircuitBreaker} from "../../src/interfaces/ICircuitBreaker.sol";

/// @notice Circuit-breaker FSM, RSC callback authentication, and oracle-divergence settlement guard.
contract ControlPlane is HelixBase {
    address internal alice;
    uint256 internal alicePk;
    address internal bob;
    uint256 internal bobPk;

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
        oracle.setPrice(poolId, 1e18);
        enterBalanced(matchId, alice, 1000e18);
        oracle.setPrice(poolId, 2e18);
        enterBalanced(matchId, bob, 1000e18);
    }

    // --- Breaker FSM via afterSwap ---

    function test_breaker_escalatesAndHaltsWithHysteresis() public {
        assertEq(uint8(breaker.state(poolId)), uint8(ICircuitBreaker.State.NORMAL));

        observeSwap(1e18); // seed
        observeSwap(1.1e18); // ~9% jump ⇒ EMA ~2.7% > HIGH(2%)
        assertEq(uint8(breaker.state(poolId)), uint8(ICircuitBreaker.State.ELEVATED), "to ELEVATED");

        observeSwap(1.3e18); // ~18% jump ⇒ EMA > CRIT(5%)
        assertEq(uint8(breaker.state(poolId)), uint8(ICircuitBreaker.State.HALTED), "to HALTED");
    }

    function test_breaker_blocksNewMatchesWhenNotNormal() public {
        observeSwap(1e18);
        observeSwap(1.1e18); // ELEVATED
        assertEq(uint8(breaker.state(poolId)), uint8(ICircuitBreaker.State.ELEVATED));

        HelixTypes.Intent memory ia = buildIntent(alice, 2000e18, 5000, 0, 1);
        HelixTypes.Intent memory ib = buildIntent(bob, 2000e18, 5000, 0, 2);
        HelixTypes.Intent[] memory intents = new HelixTypes.Intent[](2);
        bytes[] memory sigs = new bytes[](2);
        intents[0] = ia;
        intents[1] = ib;
        sigs[0] = signIntent(alicePk, ia);
        sigs[1] = signIntent(bobPk, ib);
        vm.expectRevert(IHelixHook.BreakerNotNormal.selector);
        hook.submitMatch(intents, sigs);
    }

    // --- RSC callback ---

    function test_triggerRebalance_onlyReactiveProxy() public {
        bytes32 matchId = _open2();
        vm.expectRevert(IHelixHook.NotReactive.selector);
        hook.triggerRebalance(matchId, uint8(HelixTypes.RebalanceAction.PAUSE));
    }

    function test_triggerRebalance_pauseAndResume() public {
        bytes32 matchId = _open2();

        vm.prank(reactiveProxy);
        hook.triggerRebalance(matchId, uint8(HelixTypes.RebalanceAction.PAUSE));
        assertEq(uint8(breaker.state(poolId)), uint8(ICircuitBreaker.State.HALTED), "RSC PAUSE halts");

        vm.prank(reactiveProxy);
        hook.triggerRebalance(matchId, uint8(HelixTypes.RebalanceAction.RESUME));
        assertEq(uint8(breaker.state(poolId)), uint8(ICircuitBreaker.State.NORMAL), "RSC RESUME restores");

        HelixTypes.Match memory m = hook.getMatch(matchId);
        assertEq(uint8(m.pending), uint8(HelixTypes.RebalanceAction.RESUME));
    }

    function test_triggerRebalance_reMatchQueued() public {
        bytes32 matchId = _open2();
        vm.prank(reactiveProxy);
        hook.triggerRebalance(matchId, uint8(HelixTypes.RebalanceAction.RE_MATCH));
        HelixTypes.Match memory m = hook.getMatch(matchId);
        assertEq(uint8(m.pending), uint8(HelixTypes.RebalanceAction.RE_MATCH), "RE_MATCH flagged for engine");
        // RE_MATCH does not change the breaker.
        assertEq(uint8(breaker.state(poolId)), uint8(ICircuitBreaker.State.NORMAL));
    }

    // --- Oracle-resistant settlement ---

    function test_settle_revertsOnOracleDivergence() public {
        bytes32 matchId = _open2();
        HelixTypes.Match memory m = hook.getMatch(matchId);

        // Build a pool TWAP around 2e18 via spaced observations.
        vm.warp(block.timestamp + 100);
        observeSwap(2e18);
        vm.warp(block.timestamp + 100);
        observeSwap(2e18);

        // Reference price wildly off the pool TWAP ⇒ settlement must refuse.
        oracle.setPrice(poolId, 1e18);
        vm.warp(m.epochEnd + 1);
        vm.expectRevert(IHelixHook.OracleDivergence.selector);
        hook.settle(matchId);
    }
}
