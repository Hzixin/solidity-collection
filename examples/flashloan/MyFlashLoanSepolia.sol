// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

// Aave V3 相关接口和基类（Remix 中可从 GitHub raw 导入，或用 @aave/core-v3 包）
// 推荐在 Remix "File Explorers" -> "GitHub" 导入：https://github.com/aave/aave-v3-core/blob/master/contracts/flashloan/base/FlashLoanSimpleReceiverBase.sol 等
// 或直接用下面接口定义（简化版）

import {FlashLoanSimpleReceiverBase} from "@aave/core-v3/contracts/flashloan/base/FlashLoanSimpleReceiverBase.sol";
import {IPoolAddressesProvider} from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// 如果 Remix 导入失败，可用下面最小接口替换（但推荐官方导入）
/*
interface IPool {
    function flashLoanSimple(
        address receiverAddress,
        address asset,
        uint256 amount,
        bytes calldata params,
        uint16 referralCode
    ) external;
}
*/

contract MyFlashLoanSepolia is FlashLoanSimpleReceiverBase {
    using SafeERC20 for IERC20;

    address payable public immutable owner;

    // Sepolia Aave V3 USDT (underlying mock token, 6 decimals)
    address public constant USDT = 0xaA8E23Fb1079EA71e0a56F48a2aA51851D8433D0;

    // 事件：方便监控和调试
    event FlashLoanRequested(address indexed token, uint256 amount, uint256 premium, address initiator);

    event FlashLoanExecuted(address indexed token, uint256 amountBorrowed, uint256 premiumPaid, uint256 profit);

    // 构造函数：传入 Sepolia 的 PoolAddressesProvider
    constructor() FlashLoanSimpleReceiverBase(IPoolAddressesProvider(0x012bAC54348C0E635dCAc9D5FB99f06F24136C9A)) {
        owner = payable(msg.sender);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can request flash loan");
        _;
    }

    /**
     * @dev 专门借 Sepolia USDT 的入口函数（推荐使用这个）
     * @param _amount 要借的数量（单位：USDT decimals = 6，所以 1 USDT = 1e6）
     */
    function requestFlashLoanUSDT(uint256 _amount) external onlyOwner {
        // 调用 Aave Pool 的 flashLoanSimple，借 USDT
        POOL.flashLoanSimple(
            address(this), // receiver = 本合约
            USDT, // 资产 = Sepolia mock USDT
            _amount, // 数量
            "", // params，可自定义 bytes（如套利路径）
            0 // referralCode = 0
        );

        emit FlashLoanRequested(USDT, _amount, 0, msg.sender);
    }

    /**
     * @dev 通用借贷入口（可借其他资产，如 WETH: 0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c）
     */
    function requestFlashLoan(address _token, uint256 _amount) external onlyOwner {
        POOL.flashLoanSimple(address(this), _token, _amount, "", 0);

        emit FlashLoanRequested(_token, _amount, 0, msg.sender);
    }

    /**
     * @dev Aave 回调：资金已到账，必须在此处执行逻辑并归还
     */
    function executeOperation(address asset, uint256 amount, uint256 premium, address, bytes calldata)
        external
        override
        returns (bool)
    {
        require(msg.sender == address(POOL), "Caller must be Aave Pool");

        // =====================================
        // 自定义逻辑区（示例：空操作）
        // 真实中：用借来的 USDT 去 Uniswap/Sushiswap 套利、清算等
        // 必须确保结束时余额 >= amount + premium
        // =====================================

        uint256 totalDebt = amount + premium;

        // 批准 Pool 拉走本金 + 0.09% premium
        IERC20(asset).approve(address(POOL), totalDebt);

        // 记录事件（profit=0 为示例，真实策略可计算）
        emit FlashLoanExecuted(asset, amount, premium, 0);

        return true; // 返回 true → 成功归还
    }

    // 提取合约剩余代币（调试/提利润）
    function withdrawToken(address _token) external onlyOwner {
        IERC20 token = IERC20(_token);
        uint256 balance = token.balanceOf(address(this));
        token.safeTransfer(owner, balance);
    }

    receive() external payable {}
}
