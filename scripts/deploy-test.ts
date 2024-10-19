import { ethers, upgrades } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();

  console.log("Deploying contracts with the account:", deployer.address);

  const AMMFactory = await ethers.getContractFactory("AMMUpgradeable");
  const ammProxy = await upgrades.deployProxy(AMMFactory, [deployer.address], { kind: "uups" });
  await ammProxy.waitForDeployment();

  const ammProxyAddress = await ammProxy.getAddress();
  console.log("AMM deployed to:", ammProxyAddress);

  // Test adding liquidity
  const Token = await ethers.getContractFactory("MockERC20");
  const token0 = await Token.deploy("Token0", "TK0");
  const token1 = await Token.deploy("Token1", "TK1");

  await token0.waitForDeployment();
  await token1.waitForDeployment();

  const token0Address = await token0.getAddress();
  const token1Address = await token1.getAddress();

  await token0.mint(deployer.address, ethers.parseEther("1000"));
  await token1.mint(deployer.address, ethers.parseEther("1000"));

  await token0.approve(ammProxyAddress, ethers.parseEther("100"));
  await token1.approve(ammProxyAddress, ethers.parseEther("100"));

  await ammProxy.addLiquidity(token0Address, token1Address, ethers.parseEther("100"), ethers.parseEther("100"));

  console.log("Liquidity added successfully");

  // Test swapping
  await token0.approve(ammProxyAddress, ethers.parseEther("10"));
  await ammProxy.swap(token0Address, token1Address, ethers.parseEther("10"));

  console.log("Swap executed successfully");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
