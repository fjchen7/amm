import { ethers, upgrades } from "hardhat";

async function main() {
  const proxyAddress = "YOUR_PROXY_ADDRESS_HERE";

  const AMMUpgradeableV2 = await ethers.getContractFactory("AMMUpgradeableV2");
  console.log("Upgrading AMMUpgradeable...");
  await upgrades.upgradeProxy(proxyAddress, AMMUpgradeableV2);
  console.log("AMMUpgradeable upgraded");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
