// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {DeployLendingEngine} from "./DeployLendingEngine.s.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {SimpleAMM} from "../src/SimpleAMM.sol";
import {StakingRewards} from "../src/StakingRewards.sol";

contract DeployDefiPortfolio is Script {
    uint256 private constant MOCK_SUPPLY = 1_000_000 ether;
    uint256 private constant REWARD_SUPPLY = 500_000 ether;

    function run()
        external
        returns (
            MockERC20 ammTokenA,
            MockERC20 ammTokenB,
            MockERC20 stakingToken,
            MockERC20 rewardsToken,
            SimpleAMM amm,
            StakingRewards stakingRewards
        )
    {
        vm.startBroadcast();

        DeployLendingEngine lendingDeployer = new DeployLendingEngine();
        lendingDeployer.run();

        ammTokenA = new MockERC20("Portfolio USD", "pUSD", 18, MOCK_SUPPLY, msg.sender);
        ammTokenB = new MockERC20("Portfolio Ether", "pETH", 18, MOCK_SUPPLY, msg.sender);
        stakingToken = new MockERC20("Governance Token", "GOV", 18, MOCK_SUPPLY, msg.sender);
        rewardsToken = new MockERC20("Reward Token", "RWD", 18, REWARD_SUPPLY, msg.sender);

        amm = new SimpleAMM(address(ammTokenA), address(ammTokenB));
        stakingRewards = new StakingRewards(address(stakingToken), address(rewardsToken));

        require(rewardsToken.transfer(address(stakingRewards), REWARD_SUPPLY), "reward transfer failed");

        vm.stopBroadcast();
    }
}
