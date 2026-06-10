// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice Minimal vendored surface of the Reactive Network SDK.
/// @dev Mirrors `reactive-lib` (IReactive / AbstractReactive). Swap these imports for the published
///      `@reactivenetwork/reactive-lib` package at deploy time; the semantics here match the SDK so
///      the Helix RSC logic is unit-testable without a live Reactive VM.

/// @notice A decoded log delivered to a reactive contract's `react` entrypoint.
struct LogRecord {
    uint256 chainId;
    address _contract;
    uint256 topic0;
    uint256 topic1;
    uint256 topic2;
    uint256 topic3;
    bytes data;
    uint256 blockNumber;
    uint256 opCode;
}

interface IReactive {
    /// @notice Called by the Reactive VM for every subscribed event.
    function react(LogRecord calldata log) external;
}

/// @notice Subscription service surface (subset).
interface ISystemContract {
    function subscribe(uint256 chainId, address _contract, uint256 topic0, uint256 topic1, uint256 topic2, uint256 topic3)
        external;
    function unsubscribe(
        uint256 chainId,
        address _contract,
        uint256 topic0,
        uint256 topic1,
        uint256 topic2,
        uint256 topic3
    ) external;
}

/// @notice Base for reactive contracts: emits cross-chain callbacks and gates `react` to the VM.
abstract contract AbstractReactive is IReactive {
    /// @dev A wildcard used by the Reactive system to mean "any value" in a subscription topic slot.
    uint256 internal constant REACTIVE_IGNORE = 0xa65f96fc951c35ead38878e0f0b7a3c744a6f5ccc1476b313353ce31712313ad;

    /// @notice The Reactive VM relays any `Callback` this contract emits to the destination chain.
    /// @param chainId   destination chain id
    /// @param _contract destination contract (the Helix hook)
    /// @param gasLimit  callback gas limit
    /// @param payload   ABI-encoded call (e.g. triggerRebalance(bytes32,uint8))
    event Callback(uint256 indexed chainId, address indexed _contract, uint64 indexed gasLimit, bytes payload);

    /// @dev True when running on the Reactive Network (VM context); false on origin chains / in tests.
    bool internal vmContext;
    address internal reactiveVm; // authorized caller of `react` in VM context

    modifier vmOnly() {
        require(!vmContext || msg.sender == reactiveVm, "Reactive: not VM");
        _;
    }

    /// @notice Accept REACT so the contract can pay the Reactive Network for its subscriptions
    ///         (the subscription service debits the reactive contract — AbstractPayer model).
    receive() external payable {}

    function _emitCallback(uint256 chainId, address _contract, uint64 gasLimit, bytes memory payload) internal {
        emit Callback(chainId, _contract, gasLimit, payload);
    }
}
