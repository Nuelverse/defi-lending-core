const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("LendingPool", function () {
  let lendingPool;
  let rusdc;
  let usdc;
  let interestRateModel;
  let priceOracle;
  let fixedPointMath;
  let poolAddress;
  let owner;
  let user1;
  let user2;

  // Constants
  const INITIAL_USDC_BALANCE = ethers.parseUnits("100000", 6); // 100k USDC (6 decimals)
  const WAD = ethers.parseEther("1"); // 1e18

  // Interest rate model parameters
  const baseRate = 0;
  const kink = ethers.parseEther("0.8"); // 80%
  const kinkRate = ethers.parseEther("0.04"); // 4%
  const maxRate = ethers.parseEther("0.79"); // 79%
  const reserveFactor = ethers.parseEther("0.1"); // 10%

  beforeEach(async function () {
    // Get signers
    [owner, user1, user2] = await ethers.getSigners();

    // Deploy FixedPointMath library
    const FixedPointMath = await ethers.getContractFactory("FixedPointMath");
    fixedPointMath = await FixedPointMath.deploy();
    const fixedPointAddress = await fixedPointMath.getAddress();

    // Deploy mock USDC
    const MockERC20 = await ethers.getContractFactory("MockERC20");
    usdc = await MockERC20.deploy("USD Coin", "USDC", 6);
    const usdcAddress = await usdc.getAddress();

    // Deploy Price Oracle
    const PriceOracle = await ethers.getContractFactory("PriceOracle");
    priceOracle = await PriceOracle.deploy();
    const priceOracleAddress = await priceOracle.getAddress();

    // Mint USDC to test users
    await usdc.mint(user1.address, INITIAL_USDC_BALANCE);
    await usdc.mint(user2.address, INITIAL_USDC_BALANCE);

    // Deploy InterestRateModel
    const InterestRateModel = await ethers.getContractFactory(
      "InterestRateModel",
      {
        libraries: {
          FixedPointMath: fixedPointAddress,
        },
      },
    );
    interestRateModel = await InterestRateModel.deploy(
      baseRate,
      kink,
      kinkRate,
      maxRate,
    );
    const interestRateModelAddress = await interestRateModel.getAddress();

    // Deploy RUSDC (no constructor args now)
    const RUSDC = await ethers.getContractFactory("RUSDC");
    rusdc = await RUSDC.deploy();
    const rusdcAddress = await rusdc.getAddress();

    // Deploy LendingPool (without RUSDC address)
    const LendingPool = await ethers.getContractFactory("LendingPool", {
      libraries: {
        FixedPointMath: fixedPointAddress,
      },
    });
    lendingPool = await LendingPool.deploy(
      usdcAddress,
      interestRateModelAddress,
      priceOracleAddress,
      reserveFactor,
    );
    poolAddress = await lendingPool.getAddress();

    // Wire them together using setters
    await rusdc.setPool(poolAddress);
    await lendingPool.setRUSDC(rusdcAddress);

    // Approve pool to spend users' USDC
    await usdc
      .connect(user1)
      .approve(await lendingPool.getAddress(), ethers.MaxUint256);
    await usdc
      .connect(user2)
      .approve(await lendingPool.getAddress(), ethers.MaxUint256);
  });

  describe("Deployment", function () {
    it("should initialize with correct values", async function () {
      expect(await lendingPool.supplyIndex()).to.equal(WAD);
      expect(await lendingPool.borrowIndex()).to.equal(WAD);
      expect(await lendingPool.totalSupply()).to.equal(0);
      expect(await lendingPool.totalBorrow()).to.equal(0);
      expect(await lendingPool.reserveFactor()).to.equal(reserveFactor);
    });

    it("should revert on zero address in constructor", async function () {
      const LendingPool = await ethers.getContractFactory("LendingPool", {
        libraries: {
          FixedPointMath: await fixedPointMath.getAddress(),
        },
      });

      await expect(
        LendingPool.deploy(
          ethers.ZeroAddress,
          await interestRateModel.getAddress(),
          await priceOracle.getAddress(),
          reserveFactor,
        ),
      ).to.be.revertedWithCustomError(LendingPool, "ZeroAddress");
    });

    it("should revert on invalid reserve factor", async function () {
      const LendingPool = await ethers.getContractFactory("LendingPool", {
        libraries: {
          FixedPointMath: await fixedPointMath.getAddress(),
        },
      });

      await expect(
        LendingPool.deploy(
          await usdc.getAddress(),
          await interestRateModel.getAddress(),
          await priceOracle.getAddress(),
          WAD, // 100% reserve factor (invalid)
        ),
      ).to.be.revertedWithCustomError(LendingPool, "InvalidReserveFactor");
    });
  });

  describe("Supply", function () {
    it("should supply USDC and receive rUSDC", async function () {
      const supplyAmount = ethers.parseUnits("1000", 6); // 1000 USDC

      await lendingPool.connect(user1).supply(supplyAmount);
      const rUSDCBalance = await rusdc.balanceOf(user1.address);
      expect(rUSDCBalance).to.equal(supplyAmount);

      const poolBalance = await usdc.balanceOf(poolAddress);
      expect(poolBalance).to.equal(supplyAmount);

      expect(await lendingPool.totalSupply()).to.equal(supplyAmount);
    });

    it("should revert on zero amount", async function () {
      await expect(
        lendingPool.connect(user1).supply(0),
      ).to.be.revertedWithCustomError(lendingPool, "ZeroAmount");
    });

    it("should revert on zero-mint", async function () {
      // TODO: This is tricky - need to get supply index very high, then try to supply 1 wei
      // For now, skip this test (we'll add it after we understand how to manipulate index)
      // Or: supply a lot first, time travel with high rates, then try supplying 1 wei
    });

    it("should emit Supplied event", async function () {
      const supplyAmount = ethers.parseUnits("1000", 6);
      await expect(lendingPool.connect(user1).supply(supplyAmount)).to.emit(
        lendingPool,
        "Supplied",
      );
    });
  });

  describe("Withdraw", function () {
    beforeEach(async function () {
      // Setup: user1 supplies 10,000 USDC before each withdraw test
      const supplyAmount = ethers.parseUnits("10000", 6);
      await lendingPool.connect(user1).supply(supplyAmount);
    });

    it("should withdraw USDC and burn rUSDC", async function () {
      const withdrawAmount = ethers.parseUnits("5000", 6); // Withdraw half

      // TODO: user1 withdraws, check rUSDC burned and USDC received
      // YOUR CODE HERE
      const rUSDCBalanceBefore = await rusdc.balanceOf(user1);
      const usdcBefore = await usdc.balanceOf(user1);

      await lendingPool.connect(user1).withdraw(withdrawAmount);
      const rUSDCBalanceAfter = await rusdc.balanceOf(user1);

      const usdcAfter = await usdc.balanceOf(user1);

      expect(rUSDCBalanceBefore - rUSDCBalanceAfter).to.equal(withdrawAmount);
      expect(usdcAfter - usdcBefore).to.equal(withdrawAmount);
    });

    it("should allow full withdrawal with no dust", async function () {
      const withdrawAmount = ethers.parseUnits("10000", 6); // Withdraw all

      await lendingPool.connect(user1).withdraw(withdrawAmount);

      expect(await usdc.balanceOf(poolAddress)).to.equal(0);
      expect(await rusdc.balanceOf(user1)).to.equal(0);
    });

    it("should revert on zero amount", async function () {
      await expect(
        lendingPool.connect(user1).withdraw(0),
      ).to.be.revertedWithCustomError(lendingPool, "ZeroAmount");
    });

    it("should revert on insufficient rUSDC balance", async function () {
      const tooMuch = ethers.parseUnits("20000", 6); // More than they have
      await expect(
        lendingPool.connect(user1).withdraw(tooMuch),
      ).to.be.revertedWithCustomError(lendingPool, "InsufficientBalance");
    });

    it("should revert on insufficient pool liquidity", async function () {
      // TODO: This requires removing USDC from pool somehow
      // Skipping for now, have user2 also supply, then have someone else borrow it all (Stage 5)
    });

    it("should emit Withdrawn event", async function () {
      const withdrawAmount = ethers.parseUnits("5000", 6);
      await expect(lendingPool.connect(user1).withdraw(withdrawAmount)).to.emit(
        lendingPool,
        "Withdrawn",
      );
    });
  });

  describe("Interest Accrual and Time Passage", function () {
    it("should grow supplier value over time (no borrowers yet)", async function () {
      // Note: With no borrowers, supply index won't grow (supply rate = 0)
      // This test will show that index stays at 1.0

      const supplyAmount = ethers.parseUnits("1000", 6);
      await lendingPool.connect(user1).supply(supplyAmount);

      const rUSDCBefore = await rusdc.balanceOf(user1.address);
      const indexBefore = await lendingPool.supplyIndex();

      // Time travel 1 year
      await time.increase(31536000);

      // Trigger accrual by having user2 supply something
      await lendingPool.connect(user2).supply(ethers.parseUnits("1", 6));

      const indexAfter = await lendingPool.supplyIndex();
      const rUSDCAfter = await rusdc.balanceOf(user1.address);

      // With no borrowers, index should NOT have grown
      expect(indexAfter).to.equal(indexBefore);
      expect(rUSDCAfter).to.equal(rUSDCBefore); // rUSDC balance unchanged

      // TODO: Later in Stage 5, when we have borrowers, this test should show growth
    });
  });

  describe("Edge Cases", function () {
    it("should handle USDC donation without changing indexes", async function () {
      const supplyAmount = ethers.parseUnits("1000", 6);
      await lendingPool.connect(user1).supply(supplyAmount);

      const indexBefore = await lendingPool.supplyIndex();

      // Someone donates USDC directly to pool (not through supply)
      await usdc
        .connect(user2)
        .transfer(await poolAddress, ethers.parseUnits("5000", 6));

      // Trigger accrual
      await lendingPool.connect(user2).supply(ethers.parseUnits("1", 6));

      const indexAfter = await lendingPool.supplyIndex();

      // Index should not have changed from donation
      expect(indexAfter).to.equal(indexBefore);
    });

    it("should allow rUSDC transfers between users", async function () {
      const supplyAmount = ethers.parseUnits("1000", 6);
      await lendingPool.connect(user1).supply(supplyAmount);

      const transferAmount = ethers.parseUnits("300", 6);
      await rusdc.connect(user1).transfer(user2.address, transferAmount);

      expect(await rusdc.balanceOf(user2)).to.equal(transferAmount);
      const usdcBefore = await usdc.balanceOf(user2);
      await lendingPool.connect(user2).withdraw(transferAmount);

      expect(await rusdc.balanceOf(user2)).to.equal(0);
      expect(await usdc.balanceOf(user2)).to.equal(usdcBefore + transferAmount);
    });

    it("should protect against reentrancy on withdraw", async function () {
      // Deploy a malicious contract that tries to reenter on withdraw
      // This requires writing a malicious contract
      // The nonReentrant modifier should protect the pool
    });
  });
});
