import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("AMMStorage", (m) => {
  const admin = m.getParameter("admin");
  const ammStorage = m.contract("AMMStorage", [admin]);
  return { ammStorage };
});
