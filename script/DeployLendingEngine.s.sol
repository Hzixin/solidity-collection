// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {LendingEngine} from "../src/LendingEngine.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockV3Aggregator} from "../src/mocks/MockV3Aggregator.sol";

contract DeployLendingEngine is Script {
    uint8 private constant FEED_DECIMALS = 8;
    int256 private constant ETH_PRICE = 2_000e8;
    int256 private constant BTC_PRICE = 30_000e8;
    uint256 private constant MOCK_SUPPLY = 1_000_000 ether;

    function run() external returns (LendingEngine engine, MockERC20 weth, MockERC20 wbtc) {
        vm.startBroadcast();

        weth = new MockERC20("Wrapped Ether", "WETH", 18, MOCK_SUPPLY, msg.sender);
        wbtc = new MockERC20("Wrapped Bitcoin", "WBTC", 18, MOCK_SUPPLY, msg.sender);

        MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(FEED_DECIMALS, ETH_PRICE);
        MockV3Aggregator btcUsdPriceFeed = new MockV3Aggregator(FEED_DECIMALS, BTC_PRICE);

        address[] memory collateralTokens = new address[](2);
        collateralTokens[0] = address(weth);
        collateralTokens[1] = address(wbtc);

        address[] memory priceFeeds = new address[](2);
        priceFeeds[0] = address(ethUsdPriceFeed);
        priceFeeds[1] = address(btcUsdPriceFeed);

        engine = new LendingEngine(collateralTokens, priceFeeds);

        vm.stopBroadcast();
    }
}
