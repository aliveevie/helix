// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title ISettlementRegistry
/// @notice Escrows settlement margins and executes zero-sum redistribution between member accounts.
interface ISettlementRegistry {
    event MarginDeposited(bytes32 indexed matchId, address indexed lp, uint256 amount);
    event Redistributed(bytes32 indexed matchId, uint256 grossMoved, uint256 settlerFee, address settler);
    event MarginReturned(bytes32 indexed matchId, address indexed lp, uint256 amount);
    event MarginForfeited(bytes32 indexed matchId, address indexed lp, uint256 returned, uint256 forfeited);

    /// @notice Pull `amount` of the margin token from `lp` into escrow against `matchId`.
    function depositMargin(bytes32 matchId, address lp, uint256 amount) external;

    /// @notice Apply a zero-sum, conservation-checked adjustment vector and pay the settler.
    /// @param matchId      the basket being settled
    /// @param lps          member LPs (parallel to `adjustments`)
    /// @param adjustments  signed redistribution (WAD); Σ must be 0
    /// @param settler      recipient of the bounded settler fee
    /// @param ilTotalWad   basket aggregate IL (WAD), used to bound the settler fee
    function applyRedistribution(
        bytes32 matchId,
        address[] calldata lps,
        int256[] calldata adjustments,
        address settler,
        uint256 ilTotalWad
    ) external;

    /// @notice Early-exit: return (1 − forfeitBps) of `lp`'s margin and retain the slice as basket surplus.
    function forfeitMargin(bytes32 matchId, address lp, uint16 forfeitBps) external;

    /// @notice Escrowed margin for (`matchId`, `lp`).
    function marginOf(bytes32 matchId, address lp) external view returns (uint256);

    /// @notice The bounded settler-fee rate in basis points.
    function settlerFeeBps() external view returns (uint16);

    /// @notice The ERC-20 token used for margin (e.g. USDC).
    function marginToken() external view returns (address);
}
