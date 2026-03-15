// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {SimpleAMM} from "../src/SimpleAMM.sol";

contract SimpleAMMTest is Test {
    uint256 private constant STARTING_BALANCE = 1_000_000 ether;

    MockERC20 private tokenA;
    MockERC20 private tokenB;
    SimpleAMM private amm;

    address private immutable LP = makeAddr("lp");
    address private immutable TRADER = makeAddr("trader");

    function setUp() public {
        tokenA = new MockERC20("Token A", "TKA", 18, 0, address(this));
        tokenB = new MockERC20("Token B", "TKB", 18, 0, address(this));
        amm = new SimpleAMM(address(tokenA), address(tokenB));

        tokenA.mint(LP, STARTING_BALANCE);
        tokenB.mint(LP, STARTING_BALANCE);
        tokenA.mint(TRADER, STARTING_BALANCE);
        tokenB.mint(TRADER, STARTING_BALANCE);

        vm.startPrank(LP);
        tokenA.approve(address(amm), type(uint256).max);
        tokenB.approve(address(amm), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(TRADER);
        tokenA.approve(address(amm), type(uint256).max);
        tokenB.approve(address(amm), type(uint256).max);
        vm.stopPrank();
    }

    function testAddLiquidityMintsLpTokens() public {
        vm.prank(LP);
        uint256 liquidity = amm.addLiquidity(100_000 ether, 100_000 ether);

        (uint256 reserve0, uint256 reserve1) = amm.getReserves();
        assertEq(reserve0, 100_000 ether);
        assertEq(reserve1, 100_000 ether);
        assertGt(liquidity, 0);
        assertEq(amm.balanceOf(LP), liquidity);
    }

    function testSwapUsesConstantProductFormula() public {
        vm.prank(LP);
        amm.addLiquidity(100_000 ether, 100_000 ether);

        uint256 quotedAmountOut = amm.getAmountOut(10_000 ether, 100_000 ether, 100_000 ether);

        vm.prank(TRADER);
        uint256 amountOut = amm.swap(address(tokenA), 10_000 ether, 9_000 ether);

        (uint256 reserve0, uint256 reserve1) = amm.getReserves();
        assertEq(amountOut, quotedAmountOut);
        assertEq(tokenB.balanceOf(TRADER), STARTING_BALANCE + amountOut);
        assertEq(reserve0, 110_000 ether);
        assertEq(reserve1, 100_000 ether - amountOut);
    }

    function testRemoveLiquidityReturnsUnderlyingAssets() public {
        vm.startPrank(LP);
        uint256 liquidity = amm.addLiquidity(50_000 ether, 50_000 ether);
        (uint256 amount0, uint256 amount1) = amm.removeLiquidity(liquidity / 2);
        vm.stopPrank();

        assertGt(amount0, 0);
        assertGt(amount1, 0);
        assertGt(tokenA.balanceOf(LP), STARTING_BALANCE - 50_000 ether);
        assertGt(tokenB.balanceOf(LP), STARTING_BALANCE - 50_000 ether);
    }

    function testRevertsOnInvalidSwapToken() public {
        MockERC20 fakeToken = new MockERC20("Fake", "FAKE", 18, 100 ether, TRADER);

        vm.prank(LP);
        amm.addLiquidity(10_000 ether, 10_000 ether);

        vm.startPrank(TRADER);
        fakeToken.approve(address(amm), type(uint256).max);
        vm.expectRevert(SimpleAMM.SimpleAMM__InvalidToken.selector);
        amm.swap(address(fakeToken), 1 ether, 0);
        vm.stopPrank();
    }
}
