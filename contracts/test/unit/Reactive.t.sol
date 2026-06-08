// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, Vm} from "forge-std/Test.sol";
import {HelixReactive} from "../../src/reactive/HelixReactive.sol";
import {LogRecord, ISystemContract} from "../../src/reactive/ReactiveLib.sol";
import {HelixTypes} from "../../src/libraries/HelixTypes.sol";

/// @notice Local simulation of the Reactive control plane: feed synthetic events to `react` and assert
///         the correct cross-chain `Callback`s (PAUSE / RESUME / RE_MATCH) are emitted.
contract ReactiveTest is Test {
    HelixReactive internal rsc;

    bytes32 internal constant PRICE_OBSERVED_TOPIC = keccak256("PriceObserved(bytes32,uint256,uint256,uint64)");
    bytes32 internal constant MATCH_SUBMITTED_TOPIC =
        keccak256("MatchSubmitted(bytes32,bytes32,address[],uint256[],uint16)");
    bytes32 internal constant CALLBACK_TOPIC = keccak256("Callback(uint256,address,uint64,bytes)");

    bytes32 internal poolA = keccak256("poolA");
    bytes32 internal poolB = keccak256("poolB");
    bytes32 internal matchA = keccak256("matchA");
    bytes32 internal matchB = keccak256("matchB");
    address internal destHook = makeAddr("destHook");

    function setUp() public {
        rsc = new HelixReactive(ISystemContract(address(0)), false);
        rsc.registerPool(poolA, 1301, destHook); // Unichain
        rsc.registerPool(poolB, 8453, destHook); // Base
        _matchLog(matchA, poolA);
        _matchLog(matchB, poolB);
    }

    function _priceLog(bytes32 pool, uint256 price) internal {
        LogRecord memory log = LogRecord({
            chainId: 1301,
            _contract: destHook,
            topic0: uint256(PRICE_OBSERVED_TOPIC),
            topic1: uint256(pool),
            topic2: 0,
            topic3: 0,
            data: abi.encode(price, price, uint64(block.timestamp)),
            blockNumber: block.number,
            opCode: 0
        });
        rsc.react(log);
    }

    function _matchLog(bytes32 matchId, bytes32 pool) internal {
        address[] memory lps = new address[](2);
        uint256[] memory sizes = new uint256[](2);
        LogRecord memory log = LogRecord({
            chainId: 1301,
            _contract: destHook,
            topic0: uint256(MATCH_SUBMITTED_TOPIC),
            topic1: uint256(matchId),
            topic2: uint256(pool),
            topic3: 0,
            data: abi.encode(lps, sizes, uint16(10000)),
            blockNumber: block.number,
            opCode: 0
        });
        rsc.react(log);
    }

    function _paused(bytes32 pool) internal view returns (bool paused) {
        (,,,, paused,,,) = rsc.stat(pool);
    }

    function _countCallbacks(Vm.Log[] memory logs, uint8 action) internal pure returns (uint256 count) {
        bytes memory want = abi.encodeWithSignature("triggerRebalance(bytes32,uint8)", bytes32(0), action);
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] != CALLBACK_TOPIC) continue;
            bytes memory payload = abi.decode(logs[i].data, (bytes));
            // Compare the trailing action byte (last 32-byte word).
            if (payload.length == want.length && uint8(uint256(bytes32(_lastWord(payload)))) == action) count++;
        }
    }

    function _lastWord(bytes memory b) internal pure returns (bytes32 w) {
        assembly {
            w := mload(add(b, mload(b)))
        }
    }

    function test_vol_pauseThenResume() public {
        _priceLog(poolA, 1e18); // seed

        vm.recordLogs();
        _priceLog(poolA, 1.1e18); // ~9% jump ⇒ vol EMA > volHigh ⇒ PAUSE
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertTrue(_paused(poolA), "pool should be paused");
        assertEq(_countCallbacks(logs, uint8(HelixTypes.RebalanceAction.PAUSE)), 1, "one PAUSE callback");

        // Calm (zero-return) observations decay the vol EMA below volLow ⇒ RESUME.
        _priceLog(poolA, 1.1e18); // EMA 0.030 -> 0.021
        _priceLog(poolA, 1.1e18); // -> 0.0147
        _priceLog(poolA, 1.1e18); // -> 0.0103
        vm.recordLogs();
        _priceLog(poolA, 1.1e18); // -> 0.0072 < volLow(0.01) ⇒ RESUME
        logs = vm.getRecordedLogs();
        assertFalse(_paused(poolA), "pool should resume");
        assertEq(_countCallbacks(logs, uint8(HelixTypes.RebalanceAction.RESUME)), 1, "one RESUME callback");
    }

    function test_correlation_triggersReMatch() public {
        rsc.setCorrelationPair(poolA, poolB);

        // Seed both legs.
        _priceLog(poolA, 1e18);
        _priceLog(poolB, 1e18);

        // Feed strongly positively-correlated returns; the hedge decays ⇒ RE_MATCH.
        uint256 pa = 1e18;
        uint256 pb = 1e18;
        for (uint256 i; i < 6; ++i) {
            pa = pa * 103 / 100;
            pb = pb * 103 / 100;
            _priceLog(poolA, pa);
            _priceLog(poolB, pb);
        }

        assertGt(rsc.realizedCorrelation(), int256(rsc.corrBound()), "realized corr above bound");

        vm.recordLogs();
        pa = pa * 103 / 100;
        pb = pb * 103 / 100;
        _priceLog(poolA, pa);
        _priceLog(poolB, pb);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertGe(_countCallbacks(logs, uint8(HelixTypes.RebalanceAction.RE_MATCH)), 1, "RE_MATCH dispatched");
    }

    function test_react_vmGuardWhenOnReactiveNetwork() public {
        HelixReactive guarded = new HelixReactive(ISystemContract(address(0)), true); // vmContext = true
        guarded.setReactiveVm(makeAddr("theVm"));
        LogRecord memory log;
        log.topic0 = uint256(PRICE_OBSERVED_TOPIC);
        vm.prank(makeAddr("notVm"));
        vm.expectRevert(bytes("Reactive: not VM"));
        guarded.react(log);
    }
}
