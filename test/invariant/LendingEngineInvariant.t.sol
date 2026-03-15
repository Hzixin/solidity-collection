// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test} from "forge-std/Test.sol";
import {DecentralizedStablecoin} from "../../src/DecentralizedStablecoin.sol";
import {LendingEngine} from "../../src/LendingEngine.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockV3Aggregator} from "../../src/mocks/MockV3Aggregator.sol";
import {LendingEngineHandler} from "./LendingEngineHandler.t.sol";

contract LendingEngineInvariantTest is StdInvariant, Test {
    uint256 private constant ETH_PRICE = 2_000e8;
    uint256 private constant STARTING_BALANCE = 1_000 ether;

    LendingEngine private engine;
    DecentralizedStablecoin private dsc;
    MockERC20 private weth;
    LendingEngineHandler private handler;

    address[] private actors;

    function setUp() public {
        weth = new MockERC20("Wrapped Ether", "WETH", 18, 0, address(this));
        // Casting is safe because this is a bounded positive mock price.
        // forge-lint: disable-next-line(unsafe-typecast)
        MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(8, int256(ETH_PRICE));

        address[] memory collateralTokens = new address[](1);
        collateralTokens[0] = address(weth);

        address[] memory priceFeeds = new address[](1);
        priceFeeds[0] = address(ethUsdPriceFeed);

        engine = new LendingEngine(collateralTokens, priceFeeds);
        dsc = DecentralizedStablecoin(engine.getDscAddress());

        actors.push(makeAddr("actor-1"));
        actors.push(makeAddr("actor-2"));
        actors.push(makeAddr("actor-3"));

        for (uint256 i = 0; i < actors.length; i++) {
            weth.mint(actors[i], STARTING_BALANCE);
            vm.startPrank(actors[i]);
            weth.approve(address(engine), type(uint256).max);
            dsc.approve(address(engine), type(uint256).max);
            vm.stopPrank();
        }

        handler = new LendingEngineHandler(engine, dsc, weth, actors);

        targetContract(address(handler));
    }

    function invariant_protocolMaintainsHealthyPositions() public view {
        for (uint256 i = 0; i < actors.length; i++) {
            (uint256 minted,) = engine.getAccountInformation(actors[i]);
            if (minted > 0) {
                assertGe(engine.getHealthFactor(actors[i]), engine.getMinHealthFactor());
            }
        }
    }

    function invariant_totalSupplyMatchesTrackedDebt() public view {
        uint256 totalMinted;
        for (uint256 i = 0; i < actors.length; i++) {
            (uint256 minted,) = engine.getAccountInformation(actors[i]);
            totalMinted += minted;
        }

        assertEq(dsc.totalSupply(), totalMinted);
    }
}
