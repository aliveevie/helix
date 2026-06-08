// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IReputation} from "./interfaces/IReputation.sol";

/// @title ReputationAccumulator
/// @notice ERC-8004-aligned reputation registry. LPs that honor matches accrue score; early exit or
///         settlement gaming is penalized. Score gates priority matching and larger size bands, and is
///         enforced on-chain as each intent's counterparty reputation floor.
/// @dev Aligns with ERC-8004 (Trustless Agents) reputation semantics: monotone, capped feedback writes
///      restricted to the authorized protocol contract. Score is a 0..MAX_SCORE uint16.
contract ReputationAccumulator is IReputation {
    uint16 public constant MAX_SCORE = 10_000;

    address public owner;
    address public hook; // authorized writer

    mapping(address => uint16) internal _score;
    mapping(address => uint64) public matchesHonored;
    mapping(address => uint64) public matchesBroken;

    modifier onlyHook() {
        require(msg.sender == hook, "REP: only hook");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function setHook(address hook_) external {
        require(msg.sender == owner, "REP: only owner");
        require(hook == address(0), "REP: hook set");
        require(hook_ != address(0), "REP: zero");
        hook = hook_;
    }

    /// @inheritdoc IReputation
    function scoreOf(address lp) external view override returns (uint16) {
        return _score[lp];
    }

    /// @inheritdoc IReputation
    function credit(address lp, uint256 weight) external override onlyHook {
        uint256 s = uint256(_score[lp]) + weight;
        if (s > MAX_SCORE) s = MAX_SCORE;
        _score[lp] = uint16(s);
        matchesHonored[lp] += 1;
        emit Credited(lp, weight, uint16(s));
    }

    /// @inheritdoc IReputation
    function penalize(address lp, uint256 weight) external override onlyHook {
        uint256 cur = _score[lp];
        uint256 s = weight >= cur ? 0 : cur - weight;
        _score[lp] = uint16(s);
        matchesBroken[lp] += 1;
        emit Penalized(lp, weight, uint16(s));
    }
}
