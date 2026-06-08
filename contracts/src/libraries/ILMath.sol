// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title ILMath
/// @notice Closed-form impermanent-loss accounting for a constant-product (x*y=k) liquidity position.
/// @dev The hook models each matched position as a 50/50 CPMM LP. This yields a well-defined,
///      gas-cheap, monotone IL baseline used purely for *relative* redistribution inside a basket.
///      All inputs/outputs are WAD (1e18) value-units, with price `P` expressed as token1-per-token0.
library ILMath {
    using Math for uint256;

    uint256 internal constant WAD = 1e18;

    /// @notice Split a notional value `N` (token1 WAD units) into a balanced LP entry at price `P0`.
    /// @return x0 entry token0 amount (WAD), worth N/2 at P0
    /// @return y0 entry token1 amount (WAD), equal to N/2
    function balancedEntry(uint256 notional, uint256 p0) internal pure returns (uint256 x0, uint256 y0) {
        require(p0 > 0, "ILMath: P0=0");
        y0 = notional / 2; //                 half the value sits in token1
        x0 = Math.mulDiv(notional / 2, WAD, p0); // the other half, denominated in token0
    }

    /// @notice Impermanent loss of the position at settlement price `P1`, in token1 WAD units.
    /// @dev IL = V_hold(P1) − V_pool(P1), always ≥ 0 for a CPMM position.
    ///      V_hold = x0·P1 + y0 ; V_pool = 2·√(x0·y0·P1)  (all WAD-consistent).
    function il(uint256 x0, uint256 y0, uint256 p1) internal pure returns (uint256) {
        uint256 vHold = Math.mulDiv(x0, p1, WAD) + y0;
        uint256 vPool = poolValue(x0, y0, p1);
        // CPMM guarantees vHold ≥ vPool; clamp defends against rounding at the boundary.
        return vHold > vPool ? vHold - vPool : 0;
    }

    /// @notice Value of the (rebalanced) pool position at price `P1`: 2·√(x0·y0·P1), WAD.
    function poolValue(uint256 x0, uint256 y0, uint256 p1) internal pure returns (uint256) {
        // A = x0·y0·P1 / WAD, staged through mulDiv to use 512-bit intermediates.
        uint256 xy = x0 * y0; //                 ≤ ~1e54 for realistic notionals; reverts on overflow
        uint256 a = Math.mulDiv(xy, p1, WAD); //  x0·y0·P1 / 1e18
        return 2 * a.sqrt();
    }

    /// @notice IL *fraction* (WAD) suffered by a CPMM position when price moves by a factor `r = P1/P0`.
    /// @dev f(r) = 1 − 2·√r / (1 + r) ∈ [0,1). Used for worst-case margin sizing from a drift bound.
    function ilFraction(uint256 rWad) internal pure returns (uint256) {
        if (rWad == WAD) return 0;
        uint256 sqrtR = (rWad * WAD).sqrt(); //          √r in WAD
        uint256 num = 2 * sqrtR; //                       2√r (WAD)
        uint256 den = WAD + rWad; //                      1+r (WAD)
        uint256 frac = Math.mulDiv(num, WAD, den); //     2√r/(1+r) (WAD)
        return frac >= WAD ? 0 : WAD - frac;
    }

    /// @notice Worst-case IL fraction (WAD) over a max price-drift `driftBps` (up-move vs down-move).
    function maxILFraction(uint256 driftBps) internal pure returns (uint256) {
        uint256 rUp = WAD + Math.mulDiv(WAD, driftBps, 10_000); // 1 + d
        uint256 rDown = Math.mulDiv(WAD, WAD, rUp); //            1 / (1+d)
        uint256 fUp = ilFraction(rUp);
        uint256 fDown = ilFraction(rDown);
        return fUp > fDown ? fUp : fDown;
    }

    /// @notice Maximum IL value (WAD) of a notional `N` position given a max price-drift `driftBps`.
    function maxIL(uint256 notional, uint256 driftBps) internal pure returns (uint256) {
        return Math.mulDiv(notional, maxILFraction(driftBps), WAD);
    }
}
