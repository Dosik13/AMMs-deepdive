// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Swapper} from "../src/Swapper.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

// Import mocks
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockFactory} from "./mocks/MockFactory.sol";
import {MockQuoterV2} from "./mocks/MockQuoterV2.sol";
import {MockSwapRouter} from "./mocks/MockSwapRouter.sol";
import {MockPositionManager} from "./mocks/MockPositionManager.sol";

contract SwapperTest is Test {
    Swapper public swapper;
    MockSwapRouter public mockRouter;
    MockQuoterV2 public mockQuoter;
    MockFactory public mockFactory;
    MockPositionManager public mockPositionManager;
    MockERC20 public tokenA;
    MockERC20 public tokenB;

    address public user = address(0x1);
    address public recipient = address(0x2);
    uint24 public constant FEE = 3000;
    uint256 public constant INITIAL_BALANCE = 10000e18;

    event SlippageToleranceUpdated(address indexed user, uint256 oldTolerance, uint256 newTolerance);

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

    event LiquidityIncreased(uint256 indexed tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);

    event LiquidityDecreased(uint256 indexed tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);

    function setUp() public {
        // Deploy mock contracts
        tokenA = new MockERC20("Token A", "TKNA", INITIAL_BALANCE * 10);
        tokenB = new MockERC20("Token B", "TKNB", INITIAL_BALANCE * 10);
        mockFactory = new MockFactory();
        mockRouter = new MockSwapRouter(address(mockFactory));
        mockQuoter = new MockQuoterV2();
        mockPositionManager = new MockPositionManager();

        // Deploy Swapper
        swapper = new Swapper(address(mockRouter), address(mockQuoter), address(mockPositionManager));

        // Set up pool
        mockFactory.setPool(address(tokenA), address(tokenB), FEE, address(0x999));

        // Give user tokens
        tokenA.mint(user, INITIAL_BALANCE);
        tokenB.mint(user, INITIAL_BALANCE);

        // User approves swapper
        vm.startPrank(user);
        tokenA.approve(address(swapper), type(uint256).max);
        tokenB.approve(address(swapper), type(uint256).max);
        vm.stopPrank();
    }

    function testConstructor() public view {
        assertEq(address(swapper.SWAP_ROUTER()), address(mockRouter));
        assertEq(address(swapper.QUOTER()), address(mockQuoter));
        assertEq(address(swapper.POSITION_MANAGER()), address(mockPositionManager));
        assertEq(address(swapper.FACTORY()), address(mockFactory));
    }

    function testConstructorRevertsWithZeroRouter() public {
        vm.expectRevert(Swapper.InvalidRouterAddress.selector);
        new Swapper(address(0), address(mockQuoter), address(mockPositionManager));
    }

    function testConstructorRevertsWithZeroQuoter() public {
        vm.expectRevert(Swapper.InvalidQuoterAddress.selector);
        new Swapper(address(mockRouter), address(0), address(mockPositionManager));
    }

    function testConstructorRevertsWithZeroPositionManager() public {
        vm.expectRevert(Swapper.InvalidPositionManagerAddress.selector);
        new Swapper(address(mockRouter), address(mockQuoter), address(0));
    }

    function testSetSlippageTolerance() public {
        vm.startPrank(user);

        vm.expectEmit(true, false, false, true);
        emit SlippageToleranceUpdated(user, 0, 1000);

        swapper.setSlippageTolerance(1000);
        assertEq(swapper.slippageTolerance(user), 1000);

        vm.stopPrank();
    }

    function testGetUserSlippageTolerance() public view {
        // Should return default if not set
        assertEq(swapper.getUserSlippageTolerance(user), 500); // DEFAULT_SLIPPAGE_TOLERANCE
    }

    function testSwapExactInputSingle() public {
        vm.startPrank(user);

        uint256 amountIn = 1e18;
        uint256 expectedAmountOut = 1000e18;
        mockRouter.setMockAmountOut(expectedAmountOut);

        uint256 userBalanceBefore = tokenA.balanceOf(user);
        uint256 recipientBalanceBefore = tokenB.balanceOf(recipient);

        vm.expectEmit(true, true, true, true);
        emit ExactInputSwapExecuted(address(tokenA), address(tokenB), amountIn, expectedAmountOut, recipient);

        (uint256 amountOut, uint24 fee) = swapper.swapExactInputSingle(
            address(tokenA), address(tokenB), recipient, block.timestamp + 1 hours, amountIn, 0, 0
        );

        assertEq(amountOut, expectedAmountOut);
        assertEq(fee, FEE);
        assertEq(tokenA.balanceOf(user), userBalanceBefore - amountIn);
        assertEq(tokenB.balanceOf(recipient), recipientBalanceBefore + expectedAmountOut);

        // Check tracking
        assertEq(swapper.totalSwaps(), 1);
        assertEq(swapper.getUserSwapCount(user), 1);

        Swapper.SwapAction memory action = swapper.getUserSwap(user, 0);
        assertEq(action.tokenIn, address(tokenA));
        assertEq(action.tokenOut, address(tokenB));
        assertEq(action.amountIn, amountIn);
        assertEq(action.amountOut, expectedAmountOut);
        assertEq(action.fee, FEE);
        assertTrue(action.isExactInput);

        vm.stopPrank();
    }

    function testSwapExactInputSingleRevertsWithZeroAmount() public {
        vm.startPrank(user);

        vm.expectRevert(Swapper.InvalidAmount.selector);
        swapper.swapExactInputSingle(address(tokenA), address(tokenB), recipient, block.timestamp + 1 hours, 0, 0, 0);

        vm.stopPrank();
    }

    function testSwapExactInputSingleRevertsWithExpiredDeadline() public {
        vm.startPrank(user);

        vm.expectRevert(Swapper.DeadlineExpired.selector);
        swapper.swapExactInputSingle(address(tokenA), address(tokenB), recipient, block.timestamp - 1, 1e18, 0, 0);

        vm.stopPrank();
    }

    function testSwapExactOutputSingle() public {
        vm.startPrank(user);

        uint256 amountOut = 1000e18;
        uint256 expectedAmountIn = 1e18;
        mockRouter.setMockAmountIn(expectedAmountIn);
        mockQuoter.setMockAmountIn(expectedAmountIn);

        uint256 userBalanceBefore = tokenA.balanceOf(user);
        uint256 recipientBalanceBefore = tokenB.balanceOf(recipient);

        vm.expectEmit(true, true, true, true);
        emit ExactOutputSwapExecuted(address(tokenA), address(tokenB), expectedAmountIn, amountOut, recipient);

        (uint256 amountIn, uint24 fee) = swapper.swapExactOutputSingle(
            address(tokenA),
            address(tokenB),
            recipient,
            block.timestamp + 1 hours,
            amountOut,
            2e18, // Max amount in
            0
        );

        assertEq(amountIn, expectedAmountIn);
        assertEq(fee, FEE);
        assertEq(tokenA.balanceOf(user), userBalanceBefore - expectedAmountIn);
        assertEq(tokenB.balanceOf(recipient), recipientBalanceBefore + amountOut);

        // Check tracking
        assertEq(swapper.totalSwaps(), 1);
        assertEq(swapper.getUserSwapCount(user), 1);

        Swapper.SwapAction memory action = swapper.getUserSwap(user, 0);
        assertEq(action.tokenIn, address(tokenA));
        assertEq(action.tokenOut, address(tokenB));
        assertEq(action.amountIn, expectedAmountIn);
        assertEq(action.amountOut, amountOut);
        assertFalse(action.isExactInput);

        vm.stopPrank();
    }

    function testIncreaseLiquidity() public {
        vm.startPrank(user);

        // First mint a position via the mock position manager
        tokenA.approve(address(mockPositionManager), type(uint256).max);
        tokenB.approve(address(mockPositionManager), type(uint256).max);

        (uint256 tokenId,,,) = mockPositionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: address(tokenA),
                token1: address(tokenB),
                fee: FEE,
                tickLower: -1000,
                tickUpper: 1000,
                amount0Desired: 100e18,
                amount1Desired: 100e18,
                amount0Min: 0,
                amount1Min: 0,
                recipient: user,
                deadline: block.timestamp + 1 hours
            })
        );

        uint256 amount0Desired = 50e18;
        uint256 amount1Desired = 50e18;

        uint256 userBalanceToken0Before = tokenA.balanceOf(user);
        uint256 userBalanceToken1Before = tokenB.balanceOf(user);

        vm.expectEmit(true, false, false, true);
        emit LiquidityIncreased(tokenId, 500e18, amount0Desired, amount1Desired);

        (uint128 liquidity, uint256 amount0, uint256 amount1) =
            swapper.increaseLiquidity(tokenId, amount0Desired, amount1Desired, 0, 0, block.timestamp + 1 hours);

        assertEq(liquidity, 500e18);
        assertEq(amount0, amount0Desired);
        assertEq(amount1, amount1Desired);
        assertEq(tokenA.balanceOf(user), userBalanceToken0Before - amount0);
        assertEq(tokenB.balanceOf(user), userBalanceToken1Before - amount1);

        // Check tracking
        assertEq(swapper.totalLiquidityActions(), 1);
        assertEq(swapper.getUserLiquidityActionCount(user), 1);

        Swapper.LiquidityAction memory action = swapper.getUserLiquidityAction(user, 0);
        assertEq(action.tokenId, tokenId);
        assertTrue(action.isIncrease);
        assertEq(action.liquidity, liquidity);
        assertEq(action.amount0, amount0);
        assertEq(action.amount1, amount1);

        vm.stopPrank();
    }

    function testIncreaseLiquidityRevertsIfNotOwner() public {
        vm.startPrank(user);

        // Mint position
        tokenA.approve(address(mockPositionManager), type(uint256).max);
        tokenB.approve(address(mockPositionManager), type(uint256).max);

        (uint256 tokenId,,,) = mockPositionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: address(tokenA),
                token1: address(tokenB),
                fee: FEE,
                tickLower: -1000,
                tickUpper: 1000,
                amount0Desired: 100e18,
                amount1Desired: 100e18,
                amount0Min: 0,
                amount1Min: 0,
                recipient: user,
                deadline: block.timestamp + 1 hours
            })
        );

        vm.stopPrank();

        // Try to increase as different user
        vm.startPrank(recipient);

        vm.expectRevert(Swapper.NotPositionOwner.selector);
        swapper.increaseLiquidity(tokenId, 50e18, 50e18, 0, 0, block.timestamp + 1 hours);

        vm.stopPrank();
    }

    function testDecreaseLiquidity() public {
        vm.startPrank(user);

        // First mint a position
        tokenA.approve(address(mockPositionManager), type(uint256).max);
        tokenB.approve(address(mockPositionManager), type(uint256).max);

        (uint256 tokenId, uint128 liquidity,,) = mockPositionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: address(tokenA),
                token1: address(tokenB),
                fee: FEE,
                tickLower: -1000,
                tickUpper: 1000,
                amount0Desired: 100e18,
                amount1Desired: 100e18,
                amount0Min: 0,
                amount1Min: 0,
                recipient: user,
                deadline: block.timestamp + 1 hours
            })
        );

        uint128 liquidityToRemove = liquidity / 2;

        vm.expectEmit(true, false, false, true);
        emit LiquidityDecreased(tokenId, liquidityToRemove, 100e18, 100e18);

        (uint256 amount0, uint256 amount1) =
            swapper.decreaseLiquidity(tokenId, liquidityToRemove, 0, 0, block.timestamp + 1 hours);

        assertEq(amount0, 100e18);
        assertEq(amount1, 100e18);

        // Check tracking
        assertEq(swapper.totalLiquidityActions(), 1);
        assertEq(swapper.getUserLiquidityActionCount(user), 1);

        Swapper.LiquidityAction memory action = swapper.getUserLiquidityAction(user, 0);
        assertEq(action.tokenId, tokenId);
        assertFalse(action.isIncrease);
        assertEq(action.liquidity, liquidityToRemove);

        vm.stopPrank();
    }

    function testDecreaseLiquidityRevertsWithZeroLiquidity() public {
        vm.startPrank(user);

        // Mint position
        tokenA.approve(address(mockPositionManager), type(uint256).max);
        tokenB.approve(address(mockPositionManager), type(uint256).max);

        (uint256 tokenId,,,) = mockPositionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: address(tokenA),
                token1: address(tokenB),
                fee: FEE,
                tickLower: -1000,
                tickUpper: 1000,
                amount0Desired: 100e18,
                amount1Desired: 100e18,
                amount0Min: 0,
                amount1Min: 0,
                recipient: user,
                deadline: block.timestamp + 1 hours
            })
        );

        vm.expectRevert(Swapper.ZeroLiquidity.selector);
        swapper.decreaseLiquidity(tokenId, 0, 0, 0, block.timestamp + 1 hours);

        vm.stopPrank();
    }

    function testGetUserLastSwap() public {
        vm.startPrank(user);

        uint256 amountIn = 1e18;
        mockRouter.setMockAmountOut(1000e18);

        swapper.swapExactInputSingle(
            address(tokenA), address(tokenB), recipient, block.timestamp + 1 hours, amountIn, 0, 0
        );

        Swapper.SwapAction memory lastSwap = swapper.getUserLastSwap(user);
        assertEq(lastSwap.amountIn, amountIn);
        assertEq(lastSwap.tokenIn, address(tokenA));

        vm.stopPrank();
    }
}
