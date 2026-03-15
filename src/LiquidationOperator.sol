// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {LendingEngine} from "./LendingEngine.sol";
import {MockFlashLender, IFlashLoanReceiver} from "./mocks/MockFlashLender.sol";
import {SimpleAMM} from "./SimpleAMM.sol";

contract LiquidationOperator is Ownable, IFlashLoanReceiver {
    using SafeERC20 for IERC20;

    error LiquidationOperator__InvalidLender();
    error LiquidationOperator__InvalidToken();
    error LiquidationOperator__InsufficientRepaymentBalance();

    bytes32 private constant CALLBACK_SUCCESS = keccak256("MockFlashLender.onFlashLoan");

    LendingEngine public immutable engine;
    SimpleAMM public immutable amm;
    IERC20 public immutable dsc;
    IERC20 public immutable collateralToken;

    event LiquidationExecuted(address indexed user, uint256 debtCovered, uint256 dscProfit);

    constructor(address engineAddress, address ammAddress, address dscAddress, address collateralTokenAddress)
        Ownable(msg.sender)
    {
        engine = LendingEngine(engineAddress);
        amm = SimpleAMM(ammAddress);
        dsc = IERC20(dscAddress);
        collateralToken = IERC20(collateralTokenAddress);
    }

    function executeLiquidation(address lender, address user, uint256 debtToCover, uint256 minDscOut)
        external
        onlyOwner
        returns (bool)
    {
        bytes memory data = abi.encode(msg.sender, lender, user, minDscOut);
        return MockFlashLender(lender).flashLoan(address(this), address(dsc), debtToCover, data);
    }

    function onFlashLoan(address, address token, uint256 amount, uint256 fee, bytes calldata data)
        external
        override
        returns (bytes32)
    {
        (address profitReceiver, address lender, address user, uint256 minDscOut) =
            abi.decode(data, (address, address, address, uint256));

        if (msg.sender != lender) revert LiquidationOperator__InvalidLender();
        if (token != address(dsc)) revert LiquidationOperator__InvalidToken();

        dsc.forceApprove(address(engine), amount);
        engine.liquidate(address(collateralToken), user, amount);

        uint256 collateralBalance = collateralToken.balanceOf(address(this));
        collateralToken.forceApprove(address(amm), collateralBalance);
        amm.swap(address(collateralToken), collateralBalance, minDscOut);

        uint256 amountOwed = amount + fee;
        uint256 dscBalance = dsc.balanceOf(address(this));
        if (dscBalance < amountOwed) revert LiquidationOperator__InsufficientRepaymentBalance();

        dsc.safeTransfer(lender, amountOwed);

        uint256 dscProfit = dsc.balanceOf(address(this));
        if (dscProfit > 0) {
            dsc.safeTransfer(profitReceiver, dscProfit);
        }

        emit LiquidationExecuted(user, amount, dscProfit);
        return CALLBACK_SUCCESS;
    }
}
