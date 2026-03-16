# Solidity DeFi Collection

A Foundry-based Solidity repository containing several small DeFi protocol modules and integration examples.

## Modules

### Stablecoin Lending Protocol

Core files:

- `src/LendingEngine.sol`
- `src/DecentralizedStablecoin.sol`
- `src/mocks/MockV3Aggregator.sol`

Features:

- overcollateralized minting
- collateral allowlist
- Chainlink-style price feeds
- health factor checks
- `deposit / mint / burn / redeem / liquidate`

### Simple AMM

Core file:

- `src/SimpleAMM.sol`

Features:

- constant-product pricing
- liquidity add/remove
- LP token mint/burn
- 0.3% swap fee

### Staking Rewards

Core file:

- `src/StakingRewards.sol`

Features:

- stake / withdraw / claim flow
- linear reward streaming over time
- proportional multi-user reward accounting

### Yield Vault

Core files:

- `src/YieldVault.sol`
- `script/DeployYieldVault.s.sol`

Features:

- ERC4626-based vault shares
- deposit cap risk control
- withdrawal cooldown
- simulated yield harvest for local strategy testing

### Flash Loan And Liquidation Example

Core files:

- `src/mocks/MockFlashLender.sol`
- `src/LiquidationOperator.sol`
- `examples/flashloan/MyFlashLoanSepolia.sol`

Notes:

- `MockFlashLender` and `LiquidationOperator` are used for local, testable flash loan liquidation flows.
- `examples/flashloan/MyFlashLoanSepolia.sol` is a standalone Aave V3 receiver example for Sepolia.

## Repository Layout

- `src/`: protocol contracts
- `src/mocks/`: mocks and local test helpers
- `script/`: Foundry deployment scripts
- `test/`: unit and invariant tests
- `examples/`: standalone examples

## Tests

Test files:

- `test/LendingEngine.t.sol`
- `test/SimpleAMM.t.sol`
- `test/StakingRewards.t.sol`
- `test/YieldVault.t.sol`
- `test/LiquidationOperator.t.sol`
- `test/invariant/LendingEngineInvariant.t.sol`

Covered areas:

- lending protocol mint, redeem, liquidation, and health checks
- AMM liquidity and swap behavior
- staking reward accrual and distribution
- vault deposits, cooldown controls, and share price appreciation after harvest
- flash loan plus liquidation integration
- invariant checks for debt and healthy-position constraints

Current result:

```bash
forge test -vv
```

At the time of writing, the suite passes with `22/22` tests.

## Local Usage

Install dependencies:

```bash
forge install
```

Build:

```bash
forge build
```

Test:

```bash
forge test -vv
```

Format:

```bash
forge fmt
```

## Deployment Scripts

Deploy the lending protocol:

```bash
forge script script/DeployLendingEngine.s.sol:DeployLendingEngine \
  --rpc-url http://127.0.0.1:8545 \
  --private-key <ANVIL_PRIVATE_KEY> \
  --broadcast
```

Deploy the full demo:

```bash
forge script script/DeployDefiPortfolio.s.sol:DeployDefiPortfolio \
  --rpc-url http://127.0.0.1:8545 \
  --private-key <ANVIL_PRIVATE_KEY> \
  --broadcast
```

Deploy the yield vault demo:

```bash
forge script script/DeployYieldVault.s.sol:DeployYieldVault \
  --rpc-url http://127.0.0.1:8545 \
  --private-key <ANVIL_PRIVATE_KEY> \
  --broadcast
```

Start a local chain first if needed:

```bash
anvil
```
