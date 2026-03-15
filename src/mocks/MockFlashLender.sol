// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IFlashLoanReceiver {
    function onFlashLoan(address initiator, address token, uint256 amount, uint256 fee, bytes calldata data)
        external
        returns (bytes32);
}

contract MockFlashLender is ReentrancyGuard {
    using SafeERC20 for IERC20;

    error MockFlashLender__UnsupportedToken();
    error MockFlashLender__InsufficientLiquidity();
    error MockFlashLender__InvalidCallback();
    error MockFlashLender__FlashLoanNotRepaid();

    bytes32 public constant CALLBACK_SUCCESS = keccak256("MockFlashLender.onFlashLoan");

    IERC20 public immutable token;
    uint256 public immutable feeBps;

    event FlashLoan(address indexed receiver, uint256 amount, uint256 fee);

    constructor(address tokenAddress, uint256 feeBps_) {
        token = IERC20(tokenAddress);
        feeBps = feeBps_;
    }

    function flashLoan(address receiver, address tokenAddress, uint256 amount, bytes calldata data)
        external
        nonReentrant
        returns (bool)
    {
        if (tokenAddress != address(token)) revert MockFlashLender__UnsupportedToken();

        uint256 balanceBefore = token.balanceOf(address(this));
        if (amount > balanceBefore) revert MockFlashLender__InsufficientLiquidity();

        uint256 fee = (amount * feeBps) / 10_000;
        token.safeTransfer(receiver, amount);

        bytes32 result = IFlashLoanReceiver(receiver).onFlashLoan(msg.sender, tokenAddress, amount, fee, data);
        if (result != CALLBACK_SUCCESS) revert MockFlashLender__InvalidCallback();

        if (token.balanceOf(address(this)) < balanceBefore + fee) {
            revert MockFlashLender__FlashLoanNotRepaid();
        }

        emit FlashLoan(receiver, amount, fee);
        return true;
    }
}
