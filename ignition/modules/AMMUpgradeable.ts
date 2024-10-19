import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("AMMUpgradeable", (m) => {
  const admin = m.getParameter("admin");

  const ammImplementation = m.contract("AMMUpgradeable");
  // Deploy ERC1967Proxy and initialize it with the AMMUpgradeable contract
  const initialize = m.encodeFunctionCall(ammImplementation, "initialize", [
    admin,
  ]);
  const ammProxy = m.contract("AMMProxy", [ammImplementation, initialize]);

  return { ammImplementation, ammProxy };
});
