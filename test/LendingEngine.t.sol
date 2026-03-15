// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {DecentralizedStablecoin} from "../src/DecentralizedStablecoin.sol";
import {LendingEngine} from "../src/LendingEngine.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockV3Aggregator} from "../src/mocks/MockV3Aggregator.sol";

contract LendingEngineTest is Test {
    uint256 private constant COLLATERAL_AMOUNT = 10 ether;
    uint256 private constant STARTING_BALANCE = 100 ether;
    uint256 private constant ETH_PRICE = 2_000e8;
    uint256 private constant BTC_PRICE = 30_000e8;

    LendingEngine private engine;
    DecentralizedStablecoin private dsc;
    MockERC20 private weth;
    MockERC20 private wbtc;
    MockV3Aggregator private ethUsdPriceFeed;
    MockV3Aggregator private btcUsdPriceFeed;

    address private immutable USER = makeAddr("user");
    address private immutable LIQUIDATOR = makeAddr("liquidator");

    function setUp() public {
        weth = new MockERC20("Wrapped Ether", "WETH", 18, 0, address(this));
        wbtc = new MockERC20("Wrapped Bitcoin", "WBTC", 18, 0, address(this));
        // Casting is safe because these constants are bounded positive mock prices.
        // forge-lint: disable-next-line(unsafe-typecast)
        ethUsdPriceFeed = new MockV3Aggregator(8, int256(ETH_PRICE));
        // Casting is safe because these constants are bounded positive mock prices.
        // forge-lint: disable-next-line(unsafe-typecast)
        btcUsdPriceFeed = new MockV3Aggregator(8, int256(BTC_PRICE));

        address[] memory collateralTokens = new address[](2);
        collateralTokens[0] = address(weth);
        collateralTokens[1] = address(wbtc);

        address[] memory priceFeeds = new address[](2);
        priceFeeds[0] = address(ethUsdPriceFeed);
        priceFeeds[1] = address(btcUsdPriceFeed);

        engine = new LendingEngine(collateralTokens, priceFeeds);
        dsc = DecentralizedStablecoin(engine.getDscAddress());

        weth.mint(USER, STARTING_BALANCE);
        weth.mint(LIQUIDATOR, STARTING_BALANCE);
        wbtc.mint(USER, STARTING_BALANCE);

        vm.startPrank(USER);
        weth.approve(address(engine), type(uint256).max);
        wbtc.approve(address(engine), type(uint256).max);
        dsc.approve(address(engine), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(LIQUIDATOR);
        weth.approve(address(engine), type(uint256).max);
        dsc.approve(address(engine), type(uint256).max);
        vm.stopPrank();
    }

    function testConstructorStoresCollateralConfiguration() public view {
        address[] memory collateralTokens = engine.getCollateralTokens();
        assertEq(collateralTokens.length, 2);
        assertEq(collateralTokens[0], address(weth));
        assertEq(engine.getCollateralTokenPriceFeed(address(weth)), address(ethUsdPriceFeed));
    }

    function testCanDepositCollateralAndMintDsc() public {
        vm.startPrank(USER);
        engine.depositCollateralAndMintDsc(address(weth), COLLATERAL_AMOUNT, 7_500 ether);
        vm.stopPrank();

        (uint256 minted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);
        assertEq(minted, 7_500 ether);
        assertEq(collateralValueInUsd, 20_000 ether);
        assertEq(dsc.balanceOf(USER), 7_500 ether);
    }

    function testRevertsWhenMintBreaksHealthFactor() public {
        vm.startPrank(USER);
        engine.depositCollateral(address(weth), COLLATERAL_AMOUNT);
        vm.expectRevert();
        engine.mintDsc(15_001 ether);
        vm.stopPrank();
    }

    function testCanBurnDscAndRedeemCollateral() public {
        vm.startPrank(USER);
        engine.depositCollateralAndMintDsc(address(weth), COLLATERAL_AMOUNT, 5_000 ether);
        engine.burnDsc(2_000 ether);
        engine.redeemCollateral(address(weth), 1 ether);
        vm.stopPrank();

        (uint256 minted,) = engine.getAccountInformation(USER);
        assertEq(minted, 3_000 ether);
        assertEq(engine.getHealthFactor(USER), 4.5 ether);
        assertEq(weth.balanceOf(USER), STARTING_BALANCE - COLLATERAL_AMOUNT + 1 ether);
    }

    function testGetUsdValueUsesConfiguredFeed() public view {
        uint256 usdValue = engine.getUsdValue(address(weth), 15 ether);
        assertEq(usdValue, 30_000 ether);
    }

    function testLiquidationTransfersBonusCollateralToLiquidator() public {
        vm.startPrank(USER);
        engine.depositCollateralAndMintDsc(address(weth), COLLATERAL_AMOUNT, 7_000 ether);
        vm.stopPrank();

        vm.startPrank(LIQUIDATOR);
        engine.depositCollateralAndMintDsc(address(weth), 10 ether, 5_000 ether);
        vm.stopPrank();

        ethUsdPriceFeed.updateAnswer(900e8);

        vm.startPrank(LIQUIDATOR);
        engine.liquidate(address(weth), USER, 2_000 ether);
        vm.stopPrank();

        (uint256 minted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);
        assertEq(minted, 5_000 ether);
        assertApproxEqAbs(collateralValueInUsd, 6_800 ether, 1_000);
        assertEq(engine.getCollateralBalanceOfUser(LIQUIDATOR, address(weth)), 10 ether);
        assertEq(weth.balanceOf(LIQUIDATOR), 92_444_444_444_444_444_444);
        assertGt(engine.getHealthFactor(USER), 1 ether);
    }

    function testLiquidationRevertsIfHealthFactorIsHealthy() public {
        vm.startPrank(USER);
        engine.depositCollateralAndMintDsc(address(weth), COLLATERAL_AMOUNT, 5_000 ether);
        vm.stopPrank();

        vm.startPrank(LIQUIDATOR);
        engine.depositCollateralAndMintDsc(address(weth), 10 ether, 5_000 ether);
        vm.expectRevert(LendingEngine.LendingEngine__HealthFactorOk.selector);
        engine.liquidate(address(weth), USER, 1_000 ether);
        vm.stopPrank();
    }

    function testFuzzDepositTracksUserCollateral(uint96 amount) public {
        uint256 collateral = bound(uint256(amount), 1 ether, STARTING_BALANCE);

        vm.startPrank(USER);
        engine.depositCollateral(address(wbtc), collateral);
        vm.stopPrank();

        assertEq(engine.getCollateralBalanceOfUser(USER, address(wbtc)), collateral);
    }
}
