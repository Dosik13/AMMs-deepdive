// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "./MockERC20.sol";

contract MockPositionManager is INonfungiblePositionManager {
    uint256 public nextTokenId = 1;
    mapping(uint256 => address) public ownerOf;
    mapping(uint256 => Position) public positions;

    struct Position {
        uint96 nonce;
        address operator;
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint256 feeGrowthInside0LastX128;
        uint256 feeGrowthInside1LastX128;
        uint128 tokensOwed0;
        uint128 tokensOwed1;
    }

    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        tokenId = nextTokenId++;
        liquidity = 1000e18;
        amount0 = params.amount0Desired;
        amount1 = params.amount1Desired;

        ownerOf[tokenId] = params.recipient;
        positions[tokenId] = Position({
            nonce: 0,
            operator: address(0),
            token0: params.token0,
            token1: params.token1,
            fee: params.fee,
            tickLower: params.tickLower,
            tickUpper: params.tickUpper,
            liquidity: liquidity,
            feeGrowthInside0LastX128: 0,
            feeGrowthInside1LastX128: 0,
            tokensOwed0: 0,
            tokensOwed1: 0
        });

        if (amount0 > 0) {
            IERC20(params.token0).transferFrom(msg.sender, address(this), amount0);
        }
        if (amount1 > 0) {
            IERC20(params.token1).transferFrom(msg.sender, address(this), amount1);
        }

        return (tokenId, liquidity, amount0, amount1);
    }

    function increaseLiquidity(IncreaseLiquidityParams calldata params)
        external
        payable
        returns (uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        Position storage pos = positions[params.tokenId];
        liquidity = 500e18;
        amount0 = params.amount0Desired;
        amount1 = params.amount1Desired;

        pos.liquidity += liquidity;

        if (amount0 > 0) {
            IERC20(pos.token0).transferFrom(msg.sender, address(this), amount0);
        }
        if (amount1 > 0) {
            IERC20(pos.token1).transferFrom(msg.sender, address(this), amount1);
        }

        return (liquidity, amount0, amount1);
    }

    function decreaseLiquidity(DecreaseLiquidityParams calldata params)
        external
        payable
        returns (uint256 amount0, uint256 amount1)
    {
        Position storage pos = positions[params.tokenId];
        require(pos.liquidity >= params.liquidity, "Insufficient liquidity");

        pos.liquidity -= params.liquidity;
        amount0 = 100e18;
        amount1 = 100e18;

        pos.tokensOwed0 += uint128(amount0);
        pos.tokensOwed1 += uint128(amount1);

        return (amount0, amount1);
    }

    function collect(CollectParams calldata params) external payable returns (uint256 amount0, uint256 amount1) {
        Position storage pos = positions[params.tokenId];
        amount0 = pos.tokensOwed0;
        amount1 = pos.tokensOwed1;

        pos.tokensOwed0 = 0;
        pos.tokensOwed1 = 0;

        MockERC20(pos.token0).mint(params.recipient, amount0);
        MockERC20(pos.token1).mint(params.recipient, amount1);

        return (amount0, amount1);
    }

    function burn(uint256 tokenId) external payable {
        require(positions[tokenId].liquidity == 0, "Position has liquidity");
        delete positions[tokenId];
        delete ownerOf[tokenId];
    }

    function name() external pure returns (string memory) {
        return "Mock Position";
    }

    function symbol() external pure returns (string memory) {
        return "MPOS";
    }

    function tokenURI(uint256) external pure returns (string memory) {
        return "";
    }

    function baseURI() external pure returns (string memory) {
        return "";
    }

    function tokenByIndex(uint256) external pure returns (uint256) {
        return 0;
    }

    function tokenOfOwnerByIndex(address, uint256) external pure returns (uint256) {
        return 0;
    }

    function totalSupply() external pure returns (uint256) {
        return 0;
    }

    function balanceOf(address) external pure returns (uint256) {
        return 0;
    }

    function safeTransferFrom(address, address, uint256) external pure {}

    function safeTransferFrom(address, address, uint256, bytes calldata) external pure {}

    function transferFrom(address, address, uint256) external pure {}

    function approve(address, uint256) external pure {}

    function setApprovalForAll(address, bool) external pure {}

    function getApproved(uint256) external pure returns (address) {
        return address(0);
    }

    function isApprovedForAll(address, address) external pure returns (bool) {
        return false;
    }

    function permit(address, uint256, uint256, uint8, bytes32, bytes32) external payable {}

    function DOMAIN_SEPARATOR() external pure returns (bytes32) {
        return bytes32(0);
    }

    function PERMIT_TYPEHASH() external pure returns (bytes32) {
        return bytes32(0);
    }

    function supportsInterface(bytes4) external pure returns (bool) {
        return true;
    }

    function createAndInitializePoolIfNecessary(address, address, uint24, uint160) external payable returns (address) {
        return address(0);
    }

    function multicall(bytes[] calldata) external payable returns (bytes[] memory) {
        bytes[] memory results;
        return results;
    }

    function refundETH() external payable {}

    function sweepToken(address, uint256, address) external payable {}

    function unwrapWETH9(uint256, address) external payable {}

    function wrapETH(uint256) external payable {}

    function pull(address, uint256) external payable {}

    function selfPermit(address, uint256, uint256, uint8, bytes32, bytes32) external payable {}

    function selfPermitIfNecessary(address, uint256, uint256, uint8, bytes32, bytes32) external payable {}

    function selfPermitAllowed(address, uint256, uint256, uint8, bytes32, bytes32) external payable {}

    function selfPermitAllowedIfNecessary(address, uint256, uint256, uint8, bytes32, bytes32) external payable {}

    function factory() external pure returns (address) {
        return address(0);
    }

    function WETH9() external pure returns (address) {
        return address(0);
    }
}
