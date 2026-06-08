// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice Minimal CREATE2 hook-address miner: finds a salt whose resulting address encodes `flags`
///         in its low 14 bits (the v4 hook-permission scheme).
library HookMiner {
    uint160 internal constant FLAG_MASK = uint160((1 << 14) - 1);
    uint256 internal constant MAX_LOOP = 160_444;

    function find(address deployer, uint160 flags, bytes memory creationCode, bytes memory constructorArgs)
        internal
        view
        returns (address hookAddress, bytes32 salt)
    {
        bytes memory bytecode = abi.encodePacked(creationCode, constructorArgs);
        bytes32 initCodeHash = keccak256(bytecode);
        for (uint256 s; s < MAX_LOOP; ++s) {
            hookAddress = computeAddress(deployer, s, initCodeHash);
            if (uint160(hookAddress) & FLAG_MASK == flags && hookAddress.code.length == 0) {
                return (hookAddress, bytes32(s));
            }
        }
        revert("HookMiner: no salt found");
    }

    function computeAddress(address deployer, uint256 salt, bytes32 initCodeHash)
        internal
        pure
        returns (address)
    {
        return address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), deployer, bytes32(salt), initCodeHash))))
        );
    }
}
