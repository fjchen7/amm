import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { Contract, Signer } from "ethers";

describe("AMMUpgradeable", function () {
  let ammProxy: Contract;
  let token0: Contract;
  let token1: Contract;
  let owner: Signer;
  let user1: Signer;
  let user2: Signer;

  beforeEach(async function () {
    [owner, user1, user2] = await ethers.getSigners();

    const AMMUpgradeable = await ethers.getContractFactory("AMMUpgradeable");
    ammProxy = await upgrades.deployProxy(AMMUpgradeable, [await owner.getAddress()], { kind: "uups" });

    const Token = await ethers.getContractFactory("MockERC20");
    token0 = await Token.deploy("Token0", "TK0");
    token1 = await Token.deploy("Token1", "TK1");

    await token0.mint(await owner.getAddress(), ethers.parseEther("10000"));
    await token1.mint(await owner.getAddress(), ethers.parseEther("10000"));
    await token0.mint(await user1.getAddress(), ethers.parseEther("1000"));
    await token1.mint(await user1.getAddress(), ethers.parseEther("1000"));
  });

  describe("Initialization", function () {
    it("should correctly set the admin role", async function () {
      expect(await ammProxy.hasRole(await ammProxy.DEFAULT_ADMIN_ROLE(), await owner.getAddress())).to.be.true;
    });

    it("should correctly set the upgrader role", async function () {
      expect(await ammProxy.hasRole(await ammProxy.UPGRADER_ROLE(), await owner.getAddress())).to.be.true;
    });
  });

  describe("Adding Liquidity", function () {
    it("should successfully add liquidity", async function () {
      await token0.approve(ammProxy.getAddress(), ethers.parseEther("100"));
      await token1.approve(ammProxy.getAddress(), ethers.parseEther("100"));

      await expect(ammProxy.addLiquidity(await token0.getAddress(), await token1.getAddress(), ethers.parseEther("100"), ethers.parseEther("100")))
        .to.emit(ammProxy, "LiquidityAdded")
        .withArgs(await owner.getAddress(), await token0.getAddress(), await token1.getAddress(), ethers.parseEther("100"), ethers.parseEther("100"), ethers.parseEther("100"));

      const pool = await ammProxy.liquidityPools(await token0.getAddress(), await token1.getAddress());
      expect(pool.token0Balance).to.equal(ethers.parseEther("100"));
      expect(pool.token1Balance).to.equal(ethers.parseEther("100"));
      expect(pool.totalLiquidity).to.equal(ethers.parseEther("100"));
    });

    it("should reject adding identical tokens", async function () {
      await expect(ammProxy.addLiquidity(await token0.getAddress(), await token0.getAddress(), ethers.parseEther("100"), ethers.parseEther("100")))
        .to.be.revertedWith("Identical tokens");
    });

    it("should reject adding zero amounts", async function () {
      await expect(ammProxy.addLiquidity(await token0.getAddress(), await token1.getAddress(), 0, ethers.parseEther("100")))
        .to.be.revertedWith("Amounts must be positive");
    });
  });

  describe("Removing Liquidity", function () {
    beforeEach(async function () {
      await token0.approve(ammProxy.getAddress(), ethers.parseEther("100"));
      await token1.approve(ammProxy.getAddress(), ethers.parseEther("100"));
      await ammProxy.addLiquidity(await token0.getAddress(), await token1.getAddress(), ethers.parseEther("100"), ethers.parseEther("100"));
    });

    it("should successfully remove liquidity", async function () {
      await expect(ammProxy.removeLiquidity(await token0.getAddress(), await token1.getAddress(), ethers.parseEther("50")))
        .to.emit(ammProxy, "LiquidityRemoved")
        .withArgs(await owner.getAddress(), await token0.getAddress(), await token1.getAddress(), ethers.parseEther("50"), ethers.parseEther("50"), ethers.parseEther("50"));

      const pool = await ammProxy.liquidityPools(await token0.getAddress(), await token1.getAddress());
      expect(pool.token0Balance).to.equal(ethers.parseEther("50"));
      expect(pool.token1Balance).to.equal(ethers.parseEther("50"));
      expect(pool.totalLiquidity).to.equal(ethers.parseEther("50"));
    });

    it("should reject removing excessive liquidity", async function () {
      await expect(ammProxy.removeLiquidity(await token0.getAddress(), await token1.getAddress(), ethers.parseEther("101")))
        .to.be.revertedWith("Insufficient user liquidity");
    });
  });

  describe("Token Swapping", function () {
    beforeEach(async function () {
      await token0.approve(ammProxy.getAddress(), ethers.parseEther("1000"));
      await token1.approve(ammProxy.getAddress(), ethers.parseEther("1000"));
      await ammProxy.addLiquidity(await token0.getAddress(), await token1.getAddress(), ethers.parseEther("1000"), ethers.parseEther("1000"));
    });

    it("should successfully swap tokens", async function () {
      await token0.connect(user1).approve(ammProxy.getAddress(), ethers.parseEther("10"));

      const initialBalance = await token1.balanceOf(await user1.getAddress());

      const tx = await ammProxy.connect(user1).swap(await token0.getAddress(), await token1.getAddress(), ethers.parseEther("10"));
      const receipt = await tx.wait();

      // Get Swap event
      const swapEvent = receipt.logs.find(
        (log) => log.topics[0] === ammProxy.interface.getEvent("Swap").topicHash
      );

      if (!swapEvent) {
        throw new Error("Swap event not found");
      }

      const decodedEvent = ammProxy.interface.parseLog(swapEvent);
      const actualOutputAmount = decodedEvent.args.amountOut;

      const finalBalance = await token1.balanceOf(await user1.getAddress());

      // Use BigInt for calculation
      expect(BigInt(finalBalance) - BigInt(initialBalance)).to.equal(BigInt(actualOutputAmount));
    });

    it("should reject swapping identical tokens", async function () {
      await expect(ammProxy.swap(await token0.getAddress(), await token0.getAddress(), ethers.parseEther("10")))
        .to.be.revertedWith("Identical tokens");
    });

    it("should reject swapping zero amounts", async function () {
      await expect(ammProxy.swap(await token0.getAddress(), await token1.getAddress(), 0))
        .to.be.revertedWith("Amount must be positive");
    });
  });
});
