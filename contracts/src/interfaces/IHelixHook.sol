// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {HelixTypes} from "../libraries/HelixTypes.sol";
import {PoolId} from "v4-core/types/PoolId.sol";

/// @title IHelixHook
/// @notice Public surface of the Helix hook: permissionless match submission, settlement, and the
///         RSC-authenticated rebalance callback.
interface IHelixHook {
    event MatchSubmitted(bytes32 indexed matchId, PoolId indexed pool, address[] lps, uint256[] sizes, uint16 rho);
    event PositionEntered(bytes32 indexed matchId, address indexed lp, uint256 x0, uint256 y0, uint256 p0);
    event MatchOpened(bytes32 indexed matchId, uint64 epochEnd);
    event PriceObserved(PoolId indexed pool, uint256 price, uint256 twap, uint64 timestamp);
    event MatchSettled(bytes32 indexed matchId, uint256 p1, uint256 ilTotal, address settler);
    event RebalanceTriggered(bytes32 indexed matchId, HelixTypes.RebalanceAction action);
    event EarlyExit(bytes32 indexed matchId, address indexed lp, uint256 forfeited);

    error NotReactive();
    error BadSignature(uint256 index);
    error IntentExpired(uint256 index);
    error NonceUsed(uint256 index);
    error ConstraintViolated(uint256 index);
    error BreakerNotNormal();
    error MatchNotOpen();
    error EpochNotEnded();
    error OracleDivergence();
    error AlreadySettled();
    error PositionInOpenMatch();

    /// @notice Permissionlessly create a basket from N signed intents. Re-verifies every signature,
    ///         deadline, nonce and constraint on-chain; pulls each member's margin into escrow.
    function submitMatch(HelixTypes.Intent[] calldata intents, bytes[] calldata signatures)
        external
        returns (bytes32 matchId);

    /// @notice Permissionlessly settle an expired, open match; redistributes IL and pays a settler fee.
    function settle(bytes32 matchId) external;

    /// @notice RSC-only rebalance callback (RE_MATCH / PAUSE / RESUME).
    function triggerRebalance(bytes32 matchId, uint8 action) external;

    /// @notice EIP-712 domain separator used for intent signatures.
    function domainSeparatorV4() external view returns (bytes32);

    /// @notice Read a match record.
    function getMatch(bytes32 matchId) external view returns (HelixTypes.Match memory);
}
