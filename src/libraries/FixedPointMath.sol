// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

library FixedPointMath {
    uint256 internal constant WAD = 1e18;

    function wadMul(uint256 a, uint256 b) external pure returns (uint256) {
        return (a * b) / WAD;
    }

    function wadDiv(uint256 a, uint256 b) external pure returns (uint256) {
        return (a * WAD) / b;
    }

    function wadMulUp(uint256 a, uint256 b) external pure returns (uint256 z) {
        // Multiply and round up
        uint256 product = a * b;
        z = product / WAD;
        if (product % WAD > 0) {
            z += 1;
        }
    }

    function wadDivUp(uint256 a, uint256 b) external pure returns (uint256 z) {
        // Divide and round up
        uint256 product = a * WAD;
        z = product / b;
        if (product % b > 0) {
            z += 1;
        }
    }
}
