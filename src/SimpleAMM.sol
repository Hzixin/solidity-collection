// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract SimpleAMM is ERC20, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error SimpleAMM__InvalidToken();
    error SimpleAMM__AmountMustBeMoreThanZero();
    error SimpleAMM__InsufficientOutputAmount();
    error SimpleAMM__InsufficientLiquidityMinted();
    error SimpleAMM__InsufficientLiquidityBurned();

    uint256 private constant MINIMUM_LIQUIDITY = 1e3;
    uint256 private constant FEE_NUMERATOR = 997;
    uint256 private constant FEE_DENOMINATOR = 1000;
    address private constant DEAD_ADDRESS = address(0xdead);

    IERC20 public immutable token0;
    IERC20 public immutable token1;

    uint256 private s_reserve0;
    uint256 private s_reserve1;

    event LiquidityAdded(address indexed provider, uint256 amount0, uint256 amount1, uint256 liquidityMinted);
    event LiquidityRemoved(address indexed provider, uint256 amount0, uint256 amount1, uint256 liquidityBurned);
    event Swap(
        address indexed trader, address indexed tokenIn, uint256 amountIn, address indexed tokenOut, uint256 amountOut
    );

    constructor(address token0Address, address token1Address) ERC20("Portfolio LP Token", "PLP") {
        token0 = IERC20(token0Address);
        token1 = IERC20(token1Address);
    }

    function addLiquidity(uint256 amount0Desired, uint256 amount1Desired)
        external
        nonReentrant
        returns (uint256 liquidity)
    {
        if (amount0Desired == 0 || amount1Desired == 0) revert SimpleAMM__AmountMustBeMoreThanZero();

        uint256 reserve0 = s_reserve0;
        uint256 reserve1 = s_reserve1;

        token0.safeTransferFrom(msg.sender, address(this), amount0Desired);
        token1.safeTransferFrom(msg.sender, address(this), amount1Desired);

        if (totalSupply() == 0) {
            liquidity = Math.sqrt(amount0Desired * amount1Desired) - MINIMUM_LIQUIDITY;
            _mint(DEAD_ADDRESS, MINIMUM_LIQUIDITY);
        } else {
            uint256 liquidityFromToken0 = (amount0Desired * totalSupply()) / reserve0;
            uint256 liquidityFromToken1 = (amount1Desired * totalSupply()) / reserve1;
            liquidity = Math.min(liquidityFromToken0, liquidityFromToken1);
        }

        if (liquidity == 0) revert SimpleAMM__InsufficientLiquidityMinted();

        _mint(msg.sender, liquidity);
        _sync();

        emit LiquidityAdded(msg.sender, amount0Desired, amount1Desired, liquidity);
    }

    function removeLiquidity(uint256 liquidity) external nonReentrant returns (uint256 amount0, uint256 amount1) {
        if (liquidity == 0) revert SimpleAMM__AmountMustBeMoreThanZero();

        uint256 supply = totalSupply();
        amount0 = (liquidity * s_reserve0) / supply;
        amount1 = (liquidity * s_reserve1) / supply;

        if (amount0 == 0 || amount1 == 0) revert SimpleAMM__InsufficientLiquidityBurned();

        _burn(msg.sender, liquidity);
        token0.safeTransfer(msg.sender, amount0);
        token1.safeTransfer(msg.sender, amount1);
        _sync();

        emit LiquidityRemoved(msg.sender, amount0, amount1, liquidity);
    }

    function swap(address tokenIn, uint256 amountIn, uint256 minAmountOut)
        external
        nonReentrant
        returns (uint256 amountOut)
    {
        if (amountIn == 0) revert SimpleAMM__AmountMustBeMoreThanZero();

        bool isToken0In = tokenIn == address(token0);
        bool isToken1In = tokenIn == address(token1);
        if (!isToken0In && !isToken1In) revert SimpleAMM__InvalidToken();

        IERC20 inputToken = isToken0In ? token0 : token1;
        IERC20 outputToken = isToken0In ? token1 : token0;
        uint256 reserveIn = isToken0In ? s_reserve0 : s_reserve1;
        uint256 reserveOut = isToken0In ? s_reserve1 : s_reserve0;

        amountOut = getAmountOut(amountIn, reserveIn, reserveOut);
        if (amountOut < minAmountOut) revert SimpleAMM__InsufficientOutputAmount();

        inputToken.safeTransferFrom(msg.sender, address(this), amountIn);
        outputToken.safeTransfer(msg.sender, amountOut);
        _sync();

        emit Swap(msg.sender, address(inputToken), amountIn, address(outputToken), amountOut);
    }

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        public
        pure
        returns (uint256 amountOut)
    {
        if (amountIn == 0 || reserveIn == 0 || reserveOut == 0) revert SimpleAMM__AmountMustBeMoreThanZero();

        uint256 amountInWithFee = amountIn * FEE_NUMERATOR;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * FEE_DENOMINATOR) + amountInWithFee;
        amountOut = numerator / denominator;
    }

    function getReserves() external view returns (uint256 reserve0, uint256 reserve1) {
        return (s_reserve0, s_reserve1);
    }

    function _sync() private {
        s_reserve0 = token0.balanceOf(address(this));
        s_reserve1 = token1.balanceOf(address(this));
    }
}
