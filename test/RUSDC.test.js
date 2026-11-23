const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("RUSDC Token", function () {
  let rusdc;
  let pool;
  let user;
  let unauthorized;
  const mintAmount = 1000e6;
  const burnAmount = 500e6;

  // beforeEach runs before every test in this describe block
  // It's used to set up a fresh state for each test
  beforeEach(async function () {
    // Get signers (accounts) - ethers provides these test accounts
    [pool, user, unauthorized] = await ethers.getSigners();
    const poolAddress = await pool.getAddress();

    // Deploy RUSDC with pool as the authorized minter/burner
    const RUSDC = await ethers.getContractFactory("RUSDC");
    rusdc = await RUSDC.deploy();
    await rusdc.setPool(poolAddress);
  });

  describe("Deployment", function () {
    it("should have correct name and symbol", async function () {
      const name = await rusdc.name();
      const symbol = await rusdc.symbol();

      expect(name).to.equal("Receipt Token");
      expect(symbol).to.equal("rUSDC");
    });

    it("should have 6 decimals", async function () {
      const decimal = await rusdc.decimals();
      expect(decimal).to.equal(6);
    });

    // it("should revert when deployed with zero address", async function () {
    //   const RUSDC = await ethers.getContractFactory("RUSDC");
    //   await expect(
    //     RUSDC.deploy(ethers.ZeroAddress),
    //   ).to.be.revertedWithCustomError(RUSDC, "ZeroAddress");
    // });
  });

  describe("Minting", function () {
    it("should allow pool to mint tokens", async function () {
      await rusdc.connect(pool).mint(user.address, mintAmount);

      const balance = await rusdc.balanceOf(user.address);
      expect(balance).to.equal(mintAmount);
    });

    it("should revert when unauthorized caller tries to mint", async function () {
      await expect(
        rusdc.connect(unauthorized).mint(user.address, mintAmount),
      ).to.be.revertedWithCustomError(rusdc, "UnauthorizedCaller");
    });

    it("should emit Minted event", async function () {
      await expect(rusdc.connect(pool).mint(user.address, mintAmount))
        .to.emit(rusdc, "Minted")
        .withArgs(user.address, mintAmount);
    });
  });

  describe("Burning", function () {
    beforeEach(async function () {
      // Set up: pool mints 1000 rUSDC to user before each burn test
      await rusdc.connect(pool).mint(user.address, 1000e6);
    });

    it("should allow pool to burn tokens", async function () {
      // Pool burns from user
      await rusdc.connect(pool).burn(user.address, burnAmount);

      const balance = await rusdc.balanceOf(user.address);
      expect(balance).to.equal(500e6);
    });

    it("should revert when unauthorized caller tries to burn", async function () {
      await expect(
        rusdc.connect(unauthorized).burn(user.address, mintAmount),
      ).to.be.revertedWithCustomError(rusdc, "UnauthorizedCaller");
    });

    it("should emit Burned event", async function () {
      await expect(rusdc.connect(pool).burn(user.address, burnAmount))
        .to.emit(rusdc, "Burned")
        .withArgs(user.address, burnAmount);
    });
  });

  describe("Transfers", function () {
    beforeEach(async function () {
      await rusdc.connect(pool).mint(user.address, 1000e6);
    });

    it("should allow users to transfer rUSDC", async function () {
      const transferAmount = 300e6;

      await rusdc.connect(user).transfer(unauthorized.address, transferAmount);
      const balance = await rusdc.balanceOf(user.address);
      const balance2 = await rusdc.balanceOf(unauthorized.address);
      expect(balance).to.equal(700e6);
      expect(balance2).to.equal(300e6);
    });
  });
});
