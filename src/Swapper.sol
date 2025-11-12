// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IQuoterV2} from "@uniswap/v3-periphery/contracts/interfaces/IQuoterV2.sol";
import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IPeripheryImmutableState} from "@uniswap/v3-periphery/contracts/interfaces/IPeripheryImmutableState.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {console} from "forge-std/console.sol";

contract Swapper {
    uint256 public constant DEFAULT_SLIPPAGE_TOLERANCE = 500;
    uint256 private constant SLIPPAGE_DENOMINATOR = 10000;

    ISwapRouter public immutable SWAP_ROUTER;
    IQuoterV2 public immutable QUOTER;
    IUniswapV3Factory public immutable FACTORY;
    INonfungiblePositionManager public immutable POSITION_MANAGER;

    mapping(address => uint256) public slippageTolerance;
    mapping(address => SwapAction[]) private userSwaps;
    mapping(address => LiquidityAction[]) private userLiquidityActions;

    uint256 public totalSwaps;
    uint256 public totalLiquidityActions;

    struct SwapAction {
        uint256 timestamp;
        uint256 blockNumber;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 amountOut;
        uint24 fee;
        bool isExactInput;
    }

    struct LiquidityAction {
        uint256 timestamp;
        uint256 blockNumber;
        uint256 tokenId;
        bool isIncrease;
        uint128 liquidity;
        uint256 amount0;
        uint256 amount1;
    }

    event ExactInputSwapExecuted(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address indexed recipient
    );
    event ExactOutputSwapExecuted(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address indexed recipient
    );
    event SlippageToleranceUpdated(address indexed user, uint256 oldTolerance, uint256 newTolerance);
    event OptimalPoolSelected(address indexed tokenIn, address indexed tokenOut, uint24 selectedFee, uint256 amountOut);
    event LiquidityIncreased(uint256 indexed tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
    event LiquidityDecreased(uint256 indexed tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);

    error InvalidRouterAddress();
    error DeadlineExpired();
    error InvalidTokenAddress();
    error InvalidAmount();
    error SlippageToleranceTooHigh(uint256 provided, uint256 max);
    error SlippageExceeded(uint256 actualSlippage, uint256 maxSlippage);
    error InvalidQuoterAddress();
    error NoPoolAvailable();
    error InvalidPositionManagerAddress();
    error NotPositionOwner();
    error ZeroLiquidity();
    error IndexOutOfBounds();
    error NoSwapsFound();
    error NoLiquidityActionsFound();

    constructor(address _swapRouter, address _quoter, address _positionManager) {
        if (_swapRouter == address(0)) revert InvalidRouterAddress();
        if (_quoter == address(0)) revert InvalidQuoterAddress();
        if (_positionManager == address(0)) {
            revert InvalidPositionManagerAddress();
        }

        SWAP_ROUTER = ISwapRouter(_swapRouter);
        QUOTER = IQuoterV2(_quoter);
        POSITION_MANAGER = INonfungiblePositionManager(_positionManager);

        address factoryAddress = IPeripheryImmutableState(_swapRouter).factory();
        FACTORY = IUniswapV3Factory(factoryAddress);
    }

    function setSlippageTolerance(uint256 _slippageBps) external {
        uint256 oldTolerance = slippageTolerance[msg.sender];
        slippageTolerance[msg.sender] = _slippageBps;

        emit SlippageToleranceUpdated(msg.sender, oldTolerance, _slippageBps);
    }

    function swapExactInputSingle(
        address tokenIn,
        address tokenOut,
        address recipient,
        uint256 deadline,
        uint256 amountIn,
        uint256 amountOutMinimum,
        uint160 sqrtPriceLimitX96
    ) external returns (uint256 amountOut, uint24 optimalFee) {
        if (tokenIn == address(0) || tokenOut == address(0)) {
            revert InvalidTokenAddress();
        }
        if (amountIn == 0) revert InvalidAmount();
        if (block.timestamp > deadline) revert DeadlineExpired();

        uint256 expectedAmountOut;
        (optimalFee, expectedAmountOut) = findOptimalPoolExactInput(tokenIn, tokenOut, amountIn, sqrtPriceLimitX96);

        emit OptimalPoolSelected(tokenIn, tokenOut, optimalFee, expectedAmountOut);

        uint256 userSlippageTolerance = getUserSlippageTolerance(msg.sender);
        uint256 calculatedExpectedAmountOut =
            (amountOutMinimum * SLIPPAGE_DENOMINATOR) / (SLIPPAGE_DENOMINATOR - userSlippageTolerance);

        if (expectedAmountOut > calculatedExpectedAmountOut) {
            calculatedExpectedAmountOut = expectedAmountOut;
        }

        TransferHelper.safeTransferFrom(tokenIn, msg.sender, address(this), amountIn);

        TransferHelper.safeApprove(tokenIn, address(SWAP_ROUTER), amountIn);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: optimalFee,
            recipient: recipient,
            deadline: deadline,
            amountIn: amountIn,
            amountOutMinimum: amountOutMinimum,
            sqrtPriceLimitX96: sqrtPriceLimitX96
        });

        amountOut = SWAP_ROUTER.exactInputSingle(params);

        if (amountOut < calculatedExpectedAmountOut) {
            uint256 slippageAmount = calculatedExpectedAmountOut - amountOut;
            uint256 actualSlippageBps = (slippageAmount * SLIPPAGE_DENOMINATOR) / calculatedExpectedAmountOut;

            if (actualSlippageBps > userSlippageTolerance) {
                revert SlippageExceeded(actualSlippageBps, userSlippageTolerance);
            }
        }

        userSwaps[msg.sender].push(
            SwapAction({
                timestamp: block.timestamp,
                blockNumber: block.number,
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                amountIn: amountIn,
                amountOut: amountOut,
                fee: optimalFee,
                isExactInput: true
            })
        );
        totalSwaps++;

        emit ExactInputSwapExecuted(tokenIn, tokenOut, amountIn, amountOut, recipient);

        return (amountOut, optimalFee);
    }

    function swapExactOutputSingle(
        address tokenIn,
        address tokenOut,
        address recipient,
        uint256 deadline,
        uint256 amountOut,
        uint256 amountInMaximum,
        uint160 sqrtPriceLimitX96
    ) external returns (uint256 amountIn, uint24 optimalFee) {
        if (tokenIn == address(0) || tokenOut == address(0)) {
            revert InvalidTokenAddress();
        }
        if (amountOut == 0) revert InvalidAmount();
        if (block.timestamp > deadline) revert DeadlineExpired();

        uint256 expectedAmountIn;
        (optimalFee, expectedAmountIn) = findOptimalPoolExactOutput(tokenIn, tokenOut, amountOut, sqrtPriceLimitX96);

        emit OptimalPoolSelected(tokenIn, tokenOut, optimalFee, amountOut);

        uint256 userSlippageTolerance = getUserSlippageTolerance(msg.sender);

        uint256 calculatedExpectedAmountIn =
            (amountInMaximum * SLIPPAGE_DENOMINATOR) / (SLIPPAGE_DENOMINATOR + userSlippageTolerance);

        if (expectedAmountIn < calculatedExpectedAmountIn) {
            calculatedExpectedAmountIn = expectedAmountIn;
        }

        if (expectedAmountIn > amountInMaximum) {
            revert SlippageExceeded(
                ((expectedAmountIn - amountInMaximum) * SLIPPAGE_DENOMINATOR) / amountInMaximum, userSlippageTolerance
            );
        }

        TransferHelper.safeTransferFrom(tokenIn, msg.sender, address(this), amountInMaximum);

        TransferHelper.safeApprove(tokenIn, address(SWAP_ROUTER), amountInMaximum);

        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: optimalFee,
            recipient: recipient,
            deadline: deadline,
            amountOut: amountOut,
            amountInMaximum: amountInMaximum,
            sqrtPriceLimitX96: sqrtPriceLimitX96
        });

        amountIn = SWAP_ROUTER.exactOutputSingle(params);

        TransferHelper.safeApprove(tokenIn, address(SWAP_ROUTER), 0);

        if (amountIn < amountInMaximum) {
            TransferHelper.safeTransfer(tokenIn, msg.sender, amountInMaximum - amountIn);
        }

        if (amountIn > calculatedExpectedAmountIn) {
            uint256 slippageAmount = amountIn - calculatedExpectedAmountIn;
            uint256 actualSlippageBps = (slippageAmount * SLIPPAGE_DENOMINATOR) / calculatedExpectedAmountIn;

            if (actualSlippageBps > userSlippageTolerance) {
                revert SlippageExceeded(actualSlippageBps, userSlippageTolerance);
            }
        }

        userSwaps[msg.sender].push(
            SwapAction({
                timestamp: block.timestamp,
                blockNumber: block.number,
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                amountIn: amountIn,
                amountOut: amountOut,
                fee: optimalFee,
                isExactInput: false
            })
        );
        totalSwaps++;

        emit ExactOutputSwapExecuted(tokenIn, tokenOut, amountIn, amountOut, recipient);

        return (amountIn, optimalFee);
    }

    function increaseLiquidity(
        uint256 tokenId,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        uint256 deadline
    ) external returns (uint128 liquidity, uint256 amount0, uint256 amount1) {
        address owner = POSITION_MANAGER.ownerOf(tokenId);
        if (owner != msg.sender) revert NotPositionOwner();

        if (amount0Desired == 0 && amount1Desired == 0) revert InvalidAmount();
        if (block.timestamp > deadline) revert DeadlineExpired();

        (,, address token0, address token1,,,,,,,,) = POSITION_MANAGER.positions(tokenId);

        if (amount0Desired > 0) {
            TransferHelper.safeTransferFrom(token0, msg.sender, address(this), amount0Desired);
            TransferHelper.safeApprove(token0, address(POSITION_MANAGER), amount0Desired);
        }

        if (amount1Desired > 0) {
            TransferHelper.safeTransferFrom(token1, msg.sender, address(this), amount1Desired);
            TransferHelper.safeApprove(token1, address(POSITION_MANAGER), amount1Desired);
        }

        INonfungiblePositionManager.IncreaseLiquidityParams memory params =
            INonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId: tokenId,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: amount0Min,
                amount1Min: amount1Min,
                deadline: deadline
            });

        (liquidity, amount0, amount1) = POSITION_MANAGER.increaseLiquidity(params);

        if (amount0Desired > 0) {
            TransferHelper.safeApprove(token0, address(POSITION_MANAGER), 0);
        }
        if (amount1Desired > 0) {
            TransferHelper.safeApprove(token1, address(POSITION_MANAGER), 0);
        }

        if (amount0Desired > amount0) {
            TransferHelper.safeTransfer(token0, msg.sender, amount0Desired - amount0);
        }
        if (amount1Desired > amount1) {
            TransferHelper.safeTransfer(token1, msg.sender, amount1Desired - amount1);
        }

        userLiquidityActions[msg.sender].push(
            LiquidityAction({
                timestamp: block.timestamp,
                blockNumber: block.number,
                tokenId: tokenId,
                isIncrease: true,
                liquidity: liquidity,
                amount0: amount0,
                amount1: amount1
            })
        );
        totalLiquidityActions++;

        emit LiquidityIncreased(tokenId, liquidity, amount0, amount1);

        return (liquidity, amount0, amount1);
    }

    function decreaseLiquidity(
        uint256 tokenId,
        uint128 liquidity,
        uint256 amount0Min,
        uint256 amount1Min,
        uint256 deadline
    ) external returns (uint256 amount0, uint256 amount1) {
        address owner = POSITION_MANAGER.ownerOf(tokenId);
        if (owner != msg.sender) revert NotPositionOwner();

        if (liquidity == 0) revert ZeroLiquidity();
        if (block.timestamp > deadline) revert DeadlineExpired();

        (,, address token0, address token1,,,,,,,,) = POSITION_MANAGER.positions(tokenId);

        if (amount0Min > 0) {
            TransferHelper.safeTransferFrom(token0, msg.sender, address(this), amount0Min);
            TransferHelper.safeApprove(token0, address(POSITION_MANAGER), amount0Min);
        }

        if (amount1Min > 0) {
            TransferHelper.safeTransferFrom(token1, msg.sender, address(this), amount1Min);
            TransferHelper.safeApprove(token1, address(POSITION_MANAGER), amount1Min);
        }

        INonfungiblePositionManager.DecreaseLiquidityParams memory params =
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: tokenId,
                liquidity: liquidity,
                amount0Min: amount0Min,
                amount1Min: amount1Min,
                deadline: deadline
            });

        (amount0, amount1) = POSITION_MANAGER.decreaseLiquidity(params);

        userLiquidityActions[msg.sender].push(
            LiquidityAction({
                timestamp: block.timestamp,
                blockNumber: block.number,
                tokenId: tokenId,
                isIncrease: false,
                liquidity: liquidity,
                amount0: amount0,
                amount1: amount1
            })
        );
        totalLiquidityActions++;

        emit LiquidityDecreased(tokenId, liquidity, amount0, amount1);

        return (amount0, amount1);
    }

    function getUserSlippageTolerance(address user) public view returns (uint256) {
        uint256 userTolerance = slippageTolerance[user];
        return userTolerance == 0 ? DEFAULT_SLIPPAGE_TOLERANCE : userTolerance;
    }

    function getFeeTiers() internal pure returns (uint24[3] memory) {
        return [uint24(500), uint24(3000), uint24(10000)];
    }

    function findOptimalPoolExactInput(address tokenIn, address tokenOut, uint256 amountIn, uint160 sqrtPriceLimitX96)
        internal
        returns (uint24 bestFee, uint256 bestAmountOut)
    {
        bestFee = 0;
        bestAmountOut = 0;

        uint24[3] memory feeTiers = getFeeTiers();

        for (uint256 i = 0; i < feeTiers.length; i++) {
            uint24 fee = feeTiers[i];

            address poolAddress = FACTORY.getPool(tokenIn, tokenOut, fee);
            if (poolAddress == address(0)) {
                continue;
            }

            try QUOTER.quoteExactInputSingle(
                IQuoterV2.QuoteExactInputSingleParams({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    amountIn: amountIn,
                    fee: fee,
                    sqrtPriceLimitX96: sqrtPriceLimitX96
                })
            ) returns (
                uint256 amountOut, uint160, uint32, uint256
            ) {
                if (amountOut > bestAmountOut) {
                    bestAmountOut = amountOut;
                    bestFee = fee;
                }
            } catch {
                continue;
            }
        }

        if (bestFee == 0) {
            revert NoPoolAvailable();
        }
    }

    function findOptimalPoolExactOutput(address tokenIn, address tokenOut, uint256 amountOut, uint160 sqrtPriceLimitX96)
        internal
        returns (uint24 bestFee, uint256 bestAmountIn)
    {
        bestFee = 0;
        bestAmountIn = type(uint256).max;

        uint24[3] memory feeTiers = getFeeTiers();

        for (uint256 i = 0; i < feeTiers.length; i++) {
            uint24 fee = feeTiers[i];

            address poolAddress = FACTORY.getPool(tokenIn, tokenOut, fee);
            if (poolAddress == address(0)) {
                continue;
            }

            try QUOTER.quoteExactOutputSingle(
                IQuoterV2.QuoteExactOutputSingleParams({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    amount: amountOut,
                    fee: fee,
                    sqrtPriceLimitX96: sqrtPriceLimitX96
                })
            ) returns (
                uint256 amountIn, uint160, uint32, uint256
            ) {
                if (amountIn < bestAmountIn) {
                    bestAmountIn = amountIn;
                    bestFee = fee;
                }
            } catch {
                continue;
            }
        }

        if (bestFee == 0) {
            revert NoPoolAvailable();
        }
    }

    function getSwapRouter() external view returns (address) {
        return address(SWAP_ROUTER);
    }

    function getUserSwapCount(address user) external view returns (uint256) {
        return userSwaps[user].length;
    }

    function getUserLiquidityActionCount(address user) external view returns (uint256) {
        return userLiquidityActions[user].length;
    }

    function getUserSwap(address user, uint256 index) external view returns (SwapAction memory) {
        if (index >= userSwaps[user].length) revert IndexOutOfBounds();
        return userSwaps[user][index];
    }

    function getUserLiquidityAction(address user, uint256 index) external view returns (LiquidityAction memory) {
        if (index >= userLiquidityActions[user].length) {
            revert IndexOutOfBounds();
        }
        return userLiquidityActions[user][index];
    }

    function getUserLastSwap(address user) external view returns (SwapAction memory) {
        if (userSwaps[user].length == 0) revert NoSwapsFound();
        return userSwaps[user][userSwaps[user].length - 1];
    }

    function getUserLastLiquidityAction(address user) external view returns (LiquidityAction memory) {
        if (userLiquidityActions[user].length == 0) {
            revert NoLiquidityActionsFound();
        }
        return userLiquidityActions[user][userLiquidityActions[user].length - 1];
    }
}
