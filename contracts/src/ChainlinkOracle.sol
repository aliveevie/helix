// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IHelixOracle, AggregatorV3Interface} from "./interfaces/IHelixOracle.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title ChainlinkOracle
/// @notice Production `IHelixOracle` adapter: returns a pool's reference price (token1-per-token0, WAD)
///         from a bound Chainlink Data Feed, with a per-oracle staleness guard and optional inversion.
contract ChainlinkOracle is IHelixOracle {
    struct Feed {
        AggregatorV3Interface agg;
        uint8 decimals;
        bool invert; // set when the feed quotes token0-per-token1 and must be flipped
        bool set;
    }

    address public owner;
    uint256 public maxStaleness;
    mapping(PoolId => Feed) public feeds;

    event FeedSet(PoolId indexed pool, address agg, bool invert);

    modifier onlyOwner() {
        require(msg.sender == owner, "CLO: only owner");
        _;
    }

    constructor(uint256 maxStaleness_) {
        owner = msg.sender;
        maxStaleness = maxStaleness_ == 0 ? 1 days : maxStaleness_;
    }

    function setMaxStaleness(uint256 s) external onlyOwner {
        require(s > 0, "CLO: zero");
        maxStaleness = s;
    }

    function setFeed(PoolId pool, address agg, bool invert) external onlyOwner {
        require(agg != address(0), "CLO: zero feed");
        uint8 d = AggregatorV3Interface(agg).decimals();
        feeds[pool] = Feed(AggregatorV3Interface(agg), d, invert, true);
        emit FeedSet(pool, agg, invert);
    }

    /// @inheritdoc IHelixOracle
    function price(PoolId pool) external view override returns (uint256) {
        Feed memory f = feeds[pool];
        require(f.set, "CLO: no feed");
        (, int256 answer,, uint256 updatedAt,) = f.agg.latestRoundData();
        require(answer > 0, "CLO: bad answer");
        require(updatedAt != 0 && block.timestamp - updatedAt <= maxStaleness, "CLO: stale");

        uint256 p = Math.mulDiv(uint256(answer), 1e18, 10 ** f.decimals); // → WAD
        if (f.invert) p = Math.mulDiv(1e18, 1e18, p); // 1/p in WAD
        return p;
    }
}
