// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {YieldVault} from "../src/YieldVault.sol";

contract DeployYieldVault is Script {
    uint256 private constant MOCK_SUPPLY = 1_000_000 ether;
    uint256 private constant DEPOSIT_CAP = 500_000 ether;
    uint256 private constant COOLDOWN = 1 days;

    function run() external returns (MockERC20 assetToken, YieldVault vault) {
        vm.startBroadcast();

        assetToken = new MockERC20("Vault Asset", "vASSET", 18, MOCK_SUPPLY, msg.sender);
        vault = new YieldVault(address(assetToken), DEPOSIT_CAP, COOLDOWN);

        vm.stopBroadcast();
    }
}
