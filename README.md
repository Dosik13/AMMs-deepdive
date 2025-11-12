# Uniswap V3 Swapper

A comprehensive Solidity smart contract wrapper for Uniswap V3 that simplifies token swapping and liquidity management with automatic optimal pool selection, built-in slippage protection, and transaction history tracking.

## Overview

`Swapper` is a contract that enhances the Uniswap V3 experience by:
- **Automatic Optimal Pool Selection**: Automatically finds and uses the best pool across multiple fee tiers (0.05%, 0.3%, 1%)
- **Flexible Swap Types**: Supports both exact input and exact output swaps
- **Liquidity Management**: Manage Uniswap V3 NFT positions (increase/decrease liquidity)
- **Customizable Slippage Protection**: Per-user slippage tolerance with a default of 0.5%
- **Transaction History**: Tracks all swaps and liquidity actions per user
- **Gas Optimization**: Handles token approvals and transfers efficiently

## Features

### Swap Functionality
- **Exact Input Swaps**: Swap a fixed amount of input tokens for maximum output
- **Exact Output Swaps**: Swap to receive a fixed amount of output tokens
- **Optimal Pool Selection**: Automatically selects the best pool from available fee tiers (500, 3000, 10000 bps)
- **Slippage Protection**: Configurable per-user slippage tolerance (default: 0.5%)

### Liquidity Management
- **Increase Liquidity**: Add more tokens to existing Uniswap V3 positions
- **Decrease Liquidity**: Remove liquidity from positions
- **Position Ownership Validation**: Ensures only position owners can manage their liquidity

### History & Tracking
- **Swap History**: Complete history of all swaps per user with timestamps, amounts, and pool fees
- **Liquidity Action History**: Track all liquidity increases and decreases
- **Global Statistics**: Total swaps and liquidity actions across all users

## Prerequisites

- [Foundry](https://getfoundry.sh/) installed
- An Ethereum RPC endpoint (e.g., Alchemy, Infura)
- Set `ETHEREUM_API` environment variable with your RPC URL

## Setup

1. **Clone the repository**:
```bash
git clone https://github.com/Dosik13/AMMs-deepdive
cd AMMs-deepdive
```

2. **Install dependencies**:
```bash
forge install
```

3. **Set up environment variables**:

Copy the example environment file:
```bash
cp .env.example .env
```

Edit `.env` and add your values:
```bash
ETHEREUM_API=https://eth-mainnet.g.alchemy.com/v2/YOUR_API_KEY
PRIVATE_KEY=0xYOUR_PRIVATE_KEY
```

Or export variables directly:
```bash
export ETHEREUM_API=https://eth-mainnet.g.alchemy.com/v2/YOUR_API_KEY
export PRIVATE_KEY=0xYOUR_PRIVATE_KEY
```

## Building

```bash
forge build
```

## Testing

### Run all tests (on forked mainnet):
```bash
forge test --fork-url $ETHEREUM_API -vvv
```

## Scripts using Anvil

### Start Anvil with mainnet fork:
```bash
anvil --fork-url $ETHEREUM_API
```

### Run scripts against local Anvil:
```bash
forge script script/Swapper.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast
```

## Contract Details

### Contract: `Swapper`

**Location**: `src/Swapper.sol`

**Constructor Parameters**:
- `_swapRouter`: Address of Uniswap V3 SwapRouter
- `_quoter`: Address of Uniswap V3 QuoterV2
- `_positionManager`: Address of Uniswap V3 NonfungiblePositionManager

**Main Functions**:

#### Swap Functions
- `swapExactInputSingle(address tokenIn, address tokenOut, address recipient, uint256 deadline, uint256 amountIn, uint256 amountOutMinimum, uint160 sqrtPriceLimitX96)` - Execute exact input swap
- `swapExactOutputSingle(address tokenIn, address tokenOut, address recipient, uint256 deadline, uint256 amountOut, uint256 amountInMaximum, uint160 sqrtPriceLimitX96)` - Execute exact output swap

#### Liquidity Management
- `increaseLiquidity(uint256 tokenId, uint256 amount0Desired, uint256 amount1Desired, uint256 amount0Min, uint256 amount1Min, uint256 deadline)` - Add liquidity to a position
- `decreaseLiquidity(uint256 tokenId, uint128 liquidity, uint256 amount0Min, uint256 amount1Min, uint256 deadline)` - Remove liquidity from a position

#### Configuration
- `setSlippageTolerance(uint256 _slippageBps)` - Set custom slippage tolerance (in basis points, max 10000 = 100%)

#### View Functions
- `getUserSlippageTolerance(address user)` - Get user's slippage tolerance (returns default if not set)
- `getUserSwapCount(address user)` - Get total number of swaps by a user
- `getUserLiquidityActionCount(address user)` - Get total liquidity actions by a user
- `getUserSwap(address user, uint256 index)` - Get specific swap by index
- `getUserLiquidityAction(address user, uint256 index)` - Get specific liquidity action by index
- `getUserLastSwap(address user)` - Get user's most recent swap
- `getUserLastLiquidityAction(address user)` - Get user's most recent liquidity action

### Events

- `ExactInputSwapExecuted` - Emitted on exact input swap execution
- `ExactOutputSwapExecuted` - Emitted on exact output swap execution
- `SlippageToleranceUpdated` - Emitted when user updates slippage tolerance
- `OptimalPoolSelected` - Emitted when optimal pool is found
- `LiquidityIncreased` - Emitted when liquidity is added to a position
- `LiquidityDecreased` - Emitted when liquidity is removed from a position

### Error Handling

The contract uses custom errors for gas-efficient error handling:
- `InvalidRouterAddress()` - Router address cannot be zero
- `InvalidQuoterAddress()` - Quoter address cannot be zero
- `InvalidPositionManagerAddress()` - Position manager address cannot be zero
- `InvalidTokenAddress()` - Token address cannot be zero
- `InvalidAmount()` - Amount cannot be zero
- `DeadlineExpired()` - Transaction deadline has passed
- `SlippageExceeded()` - Actual slippage exceeds user's tolerance
- `NoPoolAvailable()` - No suitable pool found for the token pair
- `NotPositionOwner()` - User is not the owner of the position
- `ZeroLiquidity()` - Cannot decrease zero liquidity
- `IndexOutOfBounds()` - Array index out of bounds
- `NoSwapsFound()` - User has no swap history
- `NoLiquidityActionsFound()` - User has no liquidity action history

## Architecture

### Optimal Pool Selection

The contract automatically finds the best pool by:
1. Checking all three fee tiers: 0.05% (500 bps), 0.3% (3000 bps), 1% (10000 bps)
2. Using QuoterV2 to get quotes from available pools
3. Selecting the pool with the best output (highest for exact input, lowest input for exact output)
4. Reverting if no suitable pool is found

### Slippage Protection

- Default slippage tolerance: 0.5% (500 basis points)
- Users can set custom slippage tolerance per address
- Slippage is calculated and validated after swap execution
- Transactions revert if actual slippage exceeds tolerance

### Token Management

- Automatically handles token transfers from users
- Manages approvals for Uniswap contracts
- Returns unused tokens (for exact output swaps)
- Cleans up approvals after operations

## Security Considerations

- All input validation (zero addresses, amounts, deadlines)
- Position ownership verification for liquidity operations
- Slippage protection with configurable tolerance
- Safe token transfer operations using TransferHelper
- Approval cleanup to prevent token lockups

## Dependencies

- **Uniswap V3 Core**: Pool and factory interfaces
- **Uniswap V3 Periphery**: SwapRouter, QuoterV2, PositionManager interfaces
- **OpenZeppelin**: ERC20 interface
- **Forge Std**: Testing utilities

## License

MIT
