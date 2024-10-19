import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import AMMStorage from "./AMMStorage";

export default buildModule("AMMUpgradeable", (m) => {
  const admin = m.getParameter("admin");

  const { ammStorage } = m.useModule(AMMStorage);

  // Deploy AMMUpgradeable implementation contract
  const ammImplementation = m.contract("AMMUpgradeable");

  // Encode initialization call for AMMUpgradeable, including admin and AMMStorage address
  const initialize = m.encodeFunctionCall(ammImplementation, "initialize", [
    admin,
    ammStorage, // Directly use ammStorage contract object
  ]);

  // Deploy proxy contract and initialize
  const ammProxy = m.contract("ERC1967Proxy", [ammImplementation, initialize]);

  return { ammImplementation, ammProxy };
});
