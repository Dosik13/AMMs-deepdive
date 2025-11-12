// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

contract MockFactory is IUniswapV3Factory {
    mapping(address => mapping(address => mapping(uint24 => address))) public getPool;

    function setPool(address token0, address token1, uint24 fee, address pool) external {
        getPool[token0][token1][fee] = pool;
        getPool[token1][token0][fee] = pool;
    }

    // Unimplemented required functions
    function owner() external pure returns (address) {
        return address(0);
    }

    function feeAmountTickSpacing(uint24) external pure returns (int24) {
        return 0;
    }

    function createPool(address, address, uint24) external pure returns (address) {
        return address(0);
    }

    function setOwner(address) external pure {}

    function enableFeeAmount(uint24, int24) external pure {}
}
