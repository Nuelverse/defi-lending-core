const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("FixedPointMath Test", function () {
  let fixedPointMath;
  const WAD = ethers.parseEther("1");
  beforeEach(async function () {
    const FixedPointMath = await ethers.getContractFactory("FixedPointMath");
    fixedPointMath = await FixedPointMath.deploy();
  });

  it("should test wadMul", async function () {
    const x = await fixedPointMath.wadMul(
      ethers.parseEther("1.5"),
      ethers.parseEther("2"),
    );
    expect(x).to.equal(ethers.parseEther("3"));
  });

  it("should test wadDiv", async function () {
    const x = await fixedPointMath.wadDiv(
      ethers.parseEther("3"),
      ethers.parseEther("2"),
    );
    expect(x).to.equal(ethers.parseEther("1.5"));
  });
  it("should test wadMulUp", async function () {
    const x = await fixedPointMath.wadMulUp(WAD + 1n, WAD + 1n);
    expect(x).to.equal(WAD + 3n);
  });
  it("should test wadDivUp", async function () {
    const x = await fixedPointMath.wadDivUp(1n, ethers.parseEther("2"));
    expect(x).to.equal(1n);
  });
});
