// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {DecentralizedStablecoin} from "../../src/DecentralizedStablecoin.sol";
import {LendingEngine} from "../../src/LendingEngine.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";

contract LendingEngineHandler is Test {
    uint256 private constant MAX_DEPOSIT = 100 ether;

    LendingEngine public immutable engine;
    DecentralizedStablecoin public immutable dsc;
    MockERC20 public immutable weth;
    address[] public actors;

    constructor(LendingEngine engine_, DecentralizedStablecoin dsc_, MockERC20 weth_, address[] memory actors_) {
        engine = engine_;
        dsc = dsc_;
        weth = weth_;
        actors = actors_;
    }

    function depositCollateral(uint256 actorSeed, uint256 amount) external {
        address actor = actors[actorSeed % actors.length];
        uint256 depositAmount = bound(amount, 1 ether, MAX_DEPOSIT);

        vm.startPrank(actor);
        engine.depositCollateral(address(weth), depositAmount);
        vm.stopPrank();
    }

    function mintDsc(uint256 actorSeed, uint256 amount) external {
        address actor = actors[actorSeed % actors.length];
        (uint256 minted, uint256 collateralValueInUsd) = engine.getAccountInformation(actor);

        uint256 maxMintable = (collateralValueInUsd * engine.getLiquidationThreshold()) / 100;
        if (maxMintable <= minted) return;

        uint256 mintAmount = bound(amount, 1, maxMintable - minted);
        vm.prank(actor);
        engine.mintDsc(mintAmount);
    }

    function burnDsc(uint256 actorSeed, uint256 amount) external {
        address actor = actors[actorSeed % actors.length];
        uint256 balance = dsc.balanceOf(actor);
        if (balance == 0) return;

        uint256 burnAmount = bound(amount, 1, balance);
        vm.prank(actor);
        engine.burnDsc(burnAmount);
    }

    function redeemCollateral(uint256 actorSeed, uint256 amount) external {
        address actor = actors[actorSeed % actors.length];
        uint256 collateralBalance = engine.getCollateralBalanceOfUser(actor, address(weth));
        if (collateralBalance == 0) return;

        (uint256 minted, uint256 collateralValueInUsd) = engine.getAccountInformation(actor);
        uint256 maxRedeemAmount = collateralBalance;

        if (minted > 0) {
            uint256 requiredCollateralUsd = (minted * 100) / engine.getLiquidationThreshold();
            if (collateralValueInUsd <= requiredCollateralUsd) return;

            uint256 excessCollateralUsd = collateralValueInUsd - requiredCollateralUsd;
            uint256 redeemableByHealthFactor = engine.getTokenAmountFromUsd(address(weth), excessCollateralUsd);
            if (redeemableByHealthFactor == 0) return;
            maxRedeemAmount =
                redeemableByHealthFactor < collateralBalance ? redeemableByHealthFactor : collateralBalance;
        }

        uint256 redeemAmount = bound(amount, 1, maxRedeemAmount);
        vm.prank(actor);
        engine.redeemCollateral(address(weth), redeemAmount);
    }

    function actorsLength() external view returns (uint256) {
        return actors.length;
    }
}
