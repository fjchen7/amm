// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

contract AMMUpgradeable is Initializable, UUPSUpgradeable, AccessControlUpgradeable {
    using SafeERC20 for IERC20;

    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    struct LiquidityPool {
        uint256 token0Balance;
        uint256 token1Balance;
        uint256 totalLiquidity;
    }

    mapping(address => mapping(address => LiquidityPool)) public liquidityPools;
    mapping(address => mapping(address => mapping(address => uint256))) public userLiquidity;

    uint256 public constant FEE_PERCENTAGE = 30; // 0.3%
    uint256 public constant FEE_DENOMINATOR = 10000;

    event LiquidityAdded(address indexed provider, address indexed token0, address indexed token1, uint256 amount0, uint256 amount1, uint256 liquidity);
    event LiquidityRemoved(address indexed provider, address indexed token0, address indexed token1, uint256 amount0, uint256 amount1, uint256 liquidity);
    event Swap(address indexed user, address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address admin) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
    }

    function addLiquidity(address token0, address token1, uint256 amount0, uint256 amount1) external {
        require(token0 != token1, "Identical tokens");
        require(amount0 > 0 && amount1 > 0, "Amounts must be positive");

        IERC20(token0).safeTransferFrom(msg.sender, address(this), amount0);
        IERC20(token1).safeTransferFrom(msg.sender, address(this), amount1);

        LiquidityPool storage pool = liquidityPools[token0][token1];
        uint256 liquidity;

        if (pool.totalLiquidity == 0) {
            liquidity = Math.sqrt(amount0 * amount1);
        } else {
            uint256 liquidity0 = (amount0 * pool.totalLiquidity) / pool.token0Balance;
            uint256 liquidity1 = (amount1 * pool.totalLiquidity) / pool.token1Balance;
            liquidity = Math.min(liquidity0, liquidity1);
        }

        require(liquidity > 0, "Insufficient liquidity minted");

        pool.token0Balance += amount0;
        pool.token1Balance += amount1;
        pool.totalLiquidity += liquidity;
        userLiquidity[msg.sender][token0][token1] += liquidity;

        emit LiquidityAdded(msg.sender, token0, token1, amount0, amount1, liquidity);
    }

    function removeLiquidity(address token0, address token1, uint256 liquidity) external {
        require(liquidity > 0, "Insufficient liquidity burned");
        LiquidityPool storage pool = liquidityPools[token0][token1];
        require(pool.totalLiquidity > 0, "Pool does not exist");

        uint256 userLiquidityBalance = userLiquidity[msg.sender][token0][token1];
        require(userLiquidityBalance >= liquidity, "Insufficient user liquidity");

        uint256 amount0 = (liquidity * pool.token0Balance) / pool.totalLiquidity;
        uint256 amount1 = (liquidity * pool.token1Balance) / pool.totalLiquidity;

        pool.token0Balance -= amount0;
        pool.token1Balance -= amount1;
        pool.totalLiquidity -= liquidity;
        userLiquidity[msg.sender][token0][token1] -= liquidity;

        IERC20(token0).safeTransfer(msg.sender, amount0);
        IERC20(token1).safeTransfer(msg.sender, amount1);

        emit LiquidityRemoved(msg.sender, token0, token1, amount0, amount1, liquidity);
    }

    function swap(address tokenIn, address tokenOut, uint256 amountIn) external {
        require(tokenIn != tokenOut, "Identical tokens");
        require(amountIn > 0, "Amount must be positive");

        LiquidityPool storage pool = liquidityPools[tokenIn][tokenOut];
        require(pool.totalLiquidity > 0, "Pool does not exist");

        uint256 amountInWithFee = amountIn * (FEE_DENOMINATOR - FEE_PERCENTAGE) / FEE_DENOMINATOR;
        uint256 amountOut = (pool.token1Balance * amountInWithFee) / (pool.token0Balance + amountInWithFee);

        require(amountOut > 0, "Insufficient output amount");

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenOut).safeTransfer(msg.sender, amountOut);

        pool.token0Balance += amountIn;
        pool.token1Balance -= amountOut;

        emit Swap(msg.sender, tokenIn, tokenOut, amountIn, amountOut);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}
}
