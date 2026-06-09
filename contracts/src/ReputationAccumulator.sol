// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IReputation} from "./interfaces/IReputation.sol";
import {IERC8004Reputation} from "./interfaces/IERC8004Reputation.sol";

/// @title ReputationAccumulator
/// @notice ERC-8004 (Trustless Agents) Reputation Registry for Helix LPs. Anyone may leave tagged,
///         revocable feedback about an LP (`giveFeedback`), aggregated via `getSummary` — the conformant
///         ERC-8004 surface. The protocol also keeps a fast, hook-controlled 0..MAX_SCORE score used as
///         the on-chain counterparty reputation floor: honoring a match credits it, early exit / gaming
///         penalizes it, and each such event is also emitted as ERC-8004 feedback.
/// @dev An agent is an LP; `agentId == uint160(lp)`.
contract ReputationAccumulator is IReputation, IERC8004Reputation {
    uint16 public constant MAX_SCORE = 10_000;

    address public owner;
    address public hook; // authorized writer of the protocol score

    // --- protocol score (used for the intent repFloor) ---
    mapping(address => uint16) internal _score;
    mapping(address => uint64) public matchesHonored;
    mapping(address => uint64) public matchesBroken;

    // --- ERC-8004 feedback store ---
    struct Feedback {
        int128 value;
        uint8 valueDecimals;
        string tag1;
        string tag2;
        bool revoked;
    }

    mapping(uint256 => mapping(address => Feedback[])) internal _feedback; // agentId => client => feedback[]
    mapping(uint256 => address[]) internal _clients; // agentId => distinct clients
    mapping(uint256 => mapping(address => bool)) internal _isClient;

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

    // ============================================================ Agent id helpers

    function agentIdOf(address lp) public pure returns (uint256) {
        return uint256(uint160(lp));
    }

    // ============================================================ Protocol score (IReputation)

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
        _record(agentIdOf(lp), msg.sender, int128(int256(weight)), 0, "helix", "honored", "", "", bytes32(0));
    }

    /// @inheritdoc IReputation
    function penalize(address lp, uint256 weight) external override onlyHook {
        uint256 cur = _score[lp];
        uint256 s = weight >= cur ? 0 : cur - weight;
        _score[lp] = uint16(s);
        matchesBroken[lp] += 1;
        emit Penalized(lp, weight, uint16(s));
        _record(agentIdOf(lp), msg.sender, -int128(int256(weight)), 0, "helix", "broke", "", "", bytes32(0));
    }

    // ============================================================ ERC-8004 Reputation Registry

    /// @inheritdoc IERC8004Reputation
    function giveFeedback(
        uint256 agentId,
        int128 value,
        uint8 valueDecimals,
        string calldata tag1,
        string calldata tag2,
        string calldata endpoint,
        string calldata feedbackURI,
        bytes32 feedbackHash
    ) external override {
        _record(agentId, msg.sender, value, valueDecimals, tag1, tag2, endpoint, feedbackURI, feedbackHash);
    }

    /// @inheritdoc IERC8004Reputation
    function revokeFeedback(uint256 agentId, uint64 feedbackIndex) external override {
        Feedback[] storage list = _feedback[agentId][msg.sender];
        require(feedbackIndex < list.length, "REP: bad index");
        require(!list[feedbackIndex].revoked, "REP: revoked");
        list[feedbackIndex].revoked = true;
        emit FeedbackRevoked(agentId, msg.sender, feedbackIndex);
    }

    /// @inheritdoc IERC8004Reputation
    function getSummary(uint256 agentId, address[] calldata clientAddresses, string calldata tag1, string calldata tag2)
        external
        view
        override
        returns (uint64 count, int128 summaryValue, uint8 summaryValueDecimals)
    {
        address[] memory clients;
        if (clientAddresses.length == 0) {
            clients = _clients[agentId];
        } else {
            clients = clientAddresses;
        }
        for (uint256 i; i < clients.length; ++i) {
            Feedback[] storage list = _feedback[agentId][clients[i]];
            for (uint256 k; k < list.length; ++k) {
                Feedback storage f = list[k];
                if (f.revoked) continue;
                if (!_tagMatch(f.tag1, tag1) || !_tagMatch(f.tag2, tag2)) continue;
                count += 1;
                summaryValue += f.value;
                summaryValueDecimals = f.valueDecimals;
            }
        }
    }

    /// @inheritdoc IERC8004Reputation
    function readFeedback(uint256 agentId, address clientAddress, uint64 feedbackIndex)
        external
        view
        override
        returns (int128 value, uint8 valueDecimals, string memory tag1, string memory tag2, bool isRevoked)
    {
        Feedback storage f = _feedback[agentId][clientAddress][feedbackIndex];
        return (f.value, f.valueDecimals, f.tag1, f.tag2, f.revoked);
    }

    /// @inheritdoc IERC8004Reputation
    function getClients(uint256 agentId) external view override returns (address[] memory) {
        return _clients[agentId];
    }

    /// @inheritdoc IERC8004Reputation
    function getLastIndex(uint256 agentId, address clientAddress) external view override returns (uint64) {
        return uint64(_feedback[agentId][clientAddress].length);
    }

    // ============================================================ Internals

    function _record(
        uint256 agentId,
        address client,
        int128 value,
        uint8 valueDecimals,
        string memory tag1,
        string memory tag2,
        string memory endpoint,
        string memory feedbackURI,
        bytes32 feedbackHash
    ) internal {
        if (!_isClient[agentId][client]) {
            _isClient[agentId][client] = true;
            _clients[agentId].push(client);
        }
        uint64 idx = uint64(_feedback[agentId][client].length);
        _feedback[agentId][client].push(Feedback(value, valueDecimals, tag1, tag2, false));
        emit NewFeedback(
            agentId, client, idx, value, valueDecimals, tag1, tag1, tag2, endpoint, feedbackURI, feedbackHash
        );
    }

    function _tagMatch(string storage stored, string calldata query) internal view returns (bool) {
        return bytes(query).length == 0 || keccak256(bytes(stored)) == keccak256(bytes(query));
    }
}
