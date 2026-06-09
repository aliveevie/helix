// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {ReputationAccumulator} from "../../src/ReputationAccumulator.sol";

/// @notice ERC-8004 Reputation Registry conformance for ReputationAccumulator (permissionless tagged
///         feedback + aggregation), plus the Helix protocol-score wiring.
contract Reputation8004 is Test {
    ReputationAccumulator internal rep;
    address internal alice = makeAddr("alice");
    address internal hook = makeAddr("hook");
    address internal client = makeAddr("client");

    function setUp() public {
        rep = new ReputationAccumulator();
        rep.setHook(hook);
    }

    function test_giveFeedback_storedAndAggregated() public {
        uint256 agent = rep.agentIdOf(alice);

        vm.prank(client);
        rep.giveFeedback(agent, 80, 0, "quality", "", "", "ipfs://a", bytes32(0));
        vm.prank(client);
        rep.giveFeedback(agent, 20, 0, "quality", "", "", "ipfs://b", bytes32(0));

        assertEq(rep.getLastIndex(agent, client), 2);
        address[] memory clients = rep.getClients(agent);
        assertEq(clients.length, 1);
        assertEq(clients[0], client);

        address[] memory empty;
        (uint64 count, int128 sum,) = rep.getSummary(agent, empty, "quality", "");
        assertEq(count, 2);
        assertEq(sum, 100);

        (int128 v,,,, bool revoked) = rep.readFeedback(agent, client, 0);
        assertEq(v, 80);
        assertFalse(revoked);
    }

    function test_revokeFeedback_excludedFromSummary() public {
        uint256 agent = rep.agentIdOf(alice);
        vm.prank(client);
        rep.giveFeedback(agent, 50, 0, "t", "", "", "", bytes32(0));
        vm.prank(client);
        rep.revokeFeedback(agent, 0);

        address[] memory empty;
        (uint64 count, int128 sum,) = rep.getSummary(agent, empty, "", "");
        assertEq(count, 0);
        assertEq(sum, 0);
    }

    function test_tagFilter_inSummary() public {
        uint256 agent = rep.agentIdOf(alice);
        vm.startPrank(client);
        rep.giveFeedback(agent, 10, 0, "speed", "", "", "", bytes32(0));
        rep.giveFeedback(agent, 99, 0, "quality", "", "", "", bytes32(0));
        vm.stopPrank();

        address[] memory empty;
        (uint64 c1, int128 s1,) = rep.getSummary(agent, empty, "speed", "");
        assertEq(c1, 1);
        assertEq(s1, 10);
        (uint64 c2, int128 s2,) = rep.getSummary(agent, empty, "", ""); // wildcard
        assertEq(c2, 2);
        assertEq(s2, 109);
    }

    function test_helixCreditEmitsErc8004Feedback_andKeepsScore() public {
        uint256 agent = rep.agentIdOf(alice);
        vm.prank(hook);
        rep.credit(alice, 1);
        assertEq(rep.scoreOf(alice), 1); // protocol score preserved

        // the credit was also recorded as ERC-8004 feedback from the hook (the client).
        (uint64 count, int128 sum,) = rep.getSummary(agent, new address[](0), "helix", "honored");
        assertEq(count, 1);
        assertEq(sum, 1);

        vm.prank(hook);
        rep.penalize(alice, 2);
        assertEq(rep.scoreOf(alice), 0);
        (uint64 c,, ) = rep.getSummary(agent, new address[](0), "helix", "broke");
        assertEq(c, 1);
    }

    function test_revoke_revertsForNonAuthor() public {
        uint256 agent = rep.agentIdOf(alice);
        vm.prank(client);
        rep.giveFeedback(agent, 1, 0, "t", "", "", "", bytes32(0));
        vm.prank(makeAddr("other"));
        vm.expectRevert(bytes("REP: bad index")); // 'other' has no feedback at index 0
        rep.revokeFeedback(agent, 0);
    }
}
