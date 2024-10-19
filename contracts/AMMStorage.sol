// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";

contract AMMStorage is AccessControl {
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    struct LiquidityPool {
        uint256 token0Balance;
        uint256 token1Balance;
        uint256 totalLiquidity;
    }

    mapping(address => mapping(address => LiquidityPool)) public liquidityPools;
    mapping(address => mapping(address => mapping(address => uint256))) public userLiquidity;

    uint256 public constant FEE_PERCENTAGE = 30; // 0.3%
    uint256 public constant FEE_DENOMINATOR = 10000;

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MANAGER_ROLE, admin);
    }

    function setLiquidityPool(address token0, address token1, LiquidityPool memory pool) external onlyRole(MANAGER_ROLE) {
        liquidityPools[token0][token1] = pool;
    }

    function getLiquidityPool(address token0, address token1) external view returns (LiquidityPool memory) {
        return liquidityPools[token0][token1];
    }

    function setUserLiquidity(address user, address token0, address token1, uint256 liquidity) external onlyRole(MANAGER_ROLE) {
        userLiquidity[user][token0][token1] = liquidity;
    }

    function addManager(address newManager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(MANAGER_ROLE, newManager);
    }

    function removeManager(address manager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        revokeRole(MANAGER_ROLE, manager);
    }
}
