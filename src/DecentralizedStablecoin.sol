// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract DecentralizedStablecoin is ERC20, Ownable {
    error DecentralizedStablecoin__AmountMustBeMoreThanZero();
    error DecentralizedStablecoin__BurnAmountExceedsBalance();
    error DecentralizedStablecoin__NotZeroAddress();

    constructor() ERC20("Decentralized Stablecoin", "DSC") Ownable(msg.sender) {}

    function burn(uint256 amount) external onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (amount == 0) revert DecentralizedStablecoin__AmountMustBeMoreThanZero();
        if (amount > balance) revert DecentralizedStablecoin__BurnAmountExceedsBalance();
        _burn(msg.sender, amount);
    }

    function mint(address to, uint256 amount) external onlyOwner returns (bool) {
        if (to == address(0)) revert DecentralizedStablecoin__NotZeroAddress();
        if (amount == 0) revert DecentralizedStablecoin__AmountMustBeMoreThanZero();
        _mint(to, amount);
        return true;
    }
}
