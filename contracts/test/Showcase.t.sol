// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {HelixBase} from "./utils/HelixBase.t.sol";
import {console2} from "forge-std/console2.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {HelixTypes} from "../src/libraries/HelixTypes.sol";
import {ILMath} from "../src/libraries/ILMath.sol";
import {Mutualization} from "../src/libraries/Mutualization.sol";

/// @notice The Helix value loop, made visible. Run with `forge test --match-contract Showcase -vvv`.
///         Three LPs in the SAME pool enter at very different prices, so at settlement their impermanent
///         loss is wildly dispersed. ρ-mutualization redistributes value so every member converges to the
///         basket's capital-weighted average IL — and the on-chain `settle()` pays out exactly that.
contract Showcase is HelixBase {
    using Math for uint256;

    address internal alice;
    uint256 internal alicePk;
    address internal bob;
    uint256 internal bobPk;
    address internal carol;
    uint256 internal carolPk;

    function setUp() public {
        deployHelix();
        (alice, alicePk) = makeLp("alice");
        (bob, bobPk) = makeLp("bob");
        (carol, carolPk) = makeLp("carol");
    }

    function test_showcase_ilConverges() public {
        // ---- form the basket: 3 LPs, equal 1000-notional ----
        HelixTypes.Intent[] memory intents = new HelixTypes.Intent[](3);
        bytes[] memory sigs = new bytes[](3);
        intents[0] = buildIntent(alice, 2000e18, 9000, 0, 1);
        intents[1] = buildIntent(bob, 2000e18, 9000, 0, 2);
        intents[2] = buildIntent(carol, 2000e18, 9000, 0, 3);
        sigs[0] = signIntent(alicePk, intents[0]);
        sigs[1] = signIntent(bobPk, intents[1]);
        sigs[2] = signIntent(carolPk, intents[2]);
        bytes32 matchId = hook.submitMatch(intents, sigs);

        // Each LP enters at a very different price → very different IL exposure.
        uint256[3] memory entryPrice = [uint256(1e18), 2e18, 0.5e18];
        address[3] memory lps = [alice, bob, carol];
        for (uint256 i; i < 3; ++i) {
            oracle.setPrice(poolId, entryPrice[i]);
            enterBalanced(matchId, lps[i], 1000e18);
        }

        // ---- settle at a single price; recompute the math the hook will run ----
        uint256 p1 = 1.2e18;
        uint256[] memory il = new uint256[](3);
        uint256[] memory sizes = new uint256[](3);
        uint256 ilTotal;
        for (uint256 i; i < 3; ++i) {
            (uint256 x0, uint256 y0) = _balanced(1000e18, entryPrice[i]);
            il[i] = ILMath.il(x0, y0, p1);
            sizes[i] = 1000e18;
            ilTotal += il[i];
        }
        int256[] memory adj = Mutualization.adjustments(il, sizes, 10_000); // ρ = 100%

        console2.log("=== Helix value loop: 3 LPs, one pool, different entry prices, settle @ 1.2 ===");
        console2.log("LP      entryPx   standalone IL(1e18)   IL rate(bps)");
        uint256[] memory rateBefore = new uint256[](3);
        for (uint256 i; i < 3; ++i) {
            rateBefore[i] = il[i] * 10_000 / sizes[i];
            console2.log(_row(i), entryPrice[i], il[i], rateBefore[i]);
        }
        console2.log("basket total IL:", ilTotal, " capital-weighted avg rate(bps):", ilTotal * 10_000 / 3000e18);

        console2.log("--- after rho=100%% mutualization (effective IL = IL - adjustment) ---");
        uint256[] memory rateAfter = new uint256[](3);
        for (uint256 i; i < 3; ++i) {
            uint256 eff = uint256(int256(il[i]) - adj[i]);
            rateAfter[i] = eff * 10_000 / sizes[i];
            console2.log(_row(i), " effective IL:", eff, _signed("  adj:", adj[i]));
        }
        uint256 varBefore = _variance(rateBefore);
        uint256 varAfter = _variance(rateAfter);
        console2.log("IL-rate variance  before:", varBefore, " after:", varAfter);
        console2.log("variance reduction (bps of 1e4):", varBefore == 0 ? 0 : (varBefore - varAfter) * 10_000 / varBefore);

        // every member converges to the same effective IL rate
        assertApproxEqAbs(rateAfter[0], rateAfter[1], 1, "alice == bob effective rate");
        assertApproxEqAbs(rateAfter[1], rateAfter[2], 1, "bob == carol effective rate");
        assertLt(varAfter, varBefore / 100, "variance collapses by >100x");

        // ---- prove it on-chain: settle() pays out exactly this, conserving value ----
        HelixTypes.Match memory m = hook.getMatch(matchId);
        uint256 totalMargin;
        uint256[3] memory before;
        for (uint256 i; i < 3; ++i) {
            totalMargin += registry.marginOf(matchId, lps[i]);
            before[i] = valueToken.balanceOf(lps[i]);
        }
        oracle.setPrice(poolId, p1);
        vm.warp(m.epochEnd + 1);
        address settler = makeAddr("settler");
        vm.prank(settler);
        hook.settle(matchId);

        uint256 paidOut = valueToken.balanceOf(settler);
        for (uint256 i; i < 3; ++i) {
            paidOut += valueToken.balanceOf(lps[i]) - before[i];
        }
        assertEq(paidOut, totalMargin, "on-chain conservation: payouts == margins");
        console2.log("on-chain settle: conservation holds, payouts == margins:", totalMargin);
    }

    function _balanced(uint256 notional, uint256 p0) internal pure returns (uint256 x0, uint256 y0) {
        y0 = notional / 2;
        x0 = Math.mulDiv(notional / 2, 1e18, p0);
    }

    function _variance(uint256[] memory xs) internal pure returns (uint256) {
        uint256 n = xs.length;
        uint256 mean;
        for (uint256 i; i < n; ++i) {
            mean += xs[i];
        }
        mean /= n;
        uint256 v;
        for (uint256 i; i < n; ++i) {
            uint256 d = xs[i] > mean ? xs[i] - mean : mean - xs[i];
            v += d * d;
        }
        return v / n;
    }

    function _row(uint256 i) internal pure returns (string memory) {
        return i == 0 ? "alice  " : i == 1 ? "bob    " : "carol  ";
    }

    function _signed(string memory label, int256 v) internal pure returns (string memory) {
        return string.concat(label, v >= 0 ? "+" : "-", vm.toString(uint256(v >= 0 ? v : -v)));
    }
}
