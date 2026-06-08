// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title Mutualization
/// @notice ρ-weighted, zero-sum redistribution of impermanent loss across a matched basket.
/// @dev For a basket with capital weights wᵢ (= sizeᵢ/Σsize) and coefficient ρ ∈ [0,1]:
///        IL_total    = Σ ILᵢ
///        IL_fairᵢ    = wᵢ · IL_total
///        adjustmentᵢ = ρ · (ILᵢ − IL_fairᵢ)
///      A member whose realized IL was *worse* (higher) than its fair share gets a POSITIVE adjustment
///      (receives compensation); one that did better gets a NEGATIVE adjustment (pays in). Each member's
///      effective IL becomes ILᵢ − adjustmentᵢ = (1−ρ)·ILᵢ + ρ·IL_fairᵢ, i.e. the basket average at ρ=1.
///      Σ adjustmentᵢ = ρ·(IL_total − IL_total) = 0 in exact arithmetic. Integer rounding is swept into
///      the final member so the on-chain sum is *exactly* zero, preserving conservation.
library Mutualization {
    uint256 internal constant BPS = 10_000;

    /// @notice Compute the signed, exactly-zero-sum adjustment vector for a basket.
    /// @param il    per-member impermanent loss (WAD, ≥0)
    /// @param sizes per-member notionals (WAD); weights are derived as sizeᵢ / Σsize
    /// @param rhoBps mutualization coefficient in bps (0..10_000)
    /// @return adj  signed adjustments (WAD); positive = member receives, negative = member pays
    function adjustments(uint256[] memory il, uint256[] memory sizes, uint256 rhoBps)
        internal
        pure
        returns (int256[] memory adj)
    {
        uint256 n = il.length;
        require(n == sizes.length && n > 0, "Mutualization: length");

        uint256 ilTotal;
        uint256 sizeTotal;
        for (uint256 i; i < n; ++i) {
            ilTotal += il[i];
            sizeTotal += sizes[i];
        }
        require(sizeTotal > 0, "Mutualization: zero size");

        adj = new int256[](n);
        int256 running;
        // All but the last member: adj = ρ·(ILᵢ − wᵢ·IL_total).
        for (uint256 i; i < n - 1; ++i) {
            uint256 fair = Math.mulDiv(ilTotal, sizes[i], sizeTotal); // wᵢ·IL_total
            int256 raw = int256(il[i]) - int256(fair); //               ILᵢ − IL_fairᵢ (signed)
            int256 a = (raw * int256(rhoBps)) / int256(BPS); //         apply ρ
            adj[i] = a;
            running += a;
        }
        // Final member absorbs the rounding residual so the vector sums to exactly zero.
        adj[n - 1] = -running;
    }

    /// @notice Worst-case amount (WAD) member `i` could be required to *pay* into the basket.
    /// @dev A member pays the most when its own IL is zero: payment ≤ ρ · wᵢ · maxIL_total.
    ///      Used to size each member's settlement margin so settlement never under-funds.
    function maxPayment(uint256 maxIlTotal, uint256 sizeI, uint256 sizeTotal, uint256 rhoBps)
        internal
        pure
        returns (uint256)
    {
        uint256 fair = Math.mulDiv(maxIlTotal, sizeI, sizeTotal); // wᵢ · maxIL_total
        return Math.mulDiv(fair, rhoBps, BPS); //                   ρ · wᵢ · maxIL_total
    }
}
