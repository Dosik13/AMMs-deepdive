// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IPeripheryImmutableState} from "@uniswap/v3-periphery/contracts/interfaces/IPeripheryImmutableState.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "./MockERC20.sol";

contract MockSwapRouter is ISwapRouter, IPeripheryImmutableState {
    address public immutable factory;
    address public immutable WETH9;
    uint256 public mockAmountOut = 1000e18;
    uint256 public mockAmountIn = 1e18;

    constructor(address _factory) {
        factory = _factory;
        WETH9 = address(0);
    }

    function setMockAmountOut(uint256 amount) external {
        mockAmountOut = amount;
    }

    function setMockAmountIn(uint256 amount) external {
        mockAmountIn = amount;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut) {
        IERC20(params.tokenIn).transferFrom(msg.sender, address(this), params.amountIn);

        MockERC20(params.tokenOut).mint(params.recipient, mockAmountOut);

        return mockAmountOut;
    }

    function exactOutputSingle(ExactOutputSingleParams calldata params) external payable returns (uint256 amountIn) {
        IERC20(params.tokenIn).transferFrom(msg.sender, address(this), mockAmountIn);

        MockERC20(params.tokenOut).mint(params.recipient, params.amountOut);

        return mockAmountIn;
    }

    function exactInput(ExactInputParams calldata) external payable returns (uint256) {
        return 0;
    }

    function exactOutput(ExactOutputParams calldata) external payable returns (uint256) {
        return 0;
    }

    function uniswapV3SwapCallback(int256, int256, bytes calldata) external pure {}
}
