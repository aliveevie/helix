// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {HelixBase} from "../utils/HelixBase.t.sol";
import {HelixTypes} from "../../src/libraries/HelixTypes.sol";

/// @notice Fuzz: random baskets, entry prices, sizes and settlement prices must always conserve value.
contract ConservationFuzz is HelixBase {
    address[] internal lps;
    uint256[] internal pks;

    function setUp() public {
        deployHelix();
        // A wide drift tolerance so margins are sized to cover the fuzzed price band.
        for (uint256 i; i < 6; ++i) {
            (address a, uint256 k) = makeLp(string(abi.encodePacked("lp", vm.toString(i))));
            lps.push(a);
            pks.push(k);
        }
    }

    function testFuzz_settlementConservesValue(
        uint8 nRaw,
        uint256 seed,
        uint256 p1Raw
    ) public {
        uint256 n = bound(nRaw, 2, 6);
        uint256 p1 = bound(p1Raw, 0.6e18, 1.8e18);

        HelixTypes.Intent[] memory intents = new HelixTypes.Intent[](n);
        bytes[] memory sigs = new bytes[](n);
        uint256[] memory notionals = new uint256[](n);
        uint256[] memory entryPrices = new uint256[](n);

        for (uint256 i; i < n; ++i) {
            // Generous drift bound (300%) ⇒ requiredRatio margins cover the fuzzed band comfortably.
            intents[i] = buildIntent(lps[i], 80_000e18, 30_000, 0, 100 + i);
            sigs[i] = signIntent(pks[i], intents[i]);
            notionals[i] = bound(uint256(keccak256(abi.encode(seed, "n", i))), 100e18, 40_000e18);
            entryPrices[i] = bound(uint256(keccak256(abi.encode(seed, "p", i))), 0.6e18, 1.8e18);
        }

        bytes32 matchId = hook.submitMatch(intents, sigs);

        for (uint256 i; i < n; ++i) {
            oracle.setPrice(poolId, entryPrices[i]);
            enterBalanced(matchId, lps[i], notionals[i]);
        }

        // Total escrow equals the sum of posted margins.
        uint256 totalMargin;
        for (uint256 i; i < n; ++i) {
            totalMargin += registry.marginOf(matchId, lps[i]);
        }
        assertEq(valueToken.balanceOf(address(registry)), totalMargin, "escrow == sum of margins");

        HelixTypes.Match memory m = hook.getMatch(matchId);
        oracle.setPrice(poolId, p1);
        vm.warp(m.epochEnd + 1);

        uint256[] memory before = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            before[i] = valueToken.balanceOf(lps[i]);
        }
        address settler = makeAddr("settler");

        vm.prank(settler);
        hook.settle(matchId);

        uint256 paidOut = valueToken.balanceOf(settler); // settler fee
        for (uint256 i; i < n; ++i) {
            paidOut += valueToken.balanceOf(lps[i]) - before[i];
            assertEq(registry.marginOf(matchId, lps[i]), 0, "margin cleared");
        }

        // CONSERVATION: total out never exceeds total in (exact at scale==1).
        assertLe(paidOut, totalMargin, "payouts <= deposits");
        assertEq(paidOut, totalMargin, "exact conservation at scale==1");
    }
}
