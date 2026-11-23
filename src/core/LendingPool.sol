// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {RUSDC} from "../tokens/RUSDC.sol";
import {InterestRateModel} from "../interest/InterestRateModel.sol";
import {FixedPointMath} from "../libraries/FixedPointMath.sol";

contract LendingPool is Ownable2Step, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using FixedPointMath for uint256;

    uint256 private constant WAD = 1e18;
    IERC20 public immutable usdc;
    RUSDC public rusdc;
    InterestRateModel public immutable interestRateModel;
    uint256 public reserveFactor;
    uint256 public supplyIndex;
    uint256 public borrowIndex;
    uint256 public lastUpdateTimestamp;
    uint256 public totalSupply;
    uint256 public totalBorrow;

    error ZeroAddress();
    error ZeroMint();
    error ZeroAmount();
    error RUSDCAlreadySet(address);
    error InsufficientBalance();
    error InsufficientLiquidity();
    error InvalidReserveFactor();

    event InterestAccrued(uint256 supplyIndex, uint256 borrowIndex, uint256 timestamp);
    event Supplied(address indexed user, uint256 usdcAmount, uint256 rUSDCMinted);
    event Withdrawn(address indexed user, uint256 usdcAmount, uint256 rUSDCBurned);

    constructor(address _usdc, address _interestRateModel, uint256 _reserveFactor) Ownable(msg.sender) {
        if (_usdc == address(0) || _interestRateModel == address(0)) {
            revert ZeroAddress();
        }
        if (_reserveFactor >= WAD) {
            revert InvalidReserveFactor();
        }
        usdc = IERC20(_usdc);
        interestRateModel = InterestRateModel(_interestRateModel);
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
        uint256 utilization = interestRateModel.getUtilization(totalSupply, totalBorrow);
        uint256 borrowRate = interestRateModel.getBorrowRate(utilization);
        uint256 supplyRate = interestRateModel.getSupplyRate(borrowRate, utilization, reserveFactor);

        borrowIndex = interestRateModel.accrueInterest(borrowIndex, borrowRate, timeElapsed);
        supplyIndex = interestRateModel.accrueInterest(supplyIndex, supplyRate, timeElapsed);
        lastUpdateTimestamp = block.timestamp;

        emit InterestAccrued(supplyIndex, borrowIndex, block.timestamp);
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
        totalSupply += amount;

        emit Supplied(msg.sender, amount, rUSDCToMint);
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

        totalSupply -= amount;
        emit Withdrawn(msg.sender, amount, rUSDCToBurn);
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
