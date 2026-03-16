// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract YieldVault is ERC4626, Ownable {
    using SafeERC20 for IERC20;

    error YieldVault__AmountMustBeMoreThanZero();
    error YieldVault__DepositCapExceeded();
    error YieldVault__CooldownNotFinished();

    uint256 public depositCap;
    uint256 public withdrawalCooldown;

    mapping(address account => uint256) public lastDepositTimestamp;

    event DepositCapUpdated(uint256 newDepositCap);
    event WithdrawalCooldownUpdated(uint256 newWithdrawalCooldown);
    event Harvest(uint256 profitAdded);

    constructor(address asset_, uint256 depositCap_, uint256 withdrawalCooldown_)
        ERC20("Portfolio Yield Vault Share", "pyvSHARE")
        ERC4626(IERC20(asset_))
        Ownable(msg.sender)
    {
        depositCap = depositCap_;
        withdrawalCooldown = withdrawalCooldown_;
    }

    function setDepositCap(uint256 newDepositCap) external onlyOwner {
        depositCap = newDepositCap;
        emit DepositCapUpdated(newDepositCap);
    }

    function setWithdrawalCooldown(uint256 newWithdrawalCooldown) external onlyOwner {
        withdrawalCooldown = newWithdrawalCooldown;
        emit WithdrawalCooldownUpdated(newWithdrawalCooldown);
    }

    function harvest(uint256 profit) external onlyOwner {
        if (profit == 0) revert YieldVault__AmountMustBeMoreThanZero();

        IERC20(asset()).safeTransferFrom(msg.sender, address(this), profit);
        emit Harvest(profit);
    }

    function deposit(uint256 assets, address receiver) public override returns (uint256 shares) {
        _checkDepositLimit(assets);
        shares = super.deposit(assets, receiver);
        lastDepositTimestamp[receiver] = block.timestamp;
    }

    function mint(uint256 shares, address receiver) public override returns (uint256 assets) {
        assets = previewMint(shares);
        _checkDepositLimit(assets);
        assets = super.mint(shares, receiver);
        lastDepositTimestamp[receiver] = block.timestamp;
    }

    function withdraw(uint256 assets, address receiver, address owner) public override returns (uint256 shares) {
        _checkCooldown(owner);
        return super.withdraw(assets, receiver, owner);
    }

    function redeem(uint256 shares, address receiver, address owner) public override returns (uint256 assets) {
        _checkCooldown(owner);
        return super.redeem(shares, receiver, owner);
    }

    function _checkDepositLimit(uint256 assets) private view {
        if (assets == 0) revert YieldVault__AmountMustBeMoreThanZero();
        if (totalAssets() + assets > depositCap) revert YieldVault__DepositCapExceeded();
    }

    function _checkCooldown(address owner) private view {
        if (block.timestamp < lastDepositTimestamp[owner] + withdrawalCooldown) {
            revert YieldVault__CooldownNotFinished();
        }
    }
}
