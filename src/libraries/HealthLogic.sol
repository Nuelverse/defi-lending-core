// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

library HealthLogic {
    // Calculates how much a user can borrow and
    // How safe is the user debt ??
    // Hf = (collateral value * LT) / debt value

    function getCollateralValue(uint256 amount, uint8 tokenDecimals, uint256 price) internal pure returns (uint256) {
        return Math.mulDiv(amount, price, 10 ** tokenDecimals);
    }

    function getDebtValue(uint256 amount, uint8 tokenDecimals, uint256 price) internal pure returns (uint256) {
        return Math.mulDiv(amount, price, 10 ** tokenDecimals, Math.Rounding.Ceil);
    }

    function getBorrowCapacity(uint256 collateralValue, uint256 ltv) internal pure returns (uint256) {
        return Math.mulDiv(collateralValue, ltv, 1e18);
    }

    function getHealthFactor(uint256 collateralValue, uint256 liquidationThreshold, uint256 debtValue)
        internal
        pure
        returns (uint256)
    {
        if (debtValue == 0) {
            return type(uint256).max;
        }
        return Math.mulDiv(collateralValue, liquidationThreshold, debtValue);
    }

    function isWithinCapacity(uint256 debtValue, uint256 borrowCapacity) internal pure returns (bool) {
        return (debtValue <= borrowCapacity) ? true : false;
    }
}
