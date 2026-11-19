// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IAgentRegistry} from "../../src/IAgentRegistry.sol";
import {IERC1155AgentOnly} from "../../src/IERC1155AgentOnly.sol";
import {ConformanceRegistry} from "./ERC721AgentOnlyConformance.sol";

/// Conformance suite for the ERC-1155 profile of the draft: the same rules as for ERC-721, for
/// single and batch movements, with `setApprovalForAll` as the only grant. An implementation
/// fills in `_deploy` and `_mintToSelf(who, amount)`, which makes `who` mint `amount` units of a
/// new id to itself; the suite has already set `who` as the caller. `_hasBurn` and
/// `_burn(operator, holder, id, amount)` are optional.
abstract contract ERC1155AgentOnlyConformance is Test {
    ConformanceRegistry internal reg;
    IERC1155 internal token;

    address internal constant ALICE = address(0xA11CE); // agent
    address internal constant BOB = address(0xB0B); // agent
    address internal constant VENUE = address(0x7E0E); // approved venue
    address internal constant HUMAN = address(0x4A3A); // neither

    function _deploy(IAgentRegistry registry) internal virtual returns (address);

    function _mintToSelf(address who, uint256 amount) internal virtual returns (uint256);

    function _hasBurn() internal view virtual returns (bool) {
        return false;
    }

    /// `operator` burns `amount` of `holder`'s `id` (the operator may be the holder); the suite has
    /// already set `operator` as the caller. Only called when `_hasBurn()`.
    function _burn(address operator, address holder, uint256 id, uint256 amount) internal virtual {}

    function setUp() public virtual {
        reg = new ConformanceRegistry();
        reg.setAgent(ALICE, true);
        reg.setAgent(BOB, true);
        reg.setVenue(VENUE, true);
        token = IERC1155(_deploy(reg));
    }

    function _mintAs(address who, uint256 amount) internal returns (uint256) {
        return this.mintAs(who, amount);
    }

    /// External, so that a revert anywhere in a hook of several calls reverts the whole step.
    function mintAs(address who, uint256 amount) external returns (uint256 id) {
        vm.startPrank(who);
        id = _mintToSelf(who, amount);
        vm.stopPrank();
    }

    function burnAs(address who, uint256 id, uint256 amount) external {
        vm.startPrank(who);
        _burn(who, who, id, amount);
        vm.stopPrank();
    }

    function _one(uint256 v) internal pure returns (uint256[] memory a) {
        a = new uint256[](1);
        a[0] = v;
    }

    function _two(uint256 x, uint256 y) internal pure returns (uint256[] memory a) {
        a = new uint256[](2);
        (a[0], a[1]) = (x, y);
    }

    // ----- Interface

    function test_AdvertisesTheInterfacesAndItsRegistry() public view {
        IERC165 t = IERC165(address(token));
        assertTrue(t.supportsInterface(type(IERC1155AgentOnly).interfaceId), "IERC1155AgentOnly");
        assertEq(type(IERC1155AgentOnly).interfaceId, bytes4(0x0d1cfcae));
        assertTrue(t.supportsInterface(type(IERC1155).interfaceId), "IERC1155");
        assertTrue(t.supportsInterface(type(IERC165).interfaceId), "IERC165");
        assertEq(address(IERC1155AgentOnly(address(token)).agentRegistry()), address(reg));
    }

    function test_BehavesAsAnErc1155BetweenAgents() public {
        uint256 a = _mintAs(ALICE, 10);
        uint256 b = _mintAs(ALICE, 5);
        assertEq(token.balanceOf(ALICE, a), 10);
        vm.prank(ALICE);
        token.setApprovalForAll(BOB, true);
        vm.prank(BOB);
        token.safeTransferFrom(ALICE, BOB, a, 4, "");
        vm.prank(BOB);
        token.safeBatchTransferFrom(ALICE, BOB, _two(a, b), _two(1, 5), "");
        assertEq(token.balanceOf(ALICE, a), 5);
        assertEq(token.balanceOf(BOB, a), 5);
        assertEq(token.balanceOf(BOB, b), 5);
    }

    // ----- Rule 2

    function test_AHumanCannotMint() public {
        vm.expectRevert();
        this.mintAs(HUMAN, 1);
    }

    function test_AnAgentThatStopsBeingRecognisedCannotPull() public {
        uint256 id = _mintAs(ALICE, 3);
        vm.prank(ALICE);
        token.setApprovalForAll(BOB, true);
        reg.setAgent(BOB, false);
        vm.prank(BOB);
        vm.expectRevert();
        token.safeTransferFrom(ALICE, BOB, id, 1, "");
        assertEq(token.balanceOf(ALICE, id), 3);
    }

    // ----- Rule 3

    function test_EvenAVenueCannotSendToAHuman() public {
        uint256 id = _mintAs(ALICE, 3);
        vm.prank(ALICE);
        token.setApprovalForAll(VENUE, true);
        vm.prank(VENUE);
        vm.expectRevert();
        token.safeTransferFrom(ALICE, HUMAN, id, 1, "");
        vm.prank(VENUE);
        vm.expectRevert();
        token.safeBatchTransferFrom(ALICE, HUMAN, _one(id), _one(1), "");
        assertEq(token.balanceOf(HUMAN, id), 0);
    }

    function testFuzz_NoUnrecognisedAccountEverReceives(address anyone) public {
        vm.assume(anyone != address(0) && anyone.code.length == 0);
        vm.assume(!reg.isAgent(anyone) && !reg.isVenue(anyone));
        uint256 id = _mintAs(ALICE, 3);
        vm.prank(ALICE);
        token.setApprovalForAll(VENUE, true);
        vm.prank(VENUE);
        vm.expectRevert();
        token.safeTransferFrom(ALICE, anyone, id, 1, "");
        vm.prank(ALICE);
        vm.expectRevert();
        token.safeTransferFrom(ALICE, anyone, id, 1, "");
        assertEq(token.balanceOf(anyone, id), 0);
    }

    // ----- Rule 4

    function test_AnAgentCannotPushToAnotherAgent() public {
        uint256 id = _mintAs(ALICE, 3);
        vm.prank(ALICE);
        vm.expectRevert();
        token.safeTransferFrom(ALICE, BOB, id, 1, "");
        vm.prank(ALICE);
        vm.expectRevert();
        token.safeBatchTransferFrom(ALICE, BOB, _one(id), _one(1), "");
        assertEq(token.balanceOf(BOB, id), 0);
    }

    function test_AnApprovedOperatorCannotPushToAThirdAgent() public {
        address carol = address(0xCA401);
        reg.setAgent(carol, true);
        uint256 id = _mintAs(ALICE, 3);
        vm.prank(ALICE);
        token.setApprovalForAll(BOB, true);
        vm.prank(BOB);
        vm.expectRevert();
        token.safeTransferFrom(ALICE, carol, id, 1, "");
        assertEq(token.balanceOf(carol, id), 0);
    }

    function test_AVenueDeliversAndHolds() public {
        uint256 id = _mintAs(ALICE, 3);
        vm.prank(ALICE);
        token.setApprovalForAll(VENUE, true);
        vm.prank(VENUE);
        token.safeTransferFrom(ALICE, BOB, id, 1, ""); // a sale delivered by the venue
        vm.prank(VENUE);
        token.safeTransferFrom(ALICE, VENUE, id, 2, ""); // escrow
        vm.prank(VENUE);
        token.safeTransferFrom(VENUE, BOB, id, 2, ""); // released
        assertEq(token.balanceOf(BOB, id), 3);
    }

    // ----- Rule 5

    function test_AHumanCannotBeApproved() public {
        _mintAs(ALICE, 1);
        vm.prank(ALICE);
        vm.expectRevert();
        token.setApprovalForAll(HUMAN, true);
        assertFalse(token.isApprovedForAll(ALICE, HUMAN));
    }

    function test_ClearingAnApprovalAlwaysWorks() public {
        vm.prank(ALICE);
        token.setApprovalForAll(BOB, true);
        reg.setAgent(ALICE, false);
        reg.setAgent(BOB, false);
        vm.prank(ALICE);
        token.setApprovalForAll(BOB, false);
        assertFalse(token.isApprovedForAll(ALICE, BOB));
    }

    function test_AnUnrecognisedOwnerCannotGrantAnApproval() public {
        reg.setAgent(ALICE, false);
        vm.prank(ALICE);
        vm.expectRevert();
        token.setApprovalForAll(BOB, true);
        assertFalse(token.isApprovedForAll(ALICE, BOB));
    }

    // ----- Rule 7

    function test_AnUnrecognisedHoldersTokensDoNotMove() public {
        uint256 id = _mintAs(ALICE, 3);
        vm.prank(ALICE);
        token.setApprovalForAll(VENUE, true);
        vm.prank(ALICE);
        token.setApprovalForAll(BOB, true);
        reg.setAgent(ALICE, false);
        vm.prank(BOB);
        vm.expectRevert();
        token.safeTransferFrom(ALICE, BOB, id, 1, "");
        vm.prank(VENUE);
        vm.expectRevert();
        token.safeBatchTransferFrom(ALICE, BOB, _one(id), _one(1), "");
        assertEq(token.balanceOf(ALICE, id), 3);
        reg.setAgent(ALICE, true); // recognised again: the tokens move
        vm.prank(BOB);
        token.safeTransferFrom(ALICE, BOB, id, 3, "");
        assertEq(token.balanceOf(BOB, id), 3);
    }

    function test_AnUnrecognisedHolderCannotBurn() public {
        if (!_hasBurn()) return;
        uint256 id = _mintAs(ALICE, 3);
        reg.setAgent(ALICE, false);
        vm.expectRevert();
        this.burnAs(ALICE, id, 1);
        assertEq(token.balanceOf(ALICE, id), 3);
    }

    /// Rule 2 alone stops this one: the holder is recognised and a burn has no recipient.
    function test_AnOperatorThatStopsBeingRecognisedCannotBurn() public {
        if (!_hasBurn()) return;
        uint256 id = _mintAs(ALICE, 3);
        vm.prank(ALICE);
        token.setApprovalForAll(BOB, true);
        reg.setAgent(BOB, false);
        vm.expectRevert();
        this.burnFrom(BOB, ALICE, id, 1);
        assertEq(token.balanceOf(ALICE, id), 3);
    }

    function test_ARecognisedHolderCanBurn() public {
        if (!_hasBurn()) return;
        uint256 id = _mintAs(ALICE, 3);
        this.burnAs(ALICE, id, 2);
        assertEq(token.balanceOf(ALICE, id), 1);
    }

    /// `operator` burns `amount` of `holder`'s `id`. Only reached when `_hasBurn()`.
    function burnFrom(address operator, address holder, uint256 id, uint256 amount) external {
        vm.startPrank(operator);
        _burn(operator, holder, id, amount);
        vm.stopPrank();
    }
}
