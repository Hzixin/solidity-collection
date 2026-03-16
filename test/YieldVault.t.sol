// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {YieldVault} from "../src/YieldVault.sol";

contract YieldVaultTest is Test {
    uint256 private constant STARTING_BALANCE = 1_000_000 ether;
    uint256 private constant DEPOSIT_CAP = 500_000 ether;
    uint256 private constant COOLDOWN = 1 days;

    MockERC20 private assetToken;
    YieldVault private vault;

    address private immutable ALICE = makeAddr("alice");
    address private immutable BOB = makeAddr("bob");

    function setUp() public {
        assetToken = new MockERC20("Vault Asset", "vASSET", 18, 0, address(this));
        vault = new YieldVault(address(assetToken), DEPOSIT_CAP, COOLDOWN);

        assetToken.mint(ALICE, STARTING_BALANCE);
        assetToken.mint(BOB, STARTING_BALANCE);
        assetToken.mint(address(this), STARTING_BALANCE);

        vm.prank(ALICE);
        assetToken.approve(address(vault), type(uint256).max);

        vm.prank(BOB);
        assetToken.approve(address(vault), type(uint256).max);

        assetToken.approve(address(vault), type(uint256).max);
    }

    function testInitialDepositMintsSharesOneToOne() public {
        vm.prank(ALICE);
        uint256 shares = vault.deposit(100 ether, ALICE);

        assertEq(shares, 100 ether);
        assertEq(vault.balanceOf(ALICE), 100 ether);
        assertEq(vault.totalAssets(), 100 ether);
    }

    function testHarvestIncreasesShareValue() public {
        vm.prank(ALICE);
        vault.deposit(100 ether, ALICE);

        vault.harvest(20 ether);

        vm.warp(block.timestamp + COOLDOWN + 1);

        vm.prank(ALICE);
        uint256 assetsOut = vault.redeem(100 ether, ALICE, ALICE);

        assertApproxEqAbs(assetsOut, 120 ether, 1);
        assertApproxEqAbs(assetToken.balanceOf(ALICE), STARTING_BALANCE + 20 ether, 1);
    }

    function testRedeemRevertsBeforeCooldownEnds() public {
        vm.prank(ALICE);
        vault.deposit(100 ether, ALICE);

        vm.prank(ALICE);
        vm.expectRevert(YieldVault.YieldVault__CooldownNotFinished.selector);
        vault.redeem(10 ether, ALICE, ALICE);
    }

    function testDepositCapPreventsExcessAssets() public {
        vm.prank(ALICE);
        vault.deposit(DEPOSIT_CAP, ALICE);

        vm.prank(BOB);
        vm.expectRevert(YieldVault.YieldVault__DepositCapExceeded.selector);
        vault.deposit(1 ether, BOB);
    }
}
