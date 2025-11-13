// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";
import {Swapper} from "../src/Swapper.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";

interface IWETH9 is IERC20 {
    function deposit() external payable;

    function withdraw(uint256) external;
}

contract DeployAndTest is Script {
    address constant UNISWAP_V3_SWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant UNISWAP_V3_QUOTER_V2 = 0x61fFE014bA17989E743c5F6cB21bF9697530B21e;
    address constant UNISWAP_V3_POSITION_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;

    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    int24 internal constant MIN_TICK = -807272;
    int24 internal constant MAX_TICK = -MIN_TICK;

    Swapper public swapper;
    IERC20 public weth;
    IERC20 public usdt;
    INonfungiblePositionManager public positionManager;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer address:", deployer);
        console.log("Deployer ETH balance:", deployer.balance / 1e18);

        vm.startBroadcast(deployerPrivateKey);

        swapper = new Swapper(UNISWAP_V3_SWAP_ROUTER, UNISWAP_V3_QUOTER_V2, UNISWAP_V3_POSITION_MANAGER);
        console.log("Swapper deployed at:", address(swapper));
        console.log("SwapRouter:", swapper.getSwapRouter());

        weth = IERC20(WETH);
        usdt = IERC20(USDT);
        positionManager = INonfungiblePositionManager(UNISWAP_V3_POSITION_MANAGER);

        prepareTokens(deployer);

        testSwaps(deployer);

        testLiquidity(deployer);

        displaySummary(deployer);

        vm.stopBroadcast();
    }

    function prepareTokens(address deployer) internal {
        uint256 ethToWrap = 200 ether;
        console.log("Wrapping", ethToWrap / 1e18, "ETH to WETH...");
        IWETH9(WETH).deposit{value: ethToWrap}();

        uint256 wethBalance = weth.balanceOf(deployer);
        console.log("WETH balance:", wethBalance / 1e18, "WETH");

        uint256 swapAmount = 100 ether;
        weth.approve(address(swapper), swapAmount);

        console.log("Swapping", swapAmount / 1e18, "WETH to USDT...");
        swapper.swapExactInputSingle(WETH, USDT, deployer, block.timestamp + 1 hours, swapAmount, 0, 0);

        uint256 usdtBalance = usdt.balanceOf(deployer);
        console.log("USDT balance:", usdtBalance / 1e6, "USDT");
    }

    function testSwaps(address deployer) internal {
        console.log("\n[Swap Test 1] Exact Input: WETH -> USDT");
        uint256 amountIn = 1 ether;
        uint256 wethBefore = weth.balanceOf(deployer);
        uint256 usdtBefore = usdt.balanceOf(deployer);

        weth.approve(address(swapper), amountIn);

        vm.recordLogs();

        (uint256 amountOut, uint24 optimalFee) =
            swapper.swapExactInputSingle(WETH, USDT, deployer, block.timestamp + 1 hours, amountIn, 0, 0);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        displaySwapEvents(logs);

        uint256 wethAfter = weth.balanceOf(deployer);
        uint256 usdtAfter = usdt.balanceOf(deployer);

        console.log("WETH before:", wethBefore, "WEI");
        console.log("WETH after:", wethAfter, "WEI");
        console.log("USDT before:", usdtBefore, "USDT with 6 decimals");
        console.log("USDT after:", usdtAfter, "USDT with 6 decimals");
        console.log("Optimal Fee:", optimalFee);
        console.log("Amount Out:", amountOut, "WEI");

        console.log("\n[Swap Test 2] Exact Output: WETH -> USDT");
        uint256 exactAmountOut = 3000 * 1e6;
        uint256 maxAmountIn = 1 ether;

        weth.approve(address(swapper), maxAmountIn);
        wethBefore = weth.balanceOf(deployer);
        usdtBefore = usdt.balanceOf(deployer);

        vm.recordLogs();

        (uint256 amountInUsed, uint24 optimalFee2) = swapper.swapExactOutputSingle(
            WETH, USDT, deployer, block.timestamp + 1 hours, exactAmountOut, maxAmountIn, 0
        );

        displaySwapEvents(vm.getRecordedLogs());

        wethAfter = weth.balanceOf(deployer);
        usdtAfter = usdt.balanceOf(deployer);

        console.log("WETH before:", wethBefore, "WEI");
        console.log("WETH after:", wethAfter, "WEI");
        console.log("USDT before:", usdtBefore, "USDT with 6 decimals");
        console.log("USDT after:", usdtAfter, "USDT with 6 decimals");
        console.log("Refunded WETH:", (maxAmountIn - amountInUsed), "WEI");
        console.log("Optimal Fee:", optimalFee2);

        console.log("\n[Swap Test 3] Updating Slippage Tolerance");
        uint256 oldTolerance = swapper.getUserSlippageTolerance(deployer);
        uint256 newTolerance = 300; // 3%

        vm.recordLogs();
        swapper.setSlippageTolerance(newTolerance);
        displaySlippageEvent(vm.getRecordedLogs());

        console.log("  Old tolerance:", oldTolerance , "bps");
        console.log("  New tolerance:", swapper.getUserSlippageTolerance(deployer), "bps");
    }

    function displaySwapEvents(Vm.Log[] memory logs) internal pure {
        console.log("\n  [Events Emitted]");

        for (uint256 i = 0; i < logs.length; i++) {
            bytes32 eventSig = logs[i].topics[0];

            bytes32 exactInputSig = keccak256("ExactInputSwapExecuted(address,address,uint256,uint256,address)");
            bytes32 exactOutputSig = keccak256("ExactOutputSwapExecuted(address,address,uint256,uint256,address)");
            bytes32 optimalPoolSig = keccak256("OptimalPoolSelected(address,address,uint24,uint256)");

            if (eventSig == exactInputSig) {
                address tokenIn = address(uint160(uint256(logs[i].topics[1])));
                address tokenOut = address(uint160(uint256(logs[i].topics[2])));
                address recipient = address(uint160(uint256(logs[i].topics[3])));
                (uint256 amountIn, uint256 amountOut) = abi.decode(logs[i].data, (uint256, uint256));

                console.log("    [EVENT] ExactInputSwapExecuted");
                console.log("      TokenIn:", tokenIn);
                console.log("      TokenOut:", tokenOut);
                console.log("      AmountIn:", amountIn);
                console.log("      AmountOut:", amountOut);
                console.log("      Recipient:", recipient);
            } else if (eventSig == exactOutputSig) {
                address tokenIn = address(uint160(uint256(logs[i].topics[1])));
                address tokenOut = address(uint160(uint256(logs[i].topics[2])));
                address recipient = address(uint160(uint256(logs[i].topics[3])));
                (uint256 amountIn, uint256 amountOut) = abi.decode(logs[i].data, (uint256, uint256));

                console.log("    [EVENT] ExactOutputSwapExecuted");
                console.log("      TokenIn:", tokenIn);
                console.log("      TokenOut:", tokenOut);
                console.log("      AmountIn:", amountIn);
                console.log("      AmountOut:", amountOut);
                console.log("      Recipient:", recipient);
            } else if (eventSig == optimalPoolSig) {
                address tokenIn = address(uint160(uint256(logs[i].topics[1])));
                address tokenOut = address(uint160(uint256(logs[i].topics[2])));
                (uint24 selectedFee, uint256 amountOut) = abi.decode(logs[i].data, (uint24, uint256));

                console.log("    [EVENT] OptimalPoolSelected");
                console.log("      TokenIn:", tokenIn);
                console.log("      TokenOut:", tokenOut);
                console.log("      Selected Fee:", selectedFee);
                console.log("      Expected AmountOut:", amountOut);
            }
        }
    }

    function displaySlippageEvent(Vm.Log[] memory logs) internal pure {
        console.log("\n  [Events Emitted]");

        bytes32 slippageSig = keccak256("SlippageToleranceUpdated(address,uint256,uint256)");

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == slippageSig) {
                address user = address(uint160(uint256(logs[i].topics[1])));
                (uint256 oldTolerance, uint256 newTolerance) = abi.decode(logs[i].data, (uint256, uint256));

                console.log("    [EVENT] SlippageToleranceUpdated");
                console.log("      User:", user);
                console.log("      Old Tolerance:", oldTolerance / 1e2, "percentage");
                console.log("      New Tolerance:", newTolerance / 1e2, "percentage");
            }
        }
    }

    function displaySummary(address deployer) internal view {
        console.log("\n=== Contract Statistics ===");
        console.log("Total Swaps:", swapper.totalSwaps());
        console.log("Total Liquidity Actions:", swapper.totalLiquidityActions());
        console.log("User Swap Count:", swapper.getUserSwapCount(deployer));
        console.log("User Liquidity Action Count:", swapper.getUserLiquidityActionCount(deployer));

        console.log("\n=== Final Balances ===");
        console.log("WETH:", weth.balanceOf(deployer) / 1e18, "WETH");
        console.log("USDT:", usdt.balanceOf(deployer) / 1e6, "USDT");
        console.log("ETH:", deployer.balance / 1e18, "ETH");

        if (swapper.getUserSwapCount(deployer) > 0) {
            console.log("\n=== Last Swap ===");
            Swapper.SwapAction memory lastSwap = swapper.getUserLastSwap(deployer);
            console.log("TokenIn:", lastSwap.tokenIn);
            console.log("TokenOut:", lastSwap.tokenOut);
            console.log("AmountIn:", lastSwap.amountIn);
            console.log("AmountOut:", lastSwap.amountOut);
            console.log("Fee:", lastSwap.fee);
            console.log("IsExactInput:", lastSwap.isExactInput);
            console.log("Timestamp:", lastSwap.timestamp);
            console.log("BlockNumber:", lastSwap.blockNumber);
        }
    }

    function testLiquidity(address deployer) internal {
        console.log("\nCreating New Position");

        vm.recordLogs();
        uint256 amount0ToMint = 50e18;
        uint256 amount1ToMint = 50e6;

        TransferHelper.safeApprove(WETH, address(positionManager), 0);
        TransferHelper.safeApprove(WETH, address(positionManager), amount0ToMint);

        TransferHelper.safeApprove(USDT, address(positionManager), 0);
        TransferHelper.safeApprove(USDT, address(positionManager), amount1ToMint);

        (uint256 tokenId, uint128 startLiquidity,,) = positionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: WETH,
                token1: USDT,
                fee: 100,
                tickLower: MIN_TICK,
                tickUpper: MAX_TICK,
                amount0Desired: amount0ToMint,
                amount1Desired: amount1ToMint,
                amount0Min: 0,
                amount1Min: 0,
                recipient: deployer,
                deadline: block.timestamp + 1 hours
            })
        );

        console.log("Token ID:", tokenId);
        console.log("Start liquidity:", startLiquidity);

        uint256 amount0ToAdd = 80e18;
        uint256 amount1ToAdd = 80e6;

        TransferHelper.safeApprove(WETH, address(swapper), 0);
        TransferHelper.safeApprove(WETH, address(swapper), amount0ToAdd);

        TransferHelper.safeApprove(USDT, address(swapper), 0);
        TransferHelper.safeApprove(USDT, address(swapper), amount1ToAdd);

        // Increase liquidity using Swapper
        (uint128 newLiquidity, uint256 addedAmount0, uint256 addedAmount1) =
            swapper.increaseLiquidity(tokenId, amount0ToAdd, amount1ToAdd, 0, 0, block.timestamp + 1 hours);

        console.log("Added liquidity:", newLiquidity);
        console.log("Added amount0:", addedAmount0);
        console.log("Added amount1:", addedAmount1);

        uint128 liquidityToRemove = newLiquidity - startLiquidity;
        console.log("\nLiquidity to remove:", liquidityToRemove);

        positionManager.approve(address(swapper), tokenId);

        (uint256 removedAmount0, uint256 removedAmount1) =
            swapper.decreaseLiquidity(tokenId, liquidityToRemove, 0, 0, block.timestamp + 1 hours);

        console.log("Removed amount0:", removedAmount0);
        console.log("Removed amount1:", removedAmount1);

        // Display liquidity events
        Vm.Log[] memory logs = vm.getRecordedLogs();
        displayLiquidityEvents(logs);
    }

    function displayLiquidityEvents(Vm.Log[] memory logs) internal pure {
        console.log("\n  [Events Emitted]");

        bytes32 increaseSig = keccak256("LiquidityIncreased(uint256,uint128,uint256,uint256)");
        bytes32 decreaseSig = keccak256("LiquidityDecreased(uint256,uint128,uint256,uint256)");

        for (uint256 i = 0; i < logs.length; i++) {
            bytes32 eventSig = logs[i].topics[0];

            if (eventSig == increaseSig) {
                uint256 tokenId = uint256(logs[i].topics[1]);
                (uint128 liquidity, uint256 amount0, uint256 amount1) =
                    abi.decode(logs[i].data, (uint128, uint256, uint256));

                console.log("    [EVENT] LiquidityIncreased");
                console.log("      TokenId:", tokenId);
                console.log("      Liquidity:", liquidity);
                console.log("      Amount0:", amount0);
                console.log("      Amount1:", amount1);
            } else if (eventSig == decreaseSig) {
                uint256 tokenId = uint256(logs[i].topics[1]);
                (uint128 liquidity, uint256 amount0, uint256 amount1) =
                    abi.decode(logs[i].data, (uint128, uint256, uint256));

                console.log("    [EVENT] LiquidityDecreased");
                console.log("      TokenId:", tokenId);
                console.log("      Liquidity:", liquidity);
                console.log("      Amount0:", amount0);
                console.log("      Amount1:", amount1);
            }
        }
    }
}
