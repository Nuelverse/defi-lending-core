const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Interest Rate Model Test", function () {
  let interestRateModel;
  const baseRate = 0;
  const kink = ethers.parseEther("0.8");
  const kinkRate = ethers.parseEther("0.04");
  const maxRate = ethers.parseEther("0.79");

  beforeEach(async function () {
    const FixedPointMath = await ethers.getContractFactory("FixedPointMath");
    const fixedPointMath = await FixedPointMath.deploy();

    const InterestRateModel = await ethers.getContractFactory(
      "InterestRateModel",
      {
        libraries: {
          FixedPointMath: await fixedPointMath.getAddress(),
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
