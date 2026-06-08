// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {HelixTypes} from "./HelixTypes.sol";
import {PoolId} from "v4-core/types/PoolId.sol";

/// @title IntentLib
/// @notice EIP-712 struct hashing for Helix matching intents.
library IntentLib {
    /// @dev keccak256 of the Intent type string. `pool` is encoded as bytes32 (the PoolId value).
    bytes32 internal constant INTENT_TYPEHASH = keccak256(
        "Intent(address lp,bytes32 pool,uint256 maxDriftBps,uint64 minDuration,uint128 maxSize,uint16 repFloor,uint256 nonce,uint64 deadline)"
    );

    /// @notice EIP-712 struct hash of an intent (hashStruct, not the final digest).
    function hash(HelixTypes.Intent memory intent) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                INTENT_TYPEHASH,
                intent.lp,
                PoolId.unwrap(intent.pool),
                intent.maxDriftBps,
                intent.minDuration,
                intent.maxSize,
                intent.repFloor,
                intent.nonce,
                intent.deadline
            )
        );
    }
}
