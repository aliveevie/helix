// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {PoolId} from "v4-core/types/PoolId.sol";

/// @notice Faithful, minimal stand-in for the v4 PoolManager's `extsload` surface.
/// @dev Stores arbitrary storage words and lets tests set a pool's Slot0 at exactly the slot
///      `StateLibrary` reads (keccak256(poolId, POOLS_SLOT=6)), so `getSlot0` works unmodified.
contract MockPoolManager {
    bytes32 internal constant POOLS_SLOT = bytes32(uint256(6));

    mapping(bytes32 => bytes32) internal _store;

    /// @notice Set a pool's spot price by packing sqrtPriceX96 into the low 160 bits of Slot0.
    function setSlot0(PoolId poolId, uint160 sqrtPriceX96) external {
        bytes32 slot = keccak256(abi.encodePacked(PoolId.unwrap(poolId), POOLS_SLOT));
        _store[slot] = bytes32(uint256(sqrtPriceX96));
    }

    function extsload(bytes32 slot) external view returns (bytes32) {
        return _store[slot];
    }

    function extsload(bytes32 startSlot, uint256 nSlots) external view returns (bytes32[] memory values) {
        values = new bytes32[](nSlots);
        for (uint256 i; i < nSlots; ++i) {
            values[i] = _store[bytes32(uint256(startSlot) + i)];
        }
    }

    function extsload(bytes32[] calldata slots) external view returns (bytes32[] memory values) {
        values = new bytes32[](slots.length);
        for (uint256 i; i < slots.length; ++i) {
            values[i] = _store[slots[i]];
        }
    }
}
