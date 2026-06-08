// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ILMath} from "../../src/libraries/ILMath.sol";
import {Mutualization} from "../../src/libraries/Mutualization.sol";

/// @notice Unit + fuzz tests for the pure accounting math (IL + zero-sum mutualization).
contract MathUnit is Test {
    uint256 internal constant WAD = 1e18;

    // --- ILMath ---

    function test_il_zeroAtEntryPrice() public pure {
        (uint256 x0, uint256 y0) = ILMath.balancedEntry(1000e18, 2e18); // notional 1000, P0=2
        assertEq(ILMath.il(x0, y0, 2e18), 0, "IL must be 0 with no price move");
    }

    function test_il_fractionSymmetricInPriceRatio() public pure {
        (uint256 x0, uint256 y0) = ILMath.balancedEntry(1000e18, 1e18);
        uint256 ilUp = ILMath.il(x0, y0, 2e18); //   price doubles  (r = 2)
        uint256 ilDown = ILMath.il(x0, y0, 0.5e18); // price halves  (r = 1/2)
        assertGt(ilUp, 0);
        assertGt(ilDown, 0);
        // Absolute IL differs (token1 value scales with price), but the IL *fraction* is symmetric in r↔1/r.
        uint256 fracUp = ilUp * WAD / (x0 * 2 + y0); //       /V_hold(2)
        uint256 fracDown = ilDown * WAD / (x0 / 2 + y0); //   /V_hold(1/2)
        assertApproxEqRel(fracUp, fracDown, 1e12);
    }

    function test_il_knownValue_2xMove() public pure {
        // Classic CPMM IL at a 2x move ≈ 5.72% of hold value.
        (uint256 x0, uint256 y0) = ILMath.balancedEntry(1000e18, 1e18); // x0=500, y0=500
        uint256 il = ILMath.il(x0, y0, 2e18);
        uint256 vHold = x0 * 2 + y0; // 500*2 + 500 = 1500
        // IL/Vhold ≈ 0.0572
        assertApproxEqRel(il * WAD / vHold, 0.0572e18, 0.01e18);
    }

    /// @dev Over the modeled domain (notional ≤ 1e27 WAD, price ∈ [1e-3, 1e3]) the closed form never
    ///      overflows and the IL identity V_pool + IL == V_hold holds exactly.
    function testFuzz_il_identityHolds(uint256 notional, uint256 p0, uint256 p1) public pure {
        notional = bound(notional, 1e6, 1e27);
        p0 = bound(p0, 1e15, 1e21);
        p1 = bound(p1, 1e15, 1e21);
        (uint256 x0, uint256 y0) = ILMath.balancedEntry(notional, p0);
        uint256 il = ILMath.il(x0, y0, p1);
        uint256 vHold = Math.mulDiv(x0, p1, WAD) + y0;
        uint256 vPool = ILMath.poolValue(x0, y0, p1);
        assertLe(vPool, vHold, "V_pool must not exceed V_hold");
        assertEq(vPool + il, vHold, "IL identity must hold exactly");
    }

    // --- Mutualization ---

    function test_adjustments_sumToZero_simple() public pure {
        uint256[] memory il = new uint256[](3);
        uint256[] memory sizes = new uint256[](3);
        il[0] = 100e18;
        il[1] = 50e18;
        il[2] = 0;
        sizes[0] = 1e18;
        sizes[1] = 1e18;
        sizes[2] = 1e18;
        int256[] memory adj = Mutualization.adjustments(il, sizes, 10_000);
        int256 sum;
        for (uint256 i; i < 3; ++i) {
            sum += adj[i];
        }
        assertEq(sum, 0, "adjustments must net to zero");
        // Worst-IL member (0) receives; best-IL member (2) pays.
        assertGt(adj[0], 0);
        assertLt(adj[2], 0);
    }

    function test_adjustments_fullMutualizationEqualizesIL() public pure {
        uint256[] memory il = new uint256[](2);
        uint256[] memory sizes = new uint256[](2);
        il[0] = 80e18;
        il[1] = 20e18;
        sizes[0] = 1e18;
        sizes[1] = 1e18;
        int256[] memory adj = Mutualization.adjustments(il, sizes, 10_000);
        // With ρ=1 and equal weights, both converge to the average IL (50). Net IL_i = il_i - adj... receive.
        // member0 had 80 (worse) ⇒ receives 30; member1 had 20 ⇒ pays 30.
        assertEq(adj[0], 30e18);
        assertEq(adj[1], -30e18);
    }

    function test_adjustments_partialRhoRetainsOutcome() public pure {
        uint256[] memory il = new uint256[](2);
        uint256[] memory sizes = new uint256[](2);
        il[0] = 80e18;
        il[1] = 20e18;
        sizes[0] = 1e18;
        sizes[1] = 1e18;
        int256[] memory adj = Mutualization.adjustments(il, sizes, 5_000); // ρ=0.5
        assertEq(adj[0], 15e18); // half of 30
        assertEq(adj[1], -15e18);
    }

    function testFuzz_adjustments_alwaysZeroSum(uint256 seed, uint256 rhoBps, uint8 nRaw) public pure {
        uint256 n = bound(nRaw, 2, 12);
        rhoBps = bound(rhoBps, 0, 10_000);
        uint256[] memory il = new uint256[](n);
        uint256[] memory sizes = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            il[i] = uint256(keccak256(abi.encode(seed, "il", i))) % 1e27;
            sizes[i] = 1 + (uint256(keccak256(abi.encode(seed, "sz", i))) % 1e24);
        }
        int256[] memory adj = Mutualization.adjustments(il, sizes, rhoBps);
        int256 sum;
        for (uint256 i; i < n; ++i) {
            sum += adj[i];
        }
        assertEq(sum, 0, "zero-sum invariant must hold for all inputs");
    }
}
