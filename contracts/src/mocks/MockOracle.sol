// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IHelixOracle} from "../interfaces/IHelixOracle.sol";
import {PoolId} from "v4-core/types/PoolId.sol";

/// @notice Settable reference-price oracle for tests and local demos (token1-per-token0, WAD).
contract MockOracle is IHelixOracle {
    mapping(PoolId => uint256) internal _price;

    function setPrice(PoolId pool, uint256 priceWad) external {
        _price[pool] = priceWad;
    }

    function price(PoolId pool) external view override returns (uint256) {
        return _price[pool];
    }
}
