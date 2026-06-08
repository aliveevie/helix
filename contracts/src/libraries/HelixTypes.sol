// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {PoolId} from "v4-core/types/PoolId.sol";

/// @title HelixTypes
/// @notice Shared structs, enums and constants for the Helix cross-pool hedging protocol.
library HelixTypes {
    /// @dev Fixed-point scaling factor (1e18). All internal prices and value-amounts are WAD-scaled.
    uint256 internal constant WAD = 1e18;

    /// @dev Basis-point denominator (100% == 10_000 bps).
    uint256 internal constant BPS = 10_000;

    /// @notice Lifecycle of a match (basket of mutualized positions).
    enum MatchStatus {
        NONE, // never created
        PENDING, // created, awaiting all members to enter liquidity
        OPEN, // all members entered, epoch running
        SETTLED, // redistributed, terminal & idempotent
        CANCELLED // never opened within the entry window; margins refunded, terminal

    }

    /// @notice Rebalance actions the Reactive Smart Contract can request.
    enum RebalanceAction {
        NONE,
        RE_MATCH, // correlation drift exceeded intent bound: queue re-match / partial unwind
        PAUSE, // volatility above critical: drive breaker toward HALTED
        RESUME // volatility receded: allow breaker resume

    }

    /// @notice An off-chain signed matching intent (EIP-712).
    /// @dev `maxSize` doubles as the matched notional value (token1 units) used for weights & margin.
    struct Intent {
        address lp; //         liquidity provider / signer
        PoolId pool; //        target pool
        uint256 maxDriftBps; // max acceptable realized-correlation drift before re-match
        uint64 minDuration; //  minimum epoch participation (seconds)
        uint128 maxSize; //     matched notional (token1 WAD units); also the position weight basis
        uint16 repFloor; //     minimum counterparty reputation score required
        uint256 nonce; //       per-LP replay nonce
        uint64 deadline; //     signature expiry (unix seconds)
    }

    /// @notice Per-position entry snapshot held by the hook.
    struct PositionRecord {
        uint256 x0; //     entry token0 amount (WAD value-units)
        uint256 y0; //     entry token1 amount (WAD value-units)
        uint256 entryPrice; // P0, token1-per-token0 (WAD)
        uint64 entryTime; //   snapshot timestamp
        uint256 margin; //     settlement margin posted (registry token native units)
        address lp; //         owner
        bool entered; //       liquidity entry finalised
    }

    /// @notice A matched basket.
    struct Match {
        PoolId pool; //            pool the basket lives in (single-chain leg)
        uint64 createdAt; //       submitMatch timestamp; bounds the entry window
        uint64 epochEnd; //        settlement becomes permissionless at/after this time
        uint64 minDuration; //     max of members' minDuration; drives epochEnd at open
        uint16 rho; //             mutualization coefficient (bps, 0..10_000)
        uint16 requiredRatioBps; // margin-as-fraction-of-notional required of each member (bps)
        uint32 enteredCount; //    members that have finalised liquidity entry
        MatchStatus status; //
        RebalanceAction pending; // queued RSC action
        address[] lps; //          member LPs (parallel to keys/sizes)
        bytes32[] keys; //         member position keys (set at entry)
        uint256[] sizes; //        member notionals (WAD): maxSize caps at submit, actual at entry
    }

    /// @notice Per-pool configuration bound at `afterInitialize`.
    struct PoolConfig {
        uint64 epochLength; //   default epoch duration (seconds)
        uint16 rho; //           default mutualization coefficient (bps)
        uint16 marginRatioBps; // margin as fraction of notional (bps)
        uint16 maxDivergenceBps; // δ: max chainlink/TWAP divergence at settlement (bps)
        bool initialized;
    }
}
