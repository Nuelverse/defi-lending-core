const { expect } = require("chai");
const { ethers } = require("hardhat");

///////// InterestRateModel tests for rate calculations ///////////
const baseRate = 0;
const kink = ethers.parseEther("0.8");
const kinkRate = ethers.parseEther("0.04");
const maxRate = ethers.parseEther("0.79");
let fixedPointAddress;
let interestRateModel;

describe("Interest Rate Model Test", function () {
  beforeEach(async function () {
    const FixedPointMath = await ethers.getContractFactory("FixedPointMath");
    const fixedPointMath = await FixedPointMath.deploy();
    fixedPointAddress = await fixedPointMath.getAddress();

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
  });

  it("should return correct borrow rate below kink (50% utilization)", async function () {
    const x = await interestRateModel.getBorrowRate(ethers.parseEther("0.5"));
    expect(x).to.equal(ethers.parseEther("0.025"));
  });

  it("should return correct borrow rate above kink (90% utilization)", async function () {
    const x = await interestRateModel.getBorrowRate(ethers.parseEther("0.9"));
    expect(x).to.equal(ethers.parseEther("0.415"));
  });

  it("should return correct supply rate with reserve factor", async function () {
    const x = await interestRateModel.getSupplyRate(
      ethers.parseEther("0.04"),
      ethers.parseEther("0.8"),
      ethers.parseEther("0.1"),
    );
    expect(x).to.equal(ethers.parseEther("0.0288"));
  });
});

//////// Construction Validation Test //////////

describe("Construction Validation Test", function () {
  it("should revert when kink is 0", async function () {
    const InterestRateModel = await ethers.getContractFactory(
      "InterestRateModel",
      {
        libraries: {
          FixedPointMath: fixedPointAddress,
        },
      },
    );
    await expect(
      InterestRateModel.deploy(baseRate, 0, kinkRate, maxRate),
    ).to.be.revertedWithCustomError(
      InterestRateModel,
      "InvalidRateProgression",
    );
  });

  it("should revert when kink is > WAD(1e18)", async function () {
    const InterestRateModel = await ethers.getContractFactory(
      "InterestRateModel",
      {
        libraries: {
          FixedPointMath: fixedPointAddress,
        },
      },
    );
    await expect(
      InterestRateModel.deploy(
        baseRate,
        ethers.parseEther("2"),
        kinkRate,
        maxRate,
      ),
    ).to.be.revertedWithCustomError(
      InterestRateModel,
      "InvalidRateProgression",
    );
  });

  it("should revert when kinkRate < baseRate", async function () {
    const InterestRateModel = await ethers.getContractFactory(
      "InterestRateModel",
      {
        libraries: {
          FixedPointMath: fixedPointAddress,
        },
      },
    );
    await expect(
      InterestRateModel.deploy(
        ethers.parseEther("2"),
        kink,
        ethers.parseEther("1"),
        maxRate,
      ),
    ).to.be.revertedWithCustomError(InterestRateModel, "InvalidKink");
  });

  it("should revert when kinkRate > maxRate", async function () {
    const InterestRateModel = await ethers.getContractFactory(
      "InterestRateModel",
      {
        libraries: {
          FixedPointMath: fixedPointAddress,
        },
      },
    );
    await expect(
      InterestRateModel.deploy(baseRate, kink, ethers.parseEther("1"), maxRate),
    ).to.be.revertedWithCustomError(InterestRateModel, "InvalidKink");
  });

  //////// Accrue Interest Test ///////////

  describe("Accrue Interest Test", function () {
    it("should grow index correctly after 1 year at 4%", async function () {
      const result = await interestRateModel.accrueInterest(
        ethers.parseEther("1"),
        ethers.parseEther("0.04"),
        31_536_000,
      );

      expect(result).to.equal(ethers.parseEther("1.04"));
    });

    it("should return same index when timeElapsed is 0", async function () {
      const result = await interestRateModel.accrueInterest(
        ethers.parseEther("1.5"),
        ethers.parseEther("0.04"),
        0,
      );

      expect(result).to.equal(ethers.parseEther("1.5"));
    });

    it("should never decrease index", async function () {
      const result = await interestRateModel.accrueInterest(
        ethers.parseEther("2"),
        ethers.parseEther("0.1"),
        0,
      );

      expect(result).to.be.greaterThanOrEqual(ethers.parseEther("2"));
    });
  });
});
