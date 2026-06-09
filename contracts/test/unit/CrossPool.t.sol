// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {HelixBase} from "../utils/HelixBase.t.sol";
import {HelixTypes} from "../../src/libraries/HelixTypes.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId} from "v4-core/types/PoolId.sol";

/// @notice Cross-pool baskets: members live in DIFFERENT pools (different assets), are each priced at
///         their own pool, and mutualize IL across the basket — the cross-asset hedge Helix is named for.
contract CrossPool is HelixBase {
    address internal alice;
    uint256 internal alicePk;
    address internal bob;
    uint256 internal bobPk;
    PoolKey internal keyB;
    PoolId internal poolIdB;

    function setUp() public {
        deployHelix();
        (alice, alicePk) = makeLp("alice");
        (bob, bobPk) = makeLp("bob");
        (keyB, poolIdB) = initSecondPool(500, 10); // a second, distinct pool sharing the hook
    }

    function test_crossPool_basketSpansTwoPoolsAndSettles() public {
        // alice's intent is for pool A, bob's for pool B — a single basket across two pools.
        HelixTypes.Intent memory ia = buildIntent(alice, 2000e18, 5000, 0, 1); // pool A (poolId)
        HelixTypes.Intent memory ib = buildIntentInPool(bob, poolIdB, 2000e18, 5000, 0, 2); // pool B
        HelixTypes.Intent[] memory intents = new HelixTypes.Intent[](2);
        bytes[] memory sigs = new bytes[](2);
        intents[0] = ia;
        intents[1] = ib;
        sigs[0] = signIntent(alicePk, ia);
        sigs[1] = signIntent(bobPk, ib);
        bytes32 matchId = hook.submitMatch(intents, sigs);

        // Enter each member in their OWN pool, both at price 1.0.
        oracle.setPrice(poolId, 1e18);
        enterMemberInPool(key, matchId, alice, 500e18, 500e18);
        oracle.setPrice(poolIdB, 1e18);
        enterMemberInPool(keyB, matchId, bob, 500e18, 500e18);

        HelixTypes.Match memory m = hook.getMatch(matchId);
        assertEq(uint8(m.status), uint8(HelixTypes.MatchStatus.OPEN), "cross-pool basket OPEN");
        assertEq(m.enteredCount, 2);
        assertTrue(PoolId.unwrap(m.pools[0]) != PoolId.unwrap(m.pools[1]), "members are in different pools");
        assertEq(PoolId.unwrap(m.pools[0]), PoolId.unwrap(poolId));
        assertEq(PoolId.unwrap(m.pools[1]), PoolId.unwrap(poolIdB));

        uint256 totalMargin = registry.marginOf(matchId, alice) + registry.marginOf(matchId, bob);

        // Asset A appreciates, asset B depreciates — each member is priced at its OWN pool.
        oracle.setPrice(poolId, 1.5e18); // pool A up
        oracle.setPrice(poolIdB, 0.7e18); // pool B down
        vm.warp(m.epochEnd + 1);

        uint256 a0 = valueToken.balanceOf(alice);
        uint256 b0 = valueToken.balanceOf(bob);
        address settler = makeAddr("settler");
        vm.prank(settler);
        hook.settle(matchId);

        uint256 paidOut = valueToken.balanceOf(settler);
        paidOut += valueToken.balanceOf(alice) - a0;
        paidOut += valueToken.balanceOf(bob) - b0;
        assertEq(paidOut, totalMargin, "conservation across a cross-pool basket");

        m = hook.getMatch(matchId);
        assertEq(uint8(m.status), uint8(HelixTypes.MatchStatus.SETTLED));
    }

    function test_crossPool_revertsIfAMemberPoolUninitialized() public {
        // bob references a pool that was never initialized via the hook ⇒ rejected.
        PoolKey memory badKey =
            PoolKey({currency0: key.currency0, currency1: key.currency1, fee: 10000, tickSpacing: 200, hooks: key.hooks});
        PoolId badId = _id(badKey);
        HelixTypes.Intent memory ia = buildIntent(alice, 2000e18, 5000, 0, 1);
        HelixTypes.Intent memory ib = buildIntentInPool(bob, badId, 2000e18, 5000, 0, 2);
        HelixTypes.Intent[] memory intents = new HelixTypes.Intent[](2);
        bytes[] memory sigs = new bytes[](2);
        intents[0] = ia;
        intents[1] = ib;
        sigs[0] = signIntent(alicePk, ia);
        sigs[1] = signIntent(bobPk, ib);
        vm.expectRevert(abi.encodeWithSignature("ConstraintViolated(uint256)", 1));
        hook.submitMatch(intents, sigs);
    }

    function _id(PoolKey memory k) internal pure returns (PoolId) {
        return PoolId.wrap(keccak256(abi.encode(k)));
    }
}
