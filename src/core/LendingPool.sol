// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {RUSDC} from "../tokens/RUSDC.sol";
import {InterestRateModel} from "../interest/InterestRateModel.sol";
import {FixedPointMath} from "../libraries/FixedPointMath.sol";
import {HealthLogic} from "../libraries/HealthLogic.sol";
import {PriceOracle} from "../oracle/PriceOracle.sol";
import {CollateralManager} from "./CollateralManager.sol";

contract LendingPool is CollateralManager, Ownable2Step, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using FixedPointMath for uint256;

    uint256 private constant WAD = 1e18;
    IERC20 public immutable usdc;
    RUSDC public rusdc;
    InterestRateModel public immutable interestRateModel;
    // PriceOracle public immutable priceOracle;
    uint256 public reserveFactor;
    uint256 public supplyIndex;
    uint256 public borrowIndex;
    uint256 public lastUpdateTimestamp;

    mapping(address => uint256) public userBorrowShares;
    uint256 internal totalBorrowShares;

    // error ZeroAddress();
    error ZeroMint();
    error ZeroAmount();
    error RUSDCAlreadySet(address);
    error InsufficientBalance();
    error InsufficientLiquidity();
    error InvalidReserveFactor();
    error AssetNotEnabled();
    error InsufficientCollateralCapacity(uint256, uint256);

    event InterestAccrued(
        uint256 supplyIndex,
        uint256 borrowIndex,
        uint256 utilization,
        uint256 supplyRate,
        uint256 borrowRate,
        uint256 timestamp
    );
    event SupplyUSDC(address indexed user, uint256 amount, uint256 rUSDCMinted, uint256 supplyIndex);
    event WithdrawUSDC(address indexed user, uint256 amount, uint256 rUSDCBurned, uint256 supplyIndex);
    event BorrowUSDC(address indexed user, uint256 amount, uint256 borrowIndex);
    event RepayUSDC(address indexed user, uint256 amount, uint256 borrowIndex);

    event SupplyCollateral(address indexed user, address indexed collateralAsset, uint256 amount);
    event WithdrawCollateral(address indexed user, address indexed collateralAsset, uint256 amount);

    constructor(address _usdc, address _interestRateModel, address _priceOracle, uint256 _reserveFactor)
        Ownable(msg.sender)
        CollateralManager(_priceOracle)
    {
        if (_usdc == address(0) || _interestRateModel == address(0)) {
            revert ZeroAddress();
        }
        if (_reserveFactor >= WAD) {
            revert InvalidReserveFactor();
        }
        usdc = IERC20(_usdc);
        interestRateModel = InterestRateModel(_interestRateModel);
        // priceOracle = PriceOracle(_priceOracle);
        reserveFactor = _reserveFactor;
        supplyIndex = WAD;
        borrowIndex = WAD;
        lastUpdateTimestamp = block.timestamp;
    }

    function _accrueInterest() internal {
        uint256 timeElapsed = block.timestamp - lastUpdateTimestamp;
        if (timeElapsed == 0) {
            return;
        }
        // already handles totalSupply == 0 case in interestRateModel, which returns 0
        uint256 totalSupply = _totalSupplyBalance();
        uint256 totalBorrow = _totalBorrowBalance();
        uint256 utilization = interestRateModel.getUtilization(totalSupply, totalBorrow);
        uint256 borrowRate = interestRateModel.getBorrowRate(utilization);
        uint256 supplyRate = interestRateModel.getSupplyRate(borrowRate, utilization, reserveFactor);

        borrowIndex = interestRateModel.accrueInterest(borrowIndex, borrowRate, timeElapsed);
        supplyIndex = interestRateModel.accrueInterest(supplyIndex, supplyRate, timeElapsed);
        lastUpdateTimestamp = block.timestamp;

        emit InterestAccrued(supplyIndex, borrowIndex, utilization, supplyRate, borrowRate, block.timestamp);
    }

    function supply(uint256 amount) external whenNotPaused nonReentrant {
        if (amount == 0) {
            revert ZeroAmount();
        }
        _accrueInterest();
        uint256 rUSDCToMint = amount.wadDiv(supplyIndex);
        if (rUSDCToMint == 0) {
            revert ZeroMint();
        }
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        rusdc.mint(msg.sender, rUSDCToMint);

        emit SupplyUSDC(msg.sender, amount, rUSDCToMint, supplyIndex);
    }

    function withdraw(uint256 amount) external nonReentrant {
        if (amount == 0) {
            revert ZeroAmount();
        }
        _accrueInterest();
        uint256 rUSDCToBurn = amount.wadDivUp(supplyIndex);
        if (rusdc.balanceOf(msg.sender) < rUSDCToBurn) {
            revert InsufficientBalance();
        }
        if (usdc.balanceOf(address(this)) < amount) {
            revert InsufficientLiquidity();
        }

        rusdc.burn(msg.sender, rUSDCToBurn);
        usdc.safeTransfer(msg.sender, amount);

        emit WithdrawUSDC(msg.sender, amount, rUSDCToBurn, supplyIndex);
    }

    function depositCollateral(address asset, uint256 amount) external {
        // check asset is enabled
        _requireCollateralEnabled(asset);
        if (amount == 0) revert ZeroAmount();
        _pullCollateral(IERC20(asset), msg.sender, amount);
        _increaseCollateral(msg.sender, asset, amount);

        emit SupplyCollateral(msg.sender, asset, amount);
    }

    function borrow(uint256 amount) external whenNotPaused nonReentrant {
        if (amount == 0) revert ZeroAmount();
        _accrueInterest();

        uint256 sharesToMint = amount.wadDivUp(borrowIndex);
        userBorrowShares[msg.sender] += sharesToMint;
        totalBorrowShares += sharesToMint;

        _requireWithinCapacity(msg.sender);

        if (usdc.balanceOf(address(this)) < amount) {
            revert InsufficientLiquidity();
        }
        usdc.safeTransfer(msg.sender, amount);

        emit BorrowUSDC(msg.sender, amount, borrowIndex);
    }

    function repay(uint256 amount) external {}

    function withdrawCollateral(address asset, uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        _accrueInterest();
        _decreaseCollateral(msg.sender, asset, amount);
        // _requireWithinCapacity(msg.sender);
    }

    //////////////////////////
    /// Internal Functions ///
    //////////////////////////

    function _borrowBalanceOf(address user) internal view returns (uint256) {
        return userBorrowShares[user].wadMulUp(borrowIndex);
    }

    function _totalBorrowBalance() internal view returns (uint256) {
        return totalBorrowShares.wadMulUp(borrowIndex);
    }

    function _totalSupplyBalance() internal view returns (uint256) {
        return rusdc.totalSupply().wadMul(supplyIndex);
    }

    function _requireWithinCapacity(address user) internal view {
        (uint256 borrowCapacity,) = _collateralPower(user);
        uint256 debtValue = HealthLogic.getDebtValue(
            _borrowBalanceOf(user), IERC20Metadata(address(usdc)).decimals(), priceOracle.getPrice(address(usdc))
        );

        if (debtValue > borrowCapacity) {
            revert InsufficientCollateralCapacity(debtValue, borrowCapacity);
        }
    }

    //////////////////////
    /// View Functions ///
    //////////////////////

    function getCollateralBalanceOf(address user, address asset) public view returns (uint256) {
        return _collateralOf(user, asset);
    }

    function getBorrowBalanceOf(address user) public view returns (uint256) {
        return _borrowBalanceOf(user);
    }

    function getAccountLiquidity(address user)
        public
        view
        returns (uint256 borrowCapacity, uint256 debtValue, uint256 availableToBorrow)
    {
        (borrowCapacity,) = _collateralPower(user);
        debtValue = HealthLogic.getDebtValue(
            _borrowBalanceOf(user), IERC20Metadata(address(usdc)).decimals(), priceOracle.getPrice(address(usdc))
        );
        if (borrowCapacity < debtValue) {
            availableToBorrow = 0;
        } else {
            availableToBorrow = borrowCapacity - debtValue;
        }
    }

    function getHealthFactor(address user) public view returns (uint256) {
        (, uint256 liquidationAdjustedValue) = _collateralPower(user);

        uint256 debtValue = HealthLogic.getDebtValue(
            _borrowBalanceOf(user), IERC20Metadata(address(usdc)).decimals(), priceOracle.getPrice(address(usdc))
        );

        return HealthLogic.getHealthFactor(liquidationAdjustedValue, 1e18, debtValue);
    }

    function getUtilization() public view returns (uint256) {
        return interestRateModel.getUtilization(_totalSupplyBalance(), _totalBorrowBalance());
    }

    function getBorrowRate() public view returns (uint256) {
        return interestRateModel.getBorrowRate(getUtilization());
    }

    //// Setter Function ////////

    function setRUSDC(address _rusdc) external onlyOwner {
        if (address(rusdc) != address(0)) {
            revert RUSDCAlreadySet(address(rusdc));
        }
        if (_rusdc == address(0)) {
            revert ZeroAddress();
        }
        rusdc = RUSDC(_rusdc);
    }
}
