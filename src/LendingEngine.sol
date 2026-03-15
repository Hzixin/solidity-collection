// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {DecentralizedStablecoin} from "./DecentralizedStablecoin.sol";

contract LendingEngine is ReentrancyGuard {
    using SafeERC20 for IERC20;

    error LendingEngine__AmountMustBeMoreThanZero();
    error LendingEngine__TokenNotAllowed(address token);
    error LendingEngine__BreaksHealthFactor(uint256 healthFactor);
    error LendingEngine__MintFailed();
    error LendingEngine__HealthFactorOk();
    error LendingEngine__HealthFactorNotImproved();
    error LendingEngine__InvalidPrice();

    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    event CollateralRedeemed(address indexed from, address indexed to, address indexed token, uint256 amount);
    event DscMinted(address indexed user, uint256 amount);
    event DscBurned(address indexed payer, address indexed onBehalfOf, uint256 amount);
    event Liquidation(
        address indexed liquidator,
        address indexed user,
        address indexed collateralToken,
        uint256 debtCovered,
        uint256 collateralRedeemed
    );

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 75;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_BONUS = 10;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountMinted) private s_dscMinted;
    address[] private s_collateralTokens;

    DecentralizedStablecoin private immutable i_dsc;

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) revert LendingEngine__AmountMustBeMoreThanZero();
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) revert LendingEngine__TokenNotAllowed(token);
        _;
    }

    constructor(address[] memory collateralTokens, address[] memory priceFeeds) {
        if (collateralTokens.length != priceFeeds.length) {
            revert LendingEngine__TokenNotAllowed(address(0));
        }

        for (uint256 i = 0; i < collateralTokens.length; i++) {
            s_priceFeeds[collateralTokens[i]] = priceFeeds[i];
            s_collateralTokens.push(collateralTokens[i]);
        }

        i_dsc = new DecentralizedStablecoin();
    }

    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 collateralAmount,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, collateralAmount);
        mintDsc(amountDscToMint);
    }

    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 collateralAmount, uint256 amountDscToBurn)
        external
    {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, collateralAmount);
    }

    function depositCollateral(address tokenCollateralAddress, uint256 collateralAmount)
        public
        moreThanZero(collateralAmount)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += collateralAmount;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, collateralAmount);
        IERC20(tokenCollateralAddress).safeTransferFrom(msg.sender, address(this), collateralAmount);
    }

    function redeemCollateral(address tokenCollateralAddress, uint256 collateralAmount)
        public
        moreThanZero(collateralAmount)
        nonReentrant
    {
        _redeemCollateral(tokenCollateralAddress, collateralAmount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_dscMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);

        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) revert LendingEngine__MintFailed();
        emit DscMinted(msg.sender, amountDscToMint);
    }

    function burnDsc(uint256 amount) public moreThanZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        isAllowedToken(collateral)
        nonReentrant
    {
        uint256 startingHealthFactor = _healthFactor(user);
        if (startingHealthFactor >= MIN_HEALTH_FACTOR) revert LendingEngine__HealthFactorOk();

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;

        _burnDsc(debtToCover, user, msg.sender);
        _redeemCollateral(collateral, totalCollateralToRedeem, user, msg.sender);

        uint256 endingHealthFactor = _healthFactor(user);
        if (endingHealthFactor <= startingHealthFactor) revert LendingEngine__HealthFactorNotImproved();

        _revertIfHealthFactorIsBroken(msg.sender);
        emit Liquidation(msg.sender, user, collateral, debtToCover, totalCollateralToRedeem);
    }

    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private {
        s_dscMinted[onBehalfOf] -= amountDscToBurn;
        IERC20(address(i_dsc)).safeTransferFrom(dscFrom, address(this), amountDscToBurn);
        i_dsc.burn(amountDscToBurn);
        emit DscBurned(dscFrom, onBehalfOf, amountDscToBurn);
    }

    function _redeemCollateral(address tokenCollateralAddress, uint256 collateralAmount, address from, address to)
        private
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= collateralAmount;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, collateralAmount);
        IERC20(tokenCollateralAddress).safeTransfer(to, collateralAmount);
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_dscMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        if (totalDscMinted == 0) return type(uint256).max;

        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) private view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) revert LendingEngine__BreaksHealthFactor(userHealthFactor);
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        uint256 price = _getValidatedPrice(token);
        return ((price * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        uint256 price = _getValidatedPrice(token);
        return (usdAmountInWei * PRECISION) / (price * ADDITIONAL_FEED_PRECISION);
    }

    function _getValidatedPrice(address token) private view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        if (price <= 0) revert LendingEngine__InvalidPrice();
        // Casting is safe because negative and zero answers are rejected above.
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint256(price);
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            if (amount > 0) {
                totalCollateralValueInUsd += getUsdValue(token, amount);
            }
        }
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        return _getAccountInformation(user);
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getDscAddress() external view returns (address) {
        return address(i_dsc);
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }
}
