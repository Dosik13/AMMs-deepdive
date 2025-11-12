// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IQuoterV2} from "@uniswap/v3-periphery/contracts/interfaces/IQuoterV2.sol";

contract MockQuoterV2 is IQuoterV2 {
    uint256 public mockAmountOut = 1000e18;
    uint256 public mockAmountIn = 1e18;

    function setMockAmountOut(uint256 amount) external {
        mockAmountOut = amount;
    }

    function setMockAmountIn(uint256 amount) external {
        mockAmountIn = amount;
    }

    function quoteExactInputSingle(QuoteExactInputSingleParams memory)
        external
        view
        returns (uint256 amountOut, uint160, uint32, uint256)
    {
        return (mockAmountOut, 0, 0, 0);
    }

    function quoteExactOutputSingle(QuoteExactOutputSingleParams memory)
        external
        view
        returns (uint256 amountIn, uint160, uint32, uint256)
    {
        return (mockAmountIn, 0, 0, 0);
    }

    function quoteExactInput(bytes memory, uint256)
        external
        pure
        returns (uint256, uint160[] memory, uint32[] memory, uint256)
    {
        uint160[] memory sqrtPriceX96AfterList;
        uint32[] memory initializedTicksCrossedList;
        return (0, sqrtPriceX96AfterList, initializedTicksCrossedList, 0);
    }

    function quoteExactOutput(bytes memory, uint256)
        external
        pure
        returns (uint256, uint160[] memory, uint32[] memory, uint256)
    {
        uint160[] memory sqrtPriceX96AfterList;
        uint32[] memory initializedTicksCrossedList;
        return (0, sqrtPriceX96AfterList, initializedTicksCrossedList, 0);
    }
}
