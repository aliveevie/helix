// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title IReputation
/// @notice ERC-8004-aligned reputation registry for Helix LPs.
/// @dev Reputation gates priority matching and larger size bands, and is enforced on-chain as the
///      `counterparty reputation floor` carried in each intent. Only the authorized hook may write.
interface IReputation {
    event Credited(address indexed lp, uint256 weight, uint16 newScore);
    event Penalized(address indexed lp, uint256 weight, uint16 newScore);

    /// @notice Increase `lp`'s reputation for honoring a match.
    function credit(address lp, uint256 weight) external;

    /// @notice Decrease `lp`'s reputation for early exit / settlement gaming.
    function penalize(address lp, uint256 weight) external;

    /// @notice Current reputation score of `lp` (0..MAX).
    function scoreOf(address lp) external view returns (uint16);
}
