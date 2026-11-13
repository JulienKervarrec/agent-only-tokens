// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IAgentRegistry} from "./IAgentRegistry.sol";
import {AgentWrapped721} from "./AgentWrapped721.sol";

// The two Uniswap V3 functions the wrapper needs. Signatures copied from the npm package
// uniswap v3-periphery, interfaces/INonfungiblePositionManager.sol.
interface IUniV3Positions {
    struct DecreaseLiquidityParams {
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }

    function decreaseLiquidity(DecreaseLiquidityParams calldata params)
        external
        payable
        returns (uint256 amount0, uint256 amount1);

    function collect(CollectParams calldata params) external payable returns (uint256 amount0, uint256 amount1);
}

/// @title Agent-only Uniswap V3 liquidity positions.
/// @notice Unaudited draft. The position never leaves: its holder manages it through
/// this contract, and value only leaves as fungible tokens, to the holder's account.
/// @dev Adding liquidity is done directly on Uniswap, which allows anyone to do it.
contract AgentWrappedUniV3 is AgentWrapped721 {
    error NotAuthorized();

    constructor(IERC721 positionManager, IAgentRegistry registry_)
        AgentWrapped721(positionManager, registry_, false, "Agent-Only Uniswap V3 Positions", "AO-UNI-V3")
    {}

    modifier onlyHolder(uint256 tokenId) {
        if (!_isAuthorized(_requireOwned(tokenId), msg.sender, tokenId)) revert NotAuthorized();
        _;
    }

    /// Removes liquidity. The tokens become owed to the position; `collect` pays them out.
    function decreaseLiquidity(uint256 tokenId, uint128 liquidity, uint256 amount0Min, uint256 amount1Min, uint256 deadline)
        external
        onlyHolder(tokenId)
        returns (uint256, uint256)
    {
        return IUniV3Positions(address(underlying())).decreaseLiquidity(
            IUniV3Positions.DecreaseLiquidityParams(tokenId, liquidity, amount0Min, amount1Min, deadline)
        );
    }

    /// Pays the holder the fees and tokens owed to the position.
    function collect(uint256 tokenId) external onlyHolder(tokenId) returns (uint256, uint256) {
        return IUniV3Positions(address(underlying())).collect(
            IUniV3Positions.CollectParams(tokenId, msg.sender, type(uint128).max, type(uint128).max)
        );
    }
}
