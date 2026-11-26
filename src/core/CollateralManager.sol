// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {PriceOracle} from "../oracle/PriceOracle.sol";
import {HealthLogic} from "../libraries/HealthLogic.sol";

abstract contract CollateralManager {
    using SafeERC20 for IERC20;
    PriceOracle internal priceOracle;

    /// @dev -> how much collateral each user deposited
    mapping(address userAddress => mapping(address asset => uint256 balance)) public userCollateralBalance;
    /// @dev total deposited amount of each asset
    mapping(address => uint256) public totalCollateralPerAsset;
    /// @dev configuration for each asset
    mapping(address => CollateralConfig) public collateralConfigs;

    address[] internal collateralAssets;
    uint256 constant MAXCOLLATERALLIMIT = 10;

    struct CollateralConfig {
        bool isCollateralEnabled;
        uint256 ltv;
        uint256 liquidationThreshold;
        uint8 tokenDecimals;
    }

    error ZeroAddress();
    error InvalidAssetContract();
    error InvalidLTV();
    error InvalidLiquidationThreshold();
    error CollateralNotEnabled();
    error CollateralLimitReached(uint256);

    constructor(address _priceOracle) {
        if (_priceOracle == address(0)) revert ZeroAddress();
        priceOracle = PriceOracle(_priceOracle);
    }

    ////////////////////////////
    //// Internal Functions/////
    ////////////////////////////

    function _collateralPower(address user)
        internal
        view
        returns (uint256 borrowCapacity, uint256 liquidationAdjustedValue)
    {
        uint256 length = collateralAssets.length;
        for (uint256 i = 0; i < length;) {
            address asset = collateralAssets[i];
            // this skips an oracle call if the asset balance is 0
            if (userCollateralBalance[user][asset] == 0) {
                unchecked {
                    ++i;
                }
                continue;
            }
            // skips accounting if the asset is disabled
            if (!collateralConfigs[asset].isCollateralEnabled) {
                unchecked {
                    ++i;
                }
                continue;
            }
            // get the user's balance for each asset
            uint256 assetAmount = userCollateralBalance[user][asset];
            // get the config for each asset
            CollateralConfig memory config = _collateralConfig(asset);
            // the price for each asset
            uint256 assetPrice = priceOracle.getPrice(asset);
            // usd value for each asset
            uint256 assetUSDValue = HealthLogic.getCollateralValue(assetAmount, config.tokenDecimals, assetPrice);
            // how much can be borrowed for each asset (in usd)
            uint256 capacityPerAsset = HealthLogic.getBorrowCapacity(assetUSDValue, config.ltv);
            // collateral's USD value after applying its liquidation threshold
            uint256 liquidationAdjustedValuePerAsset =
                HealthLogic.getBorrowCapacity(assetUSDValue, config.liquidationThreshold);

            borrowCapacity += capacityPerAsset;
            liquidationAdjustedValue += liquidationAdjustedValuePerAsset;

            unchecked {
                ++i;
            }
        }
    }

    function _pullCollateral(IERC20 asset, address user, uint256 amount) internal {
        asset.safeTransferFrom(user, address(this), amount);
    }

    function _pushCollateral(IERC20 asset, address user, uint256 amount) internal {
        asset.safeTransfer(user, amount);
    }

    function _collateralOf(address user, address asset) internal view returns (uint256) {
        return userCollateralBalance[user][asset];
    }

    function _increaseCollateral(address user, address asset, uint256 amount) internal {
        // increase the user's balance
        userCollateralBalance[user][asset] += amount;
        // increase the total collateral for the asset
        totalCollateralPerAsset[asset] += amount;
    }

    function _decreaseCollateral(address user, address asset, uint256 amount) internal {
        // decrease the user's balance
        userCollateralBalance[user][asset] -= amount;
        // decrease the total collateral for the asset
        totalCollateralPerAsset[asset] -= amount;
    }

    function _collateralConfig(address asset) internal view returns (CollateralConfig memory) {
        return collateralConfigs[asset];
    }

    function _requireCollateralEnabled(address asset) internal view {
        if (!collateralConfigs[asset].isCollateralEnabled) revert CollateralNotEnabled();
    }

    ///////////////////////
    /// Setter Functions///
    ///////////////////////

    function _setCollateralConfig(address asset, uint256 ltv, uint256 liquidationThreshold, bool enabled) internal {
        if (asset == address(0)) revert ZeroAddress();
        if (asset.code.length <= 0) revert InvalidAssetContract();
        if (ltv > liquidationThreshold) revert InvalidLTV();
        if (liquidationThreshold > 1e18) revert InvalidLiquidationThreshold();
        uint256 length = collateralAssets.length;

        CollateralConfig memory config =
            CollateralConfig(enabled, ltv, liquidationThreshold, IERC20Metadata(asset).decimals());
        for (uint256 i = 0; i < length;) {
            if (asset == collateralAssets[i]) {
                collateralConfigs[asset] = config;
                return;
            }
            unchecked {
                ++i;
            }
        }
        if (length + 1 > MAXCOLLATERALLIMIT) revert CollateralLimitReached(length + 1);
        collateralAssets.push(asset);
        collateralConfigs[asset] = config;
    }
}
