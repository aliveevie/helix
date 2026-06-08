// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ISettlementRegistry} from "./interfaces/ISettlementRegistry.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title SettlementRegistry
/// @notice Escrows settlement margins and executes zero-sum, conservation-checked redistribution.
/// @dev Margins are tracked internally in WAD (1e18). The registry converts WAD↔token at transfer
///      boundaries using `scale = 10^(18−decimals)`, always rounding payouts *down* so total tokens
///      out can never exceed total tokens in. With an 18-decimal token, scale == 1 (exact).
contract SettlementRegistry is ISettlementRegistry, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 internal constant WAD = 1e18;
    uint256 internal constant BPS = 10_000;
    uint16 public constant MAX_FEE_BPS = 100; // settler fee capped at 1% of basket IL

    IERC20 public immutable token;
    uint256 public immutable scale; // 10^(18 - decimals)
    uint16 internal immutable _settlerFeeBps;
    uint16 public constant MAX_FORFEIT_BPS = 5_000; // early-exit forfeit capped at 50%

    address public owner;
    address public hook;

    mapping(bytes32 => mapping(address => uint256)) internal _margin; // matchId => lp => WAD (token-backed)
    mapping(bytes32 => bool) public settled;

    modifier onlyHook() {
        require(msg.sender == hook, "SR: only hook");
        _;
    }

    constructor(address token_, uint16 settlerFeeBps_) {
        require(token_ != address(0), "SR: zero token");
        require(settlerFeeBps_ <= MAX_FEE_BPS, "SR: fee too high");
        uint8 dec = IERC20Metadata(token_).decimals();
        require(dec <= 18, "SR: decimals>18");
        token = IERC20(token_);
        scale = 10 ** (18 - dec);
        _settlerFeeBps = settlerFeeBps_;
        owner = msg.sender;
    }

    function setHook(address hook_) external {
        require(msg.sender == owner, "SR: only owner");
        require(hook == address(0), "SR: hook set");
        require(hook_ != address(0), "SR: zero");
        hook = hook_;
    }

    function settlerFeeBps() external view override returns (uint16) {
        return _settlerFeeBps;
    }

    function marginToken() external view override returns (address) {
        return address(token);
    }

    /// @inheritdoc ISettlementRegistry
    /// @return marginOf the token-backed margin in WAD.
    function marginOf(bytes32 matchId, address lp) external view override returns (uint256) {
        return _margin[matchId][lp];
    }

    /// @inheritdoc ISettlementRegistry
    function depositMargin(bytes32 matchId, address lp, uint256 amountWad) external override onlyHook nonReentrant {
        require(!settled[matchId], "SR: settled");
        uint256 tokenAmount = amountWad / scale; // round down to whole token units
        require(tokenAmount > 0, "SR: dust margin");
        uint256 backedWad = tokenAmount * scale; // exact token-backed WAD
        token.safeTransferFrom(lp, address(this), tokenAmount);
        _margin[matchId][lp] += backedWad;
        emit MarginDeposited(matchId, lp, backedWad);
    }

    /// @inheritdoc ISettlementRegistry
    /// @dev Returns (1 − forfeitBps) of the margin to `lp`; the forfeited slice stays escrowed as
    ///      basket surplus (still satisfies the conservation invariant: tokens out ≤ tokens in).
    function forfeitMargin(bytes32 matchId, address lp, uint16 forfeitBps)
        external
        override
        onlyHook
        nonReentrant
    {
        require(!settled[matchId], "SR: settled");
        require(forfeitBps <= MAX_FORFEIT_BPS, "SR: forfeit too high");
        uint256 marginI = _margin[matchId][lp];
        require(marginI > 0, "SR: no margin");
        _margin[matchId][lp] = 0; // effects before interaction; slice stays in contract

        uint256 forfeitedWad = Math.mulDiv(marginI, forfeitBps, BPS);
        uint256 returnWad = marginI - forfeitedWad;
        uint256 returnToken = returnWad / scale;
        if (returnToken > 0) token.safeTransfer(lp, returnToken);
        emit MarginForfeited(matchId, lp, returnToken * scale, marginI - returnToken * scale);
    }

    /// @inheritdoc ISettlementRegistry
    /// @dev State flips to `settled` before any external transfer (idempotency + reentrancy safety).
    ///      Enforces Σ adjustments == 0 and per-member solvency (margin + adj − fee ≥ 0). Total tokens
    ///      paid out ≤ total tokens escrowed, by construction.
    function applyRedistribution(
        bytes32 matchId,
        address[] calldata lps,
        int256[] calldata adjustments,
        address settler,
        uint256 ilTotalWad
    ) external override onlyHook nonReentrant {
        require(!settled[matchId], "SR: settled");
        settled[matchId] = true; // checks-effects-interactions: terminal before transfers

        uint256 n = lps.length;
        require(n == adjustments.length && n > 0, "SR: length");

        // Zero-sum guard + total escrow.
        int256 adjSum;
        uint256 totalMarginWad;
        for (uint256 i; i < n; ++i) {
            adjSum += adjustments[i];
            totalMarginWad += _margin[matchId][lps[i]];
        }
        require(adjSum == 0, "SR: not zero-sum");

        // Bounded settler fee: settlerFeeBps · IL_total, never exceeding the escrow.
        uint256 feeWad = Math.mulDiv(ilTotalWad, _settlerFeeBps, BPS);
        if (feeWad > totalMarginWad) feeWad = totalMarginWad;

        uint256 grossMoved;
        uint256 feeAccruedWad; // exactly what members contribute, so the settler payout is always funded
        for (uint256 i; i < n; ++i) {
            address lp = lps[i];
            uint256 marginI = _margin[matchId][lp];
            uint256 feeI = totalMarginWad == 0 ? 0 : Math.mulDiv(feeWad, marginI, totalMarginWad);
            feeAccruedWad += feeI;

            int256 netWad = int256(marginI) + adjustments[i] - int256(feeI);
            require(netWad >= 0, "SR: insolvent member"); // margin sizing must cover this

            if (adjustments[i] > 0) grossMoved += uint256(adjustments[i]);

            _margin[matchId][lp] = 0; // effects before interaction
            uint256 payoutToken = uint256(netWad) / scale; // round down; dust stays as conservation buffer
            if (payoutToken > 0) {
                token.safeTransfer(lp, payoutToken);
                emit MarginReturned(matchId, lp, payoutToken * scale);
            }
        }

        uint256 feeToken = feeAccruedWad / scale; // ≤ Σ contributed; never exceeds escrow
        if (feeToken > 0) token.safeTransfer(settler, feeToken);

        emit Redistributed(matchId, grossMoved, feeToken * scale, settler);
    }
}
