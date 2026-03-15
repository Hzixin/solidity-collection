// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {StakingRewards} from "../src/StakingRewards.sol";

contract StakingRewardsTest is Test {
    uint256 private constant STAKE_AMOUNT = 100 ether;
    uint256 private constant REWARD_AMOUNT = 700 ether;

    MockERC20 private stakingToken;
    MockERC20 private rewardsToken;
    StakingRewards private stakingRewards;

    address private immutable ALICE = makeAddr("alice");
    address private immutable BOB = makeAddr("bob");

    function setUp() public {
        stakingToken = new MockERC20("Stake Token", "STK", 18, 0, address(this));
        rewardsToken = new MockERC20("Reward Token", "RWD", 18, 0, address(this));
        stakingRewards = new StakingRewards(address(stakingToken), address(rewardsToken));

        stakingToken.mint(ALICE, 1_000 ether);
        stakingToken.mint(BOB, 1_000 ether);
        rewardsToken.mint(address(this), REWARD_AMOUNT);
        assertTrue(rewardsToken.transfer(address(stakingRewards), REWARD_AMOUNT));

        vm.startPrank(ALICE);
        stakingToken.approve(address(stakingRewards), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(BOB);
        stakingToken.approve(address(stakingRewards), type(uint256).max);
        vm.stopPrank();

        stakingRewards.notifyRewardAmount(REWARD_AMOUNT);
    }

    function testSingleStakerEarnsFullRewardStream() public {
        vm.prank(ALICE);
        stakingRewards.stake(STAKE_AMOUNT);

        vm.warp(block.timestamp + 7 days);

        uint256 earned = stakingRewards.earned(ALICE);
        assertApproxEqAbs(earned, REWARD_AMOUNT, 1e14);

        vm.prank(ALICE);
        stakingRewards.getReward();

        assertApproxEqAbs(rewardsToken.balanceOf(ALICE), REWARD_AMOUNT, 1e14);
    }

    function testRewardsSplitProportionallyBetweenStakers() public {
        vm.prank(ALICE);
        stakingRewards.stake(STAKE_AMOUNT);

        vm.warp(block.timestamp + 3 days);

        vm.prank(BOB);
        stakingRewards.stake(STAKE_AMOUNT);

        vm.warp(block.timestamp + 4 days);

        uint256 aliceEarned = stakingRewards.earned(ALICE);
        uint256 bobEarned = stakingRewards.earned(BOB);

        assertGt(aliceEarned, bobEarned);
        assertApproxEqAbs(aliceEarned + bobEarned, REWARD_AMOUNT, 1e15);
    }

    function testExitWithdrawsStakeAndRewards() public {
        vm.prank(ALICE);
        stakingRewards.stake(STAKE_AMOUNT);

        vm.warp(block.timestamp + 7 days);

        vm.prank(ALICE);
        stakingRewards.exit();

        assertEq(stakingToken.balanceOf(ALICE), 1_000 ether);
        assertApproxEqAbs(rewardsToken.balanceOf(ALICE), REWARD_AMOUNT, 1e14);
        assertEq(stakingRewards.balanceOf(ALICE), 0);
    }
}
