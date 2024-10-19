// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./AMMStorage.sol";

contract AMMUpgradeable is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;

    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    AMMStorage public ammStorage;

    struct LiquidityPool {
        uint256 token0Balance;
        uint256 token1Balance;
        uint256 totalLiquidity;
    }

    mapping(address => mapping(address => LiquidityPool)) public liquidityPools;
    mapping(address => mapping(address => mapping(address => uint256)))
        public userLiquidity;

    uint256 private FEE_PERCENTAGE;
    uint256 private immutable FEE_DENOMINATOR = 10000;

    event LiquidityAdded(
        address indexed provider,
        address indexed token0,
        address indexed token1,
        uint256 amount0,
        uint256 amount1,
        uint256 liquidity
    );
    event LiquidityRemoved(
        address indexed provider,
        address indexed token0,
        address indexed token1,
        uint256 amount0,
        uint256 amount1,
        uint256 liquidity
    );
    event Swap(
        address indexed user,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );
    event FeePercentageChanged(uint256 newFeePercentage);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address admin, address storageAddress) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);

        ammStorage = AMMStorage(storageAddress);
        FEE_PERCENTAGE = 30; // 设置初始费率为 0.3%
    }

    function addLiquidity(
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1
    ) external nonReentrant whenNotPaused {
        require(token0 != token1, "Identical tokens");
        require(amount0 > 0 && amount1 > 0, "Amounts must be positive");

        AMMStorage.LiquidityPool memory pool = ammStorage.getLiquidityPool(token0, token1);
        uint256 liquidity;

        if (pool.totalLiquidity == 0) {
            liquidity = Math.sqrt(amount0 * amount1);
            require(liquidity > 0, "Insufficient liquidity minted");
        } else {
            uint256 liquidity0 = (amount0 * pool.totalLiquidity) / pool.token0Balance;
            uint256 liquidity1 = (amount1 * pool.totalLiquidity) / pool.token1Balance;
            liquidity = Math.min(liquidity0, liquidity1);
            require(liquidity > 0, "Insufficient liquidity minted");
        }

        IERC20(token0).safeTransferFrom(msg.sender, address(this), amount0);
        IERC20(token1).safeTransferFrom(msg.sender, address(this), amount1);

        pool.token0Balance += amount0;
        pool.token1Balance += amount1;
        pool.totalLiquidity += liquidity;
        ammStorage.setLiquidityPool(token0, token1, pool);

        uint256 userLiquidityBalance = ammStorage.userLiquidity(msg.sender, token0, token1);
        ammStorage.setUserLiquidity(msg.sender, token0, token1, userLiquidityBalance + liquidity);

        emit LiquidityAdded(
            msg.sender,
            token0,
            token1,
            amount0,
            amount1,
            liquidity
        );
    }

    function removeLiquidity(
        address token0,
        address token1,
        uint256 liquidity
    ) external nonReentrant whenNotPaused {
        require(liquidity > 0, "Insufficient liquidity burned");
        AMMStorage.LiquidityPool memory pool = ammStorage.getLiquidityPool(token0, token1);
        require(pool.totalLiquidity > 0, "Pool does not exist");

        uint256 userLiquidityBalance = ammStorage.userLiquidity(msg.sender, token0, token1);
        require(userLiquidityBalance >= liquidity, "Insufficient user liquidity");

        uint256 amount0 = (liquidity * pool.token0Balance) / pool.totalLiquidity;
        uint256 amount1 = (liquidity * pool.token1Balance) / pool.totalLiquidity;

        pool.token0Balance -= amount0;
        pool.token1Balance -= amount1;
        pool.totalLiquidity -= liquidity;
        ammStorage.setLiquidityPool(token0, token1, pool);
        ammStorage.setUserLiquidity(msg.sender, token0, token1, userLiquidityBalance - liquidity);

        IERC20(token0).safeTransfer(msg.sender, amount0);
        IERC20(token1).safeTransfer(msg.sender, amount1);

        emit LiquidityRemoved(
            msg.sender,
            token0,
            token1,
            amount0,
            amount1,
            liquidity
        );
    }

    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external nonReentrant whenNotPaused {
        require(tokenIn != tokenOut, "Identical tokens");
        require(amountIn > 0, "Amount must be positive");

        AMMStorage.LiquidityPool memory pool = ammStorage.getLiquidityPool(tokenIn, tokenOut);
        require(pool.totalLiquidity > 0, "Pool does not exist");

        uint256 amountInWithFee = (amountIn * (FEE_DENOMINATOR - FEE_PERCENTAGE)) / FEE_DENOMINATOR;
        uint256 amountOut;
        unchecked {
            amountOut = (pool.token1Balance * amountInWithFee) / (pool.token0Balance + amountInWithFee);
        }

        require(amountOut > 0 && amountOut < pool.token1Balance, "Invalid output amount");

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenOut).safeTransfer(msg.sender, amountOut);

        unchecked {
            pool.token0Balance += amountIn;
            pool.token1Balance -= amountOut;
        }
        ammStorage.setLiquidityPool(tokenIn, tokenOut, pool);

        emit Swap(msg.sender, tokenIn, tokenOut, amountIn, amountOut);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(UPGRADER_ROLE) {}

    function setFeePercentage(uint256 newFeePercentage) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newFeePercentage <= FEE_DENOMINATOR, "Fee percentage too high");
        FEE_PERCENTAGE = newFeePercentage;
        emit FeePercentageChanged(newFeePercentage);
    }
}
