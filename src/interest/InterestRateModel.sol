// SPDX-License-Identifier: MIT

import {FixedPointMath} from "../libraries/FixedPointMath.sol";

pragma solidity 0.8.28;

contract InterestRateModel {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant SECONDS_PER_YEAR = 31_536_000;
    uint256 immutable i_baseRate;
    uint256 immutable i_kink;
    uint256 immutable i_kinkRate;
    uint256 immutable i_maxRate;

    error InvalidKink();
    error InvalidRateProgression();

    constructor(uint256 _baseRate, uint256 _kink, uint256 _kinkRate, uint256 _maxRate) {
        if (_kink == 0 || _kink >= WAD) {
            revert InvalidRateProgression();
        }
        if (_kinkRate < _baseRate || _kinkRate > _maxRate) {
            revert InvalidKink();
        }

        i_baseRate = _baseRate;
        i_kink = _kink;
        i_kinkRate = _kinkRate;
        i_maxRate = _maxRate;
    }

    function getUtilization(uint256 totalSupply, uint256 totalBorrow) public pure returns (uint256) {
        if (totalSupply == 0) {
            return 0;
        }
        return (totalBorrow * WAD / totalSupply);
    }

    function getBorrowRate(uint256 utilization) public view returns (uint256) {
        if (utilization <= i_kink) {
            return
                i_baseRate
                    + FixedPointMath.wadMul((i_kinkRate - i_baseRate), FixedPointMath.wadDiv(utilization, i_kink));
        }
        return i_kinkRate
            + FixedPointMath.wadMul(i_maxRate - i_kinkRate, FixedPointMath.wadDiv(utilization - i_kink, WAD - i_kink));
    }

    function getSupplyRate(uint256 borrowRate, uint256 utilization, uint256 reserveFactor)
        public
        pure
        returns (uint256)
    {
        return FixedPointMath.wadMul(FixedPointMath.wadMul(borrowRate, utilization), WAD - reserveFactor);
    }

    function accrueInterest(uint256 index, uint256 annualRate, uint256 timeElapsed) public pure returns (uint256) {
        // this function grows an index based on elapsed time
        uint256 perSecondGrowth = (annualRate * timeElapsed) / SECONDS_PER_YEAR;
        return index + FixedPointMath.wadMul(index, perSecondGrowth);
    }
}
