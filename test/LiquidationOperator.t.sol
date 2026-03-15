// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {DecentralizedStablecoin} from "../src/DecentralizedStablecoin.sol";
import {LendingEngine} from "../src/LendingEngine.sol";
import {LiquidationOperator} from "../src/LiquidationOperator.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockFlashLender} from "../src/mocks/MockFlashLender.sol";
import {MockV3Aggregator} from "../src/mocks/MockV3Aggregator.sol";
import {SimpleAMM} from "../src/SimpleAMM.sol";

contract LiquidationOperatorTest is Test {
    uint256 private constant STARTING_BALANCE = 1_000 ether;
    uint256 private constant ETH_PRICE = 2_000e8;

    LendingEngine private engine;
    DecentralizedStablecoin private dsc;
    MockERC20 private weth;
    MockV3Aggregator private ethUsdPriceFeed;
    SimpleAMM private amm;
    MockFlashLender private lender;
    LiquidationOperator private operator;

    address private immutable USER = makeAddr("user");
    address private immutable LP = makeAddr("lp");
    address private immutable BOT_OWNER = makeAddr("bot-owner");

    function setUp() public {
        weth = new MockERC20("Wrapped Ether", "WETH", 18, 0, address(this));
        // Casting is safe because this is a bounded positive mock price.
        // forge-lint: disable-next-line(unsafe-typecast)
        ethUsdPriceFeed = new MockV3Aggregator(8, int256(ETH_PRICE));

        address[] memory collateralTokens = new address[](1);
        collateralTokens[0] = address(weth);

        address[] memory priceFeeds = new address[](1);
        priceFeeds[0] = address(ethUsdPriceFeed);

        engine = new LendingEngine(collateralTokens, priceFeeds);
        dsc = DecentralizedStablecoin(engine.getDscAddress());
        amm = new SimpleAMM(address(dsc), address(weth));
        lender = new MockFlashLender(address(dsc), 5);

        vm.prank(BOT_OWNER);
        operator = new LiquidationOperator(address(engine), address(amm), address(dsc), address(weth));

        weth.mint(USER, STARTING_BALANCE);
        weth.mint(LP, STARTING_BALANCE);

        vm.startPrank(USER);
        weth.approve(address(engine), type(uint256).max);
        dsc.approve(address(engine), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(LP);
        weth.approve(address(engine), type(uint256).max);
        dsc.approve(address(engine), type(uint256).max);
        dsc.approve(address(amm), type(uint256).max);
        weth.approve(address(amm), type(uint256).max);
        vm.stopPrank();
    }

    function testFlashLoanLiquidationProducesProfit() public {
        vm.startPrank(LP);
        engine.depositCollateralAndMintDsc(address(weth), 200 ether, 100_000 ether);
        assertTrue(dsc.transfer(address(lender), 5_000 ether));
        amm.addLiquidity(90_000 ether, 100 ether);
        vm.stopPrank();

        vm.startPrank(USER);
        engine.depositCollateralAndMintDsc(address(weth), 10 ether, 7_000 ether);
        vm.stopPrank();

        ethUsdPriceFeed.updateAnswer(900e8);

        uint256 lenderBalanceBefore = dsc.balanceOf(address(lender));
        uint256 botBalanceBefore = dsc.balanceOf(BOT_OWNER);

        vm.prank(BOT_OWNER);
        operator.executeLiquidation(address(lender), USER, 2_000 ether, 2_050 ether);

        uint256 lenderBalanceAfter = dsc.balanceOf(address(lender));
        uint256 botBalanceAfter = dsc.balanceOf(BOT_OWNER);
        (uint256 minted,) = engine.getAccountInformation(USER);

        assertEq(minted, 5_000 ether);
        assertGt(engine.getHealthFactor(USER), 1 ether);
        assertEq(lenderBalanceAfter, lenderBalanceBefore + 1 ether);
        assertGt(botBalanceAfter, botBalanceBefore);
    }
}
