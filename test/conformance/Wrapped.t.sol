// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IAgentRegistry} from "../../src/IAgentRegistry.sol";
import {AgentWrapped721} from "../../src/AgentWrapped721.sol";
import {ERC721AgentOnlyConformance} from "./ERC721AgentOnlyConformance.sol";

contract OpenNft is ERC721("Open", "OPN") {
    uint256 public lastId;

    function mint() external returns (uint256 id) {
        id = ++lastId;
        _mint(msg.sender, id);
    }
}

/// Our wrapper of an existing NFT passes the suite too: wrapping is the mint, unwrapping the burn.
contract WrappedConformanceTest is ERC721AgentOnlyConformance {
    OpenNft internal original;

    function _deploy(IAgentRegistry r) internal override returns (address) {
        original = new OpenNft();
        return address(new AgentWrapped721(IERC721(address(original)), r, true, "Wrapped", "WRP"));
    }

    function _mintToSelf(address who) internal override returns (uint256 id) {
        id = original.mint();
        original.approve(address(token), id);
        uint256[] memory ids = new uint256[](1);
        ids[0] = id;
        AgentWrapped721(address(token)).depositFor(who, ids);
    }

    function _hasBurn() internal pure override returns (bool) {
        return true;
    }

    function _burn(address who, uint256 id) internal override {
        uint256[] memory ids = new uint256[](1);
        ids[0] = id;
        AgentWrapped721(address(token)).withdrawTo(who, ids);
    }
}
