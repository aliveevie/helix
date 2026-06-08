// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {HelixBase} from "../utils/HelixBase.t.sol";
import {HelixTypes} from "../../src/libraries/HelixTypes.sol";
import {ICircuitBreaker} from "../../src/interfaces/ICircuitBreaker.sol";
import {HelixReactive} from "../../src/reactive/HelixReactive.sol";
import {LogRecord, ISystemContract} from "../../src/reactive/ReactiveLib.sol";
import {PoolId} from "v4-core/types/PoolId.sol";

/// @notice Full reactive loop, end to end: the hook's *real* emitted events are fed to the RSC, and the
///         RSC's *real* callback bytes are relayed back into the hook by the registered proxy. This proves
///         the event encodings the RSC subscribes to exactly match what the hook emits, and that the
///         callback the RSC produces is a well-formed `triggerRebalance` the hook accepts.
contract ReactiveLoop is HelixBase {
    HelixReactive internal rsc;

    address internal alice;
    uint256 internal alicePk;
    address internal bob;
    uint256 internal bobPk;

    bytes32 internal constant PRICE_OBSERVED_TOPIC = keccak256("PriceObserved(bytes32,uint256,uint256,uint64)");
    bytes32 internal constant MATCH_SUBMITTED_TOPIC =
        keccak256("MatchSubmitted(bytes32,bytes32,address[],uint256[],uint16)");
    bytes32 internal constant CALLBACK_TOPIC = keccak256("Callback(uint256,address,uint64,bytes)");

    function setUp() public {
        deployHelix();
        (alice, alicePk) = makeLp("alice");
        (bob, bobPk) = makeLp("bob");

        rsc = new HelixReactive(ISystemContract(address(0)), false);
        rsc.registerPool(PoolId.unwrap(poolId), block.chainid, address(hook));
    }

    function _toRecord(Vm.Log memory l) internal view returns (LogRecord memory r) {
        r.chainId = block.chainid;
        r._contract = l.emitter;
        r.topic0 = uint256(l.topics[0]);
        r.topic1 = l.topics.length > 1 ? uint256(l.topics[1]) : 0;
        r.topic2 = l.topics.length > 2 ? uint256(l.topics[2]) : 0;
        r.topic3 = l.topics.length > 3 ? uint256(l.topics[3]) : 0;
        r.data = l.data;
        r.blockNumber = block.number;
        r.opCode = 0;
    }

    /// @dev Feed every log with `topic0 == want` (emitted by the hook) into the RSC's react entrypoint.
    function _feed(Vm.Log[] memory logs, bytes32 want) internal {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == want) {
                rsc.react(_toRecord(logs[i]));
            }
        }
    }

    /// @dev Relay the RSC's emitted Callback bytes to the hook, exactly as the Reactive proxy would.
    function _relayCallbacks(Vm.Log[] memory logs) internal returns (uint256 relayed) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == CALLBACK_TOPIC) {
                bytes memory payload = abi.decode(logs[i].data, (bytes));
                vm.prank(reactiveProxy);
                (bool ok,) = address(hook).call(payload);
                require(ok, "callback relay failed");
                relayed++;
            }
        }
    }

    function _openMatch() internal returns (bytes32 matchId) {
        HelixTypes.Intent memory ia = buildIntent(alice, 2000e18, 5000, 0, 1);
        HelixTypes.Intent memory ib = buildIntent(bob, 2000e18, 5000, 0, 2);
        HelixTypes.Intent[] memory intents = new HelixTypes.Intent[](2);
        bytes[] memory sigs = new bytes[](2);
        intents[0] = ia;
        intents[1] = ib;
        sigs[0] = signIntent(alicePk, ia);
        sigs[1] = signIntent(bobPk, ib);

        // Capture the real MatchSubmitted event and teach the RSC about the basket↔pool mapping.
        vm.recordLogs();
        matchId = hook.submitMatch(intents, sigs);
        _feed(vm.getRecordedLogs(), MATCH_SUBMITTED_TOPIC);

        oracle.setPrice(poolId, 1e18);
        enterBalanced(matchId, alice, 1000e18);
        oracle.setPrice(poolId, 2e18);
        enterBalanced(matchId, bob, 1000e18);
    }

    function test_endToEnd_priceSpikePausesViaRSC() public {
        bytes32 matchId = _openMatch();

        // Seed the RSC with a calm observation (hook's real PriceObserved event).
        vm.recordLogs();
        observeSwap(1e18);
        _feed(vm.getRecordedLogs(), PRICE_OBSERVED_TOPIC);

        assertTrue(breaker.state(poolId) != ICircuitBreaker.State.HALTED, "not halted yet");

        // A volatility spike: feed the hook's real PriceObserved to the RSC, then relay its callback bytes.
        vm.recordLogs();
        observeSwap(1.15e18);
        Vm.Log[] memory swapLogs = vm.getRecordedLogs();

        // The RSC reacts in its own log scope so we can capture the Callback it emits.
        vm.recordLogs();
        _feed(swapLogs, PRICE_OBSERVED_TOPIC);
        Vm.Log[] memory rscLogs = vm.getRecordedLogs();

        uint256 relayed = _relayCallbacks(rscLogs);
        assertEq(relayed, 1, "exactly one PAUSE callback relayed for the basket");

        // The RSC drove the breaker to HALTED via the authenticated callback.
        assertEq(uint8(breaker.state(poolId)), uint8(ICircuitBreaker.State.HALTED), "RSC paused the pool");

        // And the queued action is recorded on the match.
        HelixTypes.Match memory m = hook.getMatch(matchId);
        assertEq(uint8(m.pending), uint8(HelixTypes.RebalanceAction.PAUSE));
    }

    function test_endToEnd_calmResumesViaRSC() public {
        _openMatch();

        // Pause first.
        vm.recordLogs();
        observeSwap(1e18);
        observeSwap(1.15e18);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        vm.recordLogs();
        _feed(logs, PRICE_OBSERVED_TOPIC);
        _relayCallbacks(vm.getRecordedLogs());
        assertEq(uint8(breaker.state(poolId)), uint8(ICircuitBreaker.State.HALTED), "paused");

        // Calm observations decay the RSC vol EMA below volLow ⇒ it emits RESUME.
        uint256 relayed;
        for (uint256 i; i < 5; ++i) {
            vm.recordLogs();
            observeSwap(1.15e18); // zero return after the first
            Vm.Log[] memory swap = vm.getRecordedLogs();
            vm.recordLogs();
            _feed(swap, PRICE_OBSERVED_TOPIC);
            relayed += _relayCallbacks(vm.getRecordedLogs());
        }

        assertGe(relayed, 1, "RSC emitted and relayed a RESUME callback");
        assertEq(uint8(breaker.state(poolId)), uint8(ICircuitBreaker.State.NORMAL), "RSC resumed the pool");
    }
}
