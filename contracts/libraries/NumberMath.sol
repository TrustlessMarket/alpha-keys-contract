// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {SafeMathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

library NumberMath {
    // CONST
    uint256 internal constant RATIO = 1e6;
    using SafeMathUpgradeable for uint256;

    uint256 internal constant ONE_ETHER = 1 ether;
    uint256 internal constant PRICE_UNIT = 0.1 ether;
    uint256 internal constant NUMBER_UNIT_PER_ONE_ETHER =
        ONE_ETHER / PRICE_UNIT;

    uint256 internal constant PRICE_BTC_PER_TC = 0.000416666666666667 ether; // 1 BTC = 2400 TC
    uint256 internal constant PRICE_TC_PER_BTC = 2400 ether; // 1 BTC = 2400 TC
    uint256 internal constant PRICE_KEYS_DENOMINATOR = 264000;

    uint256 internal constant TS_30_DAYS = 30 days;

    //
    function mulRatio(
        uint256 value,
        uint24 ratio
    ) internal pure returns (uint256) {
        return value.mul(ratio).div(RATIO);
    }

    function mulEther(uint256 value) internal pure returns (uint256) {
        return value.mul(1 ether);
    }

    function divEther(uint256 value) internal pure returns (uint256) {
        return value.div(1 ether);
    }

    function mulPrice(
        uint256 value,
        uint256 rate
    ) internal pure returns (uint256) {
        return value.mul(rate).div(1 ether);
    }
}
