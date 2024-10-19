import { ethers, upgrades } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();

  console.log("Deploying contracts with the account:", deployer.address);

  const AMMUpgradeable = await ethers.getContractFactory("AMMUpgradeable");
  const ammProxy = await upgrades.deployProxy(AMMUpgradeable, [deployer.address], { kind: "uups" });

  await ammProxy.deployed();

  console.log("AMMUpgradeable deployed to:", ammProxy.address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
