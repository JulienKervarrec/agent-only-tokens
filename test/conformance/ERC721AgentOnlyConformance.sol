// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IAgentRegistry} from "../../src/IAgentRegistry.sol";
import {IERC721AgentOnly} from "../../src/IERC721AgentOnly.sol";

/// A registry for the suite alone: anyone can say who is an agent or a venue. It stands for any
/// real registry, so the suite depends on nothing but the two questions of the standard.
contract ConformanceRegistry is IAgentRegistry {
    mapping(address => bool) public isAgent;
    mapping(address => bool) public isVenue;

    function setAgent(address a, bool on) external {
        isAgent[a] = on;
    }

    function setVenue(address a, bool on) external {
        isVenue[a] = on;
    }
}

/// Conformance suite for the normative rules of the draft (study, section 3.8). Any
/// implementation runs it by inheriting this contract and filling in two hooks:
/// `_deploy` builds the token on the given registry, `_mintToSelf(who)` makes `who` mint one
/// token to itself; the suite has already set `who` as the caller with `vm.startPrank`.
/// `_hasBurn` and `_burn(who, id)` are optional.
/// The suite tests what the draft says, not how our implementation says it.
abstract contract ERC721AgentOnlyConformance is Test {
    ConformanceRegistry internal reg;
    IERC721 internal token;

    // Plain addresses with no code: the rules hold whatever the account is.
    address internal constant ALICE = address(0xA11CE); // agent
    address internal constant BOB = address(0xB0B); // agent
    address internal constant VENUE = address(0x7E0E); // approved venue
    address internal constant HUMAN = address(0x4A3A); // neither

    /// Deploys the token under test on `registry`.
    function _deploy(IAgentRegistry registry) internal virtual returns (address);

    /// `who` mints one token to itself; returns its id. Calls are already made as `who`.
    function _mintToSelf(address who) internal virtual returns (uint256);

    /// True if the token has a burn, done by `_burn`.
    function _hasBurn() internal view virtual returns (bool) {
        return false;
    }

    /// `who` burns `id`; calls are already made as `who`. Only called when `_hasBurn()`.
    function _burn(address who, uint256 id) internal virtual {}

    function setUp() public virtual {
        reg = new ConformanceRegistry();
        reg.setAgent(ALICE, true);
        reg.setAgent(BOB, true);
        reg.setVenue(VENUE, true);
        token = IERC721(_deploy(reg));
    }

    function _mintAs(address who) internal returns (uint256) {
        return this.mintAs(who);
    }

    /// External, so that a revert anywhere in a hook of several calls reverts the whole step.
    function mintAs(address who) external returns (uint256 id) {
        vm.startPrank(who);
        id = _mintToSelf(who);
        vm.stopPrank();
    }

    function burnAs(address who, uint256 id) external {
        vm.startPrank(who);
        _burn(who, id);
        vm.stopPrank();
    }

    // ----- Interface (rule 1, and the ERC-165 identifier)

    function test_AdvertisesTheInterfacesAndItsRegistry() public view {
        IERC165 t = IERC165(address(token));
        assertTrue(t.supportsInterface(type(IERC721AgentOnly).interfaceId), "IERC721AgentOnly");
        assertTrue(t.supportsInterface(type(IERC721).interfaceId), "IERC721");
        assertTrue(t.supportsInterface(type(IERC165).interfaceId), "IERC165");
        assertEq(address(IERC721AgentOnly(address(token)).agentRegistry()), address(reg));
    }

    function test_BehavesAsAnErc721BetweenAgents() public {
        uint256 id = _mintAs(ALICE);
        assertEq(token.ownerOf(id), ALICE);
        assertEq(token.balanceOf(ALICE), 1);
        vm.prank(ALICE);
        token.approve(BOB, id);
        assertEq(token.getApproved(id), BOB);
        vm.prank(BOB);
        token.transferFrom(ALICE, BOB, id);
        assertEq(token.ownerOf(id), BOB);
        vm.prank(BOB);
        token.setApprovalForAll(ALICE, true);
        assertTrue(token.isApprovedForAll(BOB, ALICE));
        vm.prank(ALICE);
        token.safeTransferFrom(BOB, ALICE, id);
        assertEq(token.ownerOf(id), ALICE);
    }

    // ----- Rule 2: the caller must be an agent or a venue

    function test_AHumanCannotMint() public {
        vm.expectRevert();
        this.mintAs(HUMAN);
        assertEq(token.balanceOf(HUMAN), 0);
    }

    function test_AnAgentThatStopsBeingRecognisedCannotPull() public {
        uint256 id = _mintAs(ALICE);
        vm.prank(ALICE);
        token.approve(BOB, id);
        reg.setAgent(BOB, false);
        vm.prank(BOB);
        vm.expectRevert();
        token.transferFrom(ALICE, BOB, id);
        assertEq(token.ownerOf(id), ALICE);
    }

    // ----- Rule 3: the recipient must be an agent or a venue

    function test_EvenAVenueCannotSendToAHuman() public {
        uint256 id = _mintAs(ALICE);
        vm.prank(ALICE);
        token.approve(VENUE, id);
        vm.prank(VENUE);
        vm.expectRevert();
        token.transferFrom(ALICE, HUMAN, id);
        vm.prank(VENUE);
        vm.expectRevert();
        token.safeTransferFrom(ALICE, HUMAN, id);
        assertEq(token.ownerOf(id), ALICE);
    }

    function testFuzz_NoUnrecognisedAccountEverReceives(address anyone) public {
        vm.assume(anyone != address(0) && anyone.code.length == 0);
        vm.assume(!reg.isAgent(anyone) && !reg.isVenue(anyone));
        uint256 id = _mintAs(ALICE);
        vm.prank(ALICE);
        token.setApprovalForAll(VENUE, true);
        vm.prank(VENUE);
        vm.expectRevert();
        token.transferFrom(ALICE, anyone, id);
        vm.prank(ALICE);
        vm.expectRevert();
        token.transferFrom(ALICE, anyone, id);
        assertEq(token.ownerOf(id), ALICE);
    }

    // ----- Rule 4: outside a venue, the recipient pulls

    function test_AnAgentCannotPushToAnotherAgent() public {
        uint256 id = _mintAs(ALICE);
        vm.prank(ALICE);
        vm.expectRevert();
        token.transferFrom(ALICE, BOB, id);
        vm.prank(ALICE);
        vm.expectRevert();
        token.safeTransferFrom(ALICE, BOB, id);
        assertEq(token.ownerOf(id), ALICE);
    }

    function test_AnApprovedOperatorCannotPushToAThirdAgent() public {
        address carol = address(0xCA401);
        reg.setAgent(carol, true);
        uint256 id = _mintAs(ALICE);
        vm.prank(ALICE);
        token.approve(BOB, id);
        vm.prank(BOB);
        vm.expectRevert();
        token.transferFrom(ALICE, carol, id);
        assertEq(token.ownerOf(id), ALICE);
    }

    function test_AVenueDeliversAndHolds() public {
        uint256 id = _mintAs(ALICE);
        vm.prank(ALICE);
        token.approve(VENUE, id);
        vm.prank(VENUE);
        token.transferFrom(ALICE, BOB, id); // a sale delivered by the venue
        assertEq(token.ownerOf(id), BOB);
        vm.prank(BOB);
        token.approve(VENUE, id);
        vm.prank(VENUE);
        token.transferFrom(BOB, VENUE, id); // escrow
        assertEq(token.ownerOf(id), VENUE);
        vm.prank(VENUE);
        token.transferFrom(VENUE, ALICE, id); // released
        assertEq(token.ownerOf(id), ALICE);
    }

    // ----- Rule 5: approvals

    function test_AHumanCannotBeApproved() public {
        uint256 id = _mintAs(ALICE);
        vm.prank(ALICE);
        vm.expectRevert();
        token.approve(HUMAN, id);
        vm.prank(ALICE);
        vm.expectRevert();
        token.setApprovalForAll(HUMAN, true);
    }

    function test_ClearingAnApprovalAlwaysWorks() public {
        uint256 id = _mintAs(ALICE);
        vm.startPrank(ALICE);
        token.approve(BOB, id);
        token.setApprovalForAll(BOB, true);
        vm.stopPrank();
        reg.setAgent(ALICE, false);
        reg.setAgent(BOB, false);
        vm.startPrank(ALICE);
        token.approve(address(0), id);
        token.setApprovalForAll(BOB, false);
        vm.stopPrank();
        assertEq(token.getApproved(id), address(0));
        assertFalse(token.isApprovedForAll(ALICE, BOB));
    }

    function test_AnUnrecognisedHolderCannotGrantAnApproval() public {
        uint256 id = _mintAs(ALICE);
        reg.setAgent(ALICE, false);
        vm.prank(ALICE);
        vm.expectRevert();
        token.approve(BOB, id);
        vm.prank(ALICE);
        vm.expectRevert();
        token.setApprovalForAll(BOB, true);
        assertEq(token.getApproved(id), address(0));
    }

    /// The holder counts too: an operator it approved cannot grant approvals while it is frozen.
    function test_AnOperatorOfAnUnrecognisedHolderCannotGrantAnApproval() public {
        uint256 id = _mintAs(ALICE);
        vm.prank(ALICE);
        token.setApprovalForAll(BOB, true);
        reg.setAgent(ALICE, false);
        vm.prank(BOB);
        vm.expectRevert();
        token.approve(VENUE, id);
        assertEq(token.getApproved(id), address(0));
    }

    // ----- Rule 7: an unrecognised holder's tokens do not move

    function test_AnUnrecognisedHoldersTokenDoesNotMove() public {
        uint256 id = _mintAs(ALICE);
        vm.prank(ALICE);
        token.setApprovalForAll(VENUE, true);
        vm.prank(ALICE);
        token.approve(BOB, id);
        reg.setAgent(ALICE, false); // frozen, expired or revoked
        vm.prank(BOB);
        vm.expectRevert();
        token.transferFrom(ALICE, BOB, id);
        vm.prank(VENUE);
        vm.expectRevert();
        token.transferFrom(ALICE, BOB, id);
        assertEq(token.ownerOf(id), ALICE);
        reg.setAgent(ALICE, true); // recognised again: the token moves
        vm.prank(BOB);
        token.transferFrom(ALICE, BOB, id);
        assertEq(token.ownerOf(id), BOB);
    }

    function test_AnUnrecognisedHolderCannotBurn() public {
        if (!_hasBurn()) return;
        uint256 id = _mintAs(ALICE);
        reg.setAgent(ALICE, false);
        vm.expectRevert();
        this.burnAs(ALICE, id);
        assertEq(token.ownerOf(id), ALICE);
    }

    /// Rule 2 alone stops this one: the holder is recognised and a burn has no recipient.
    function test_AnOperatorThatStopsBeingRecognisedCannotBurn() public {
        if (!_hasBurn()) return;
        uint256 id = _mintAs(ALICE);
        vm.prank(ALICE);
        token.approve(BOB, id);
        reg.setAgent(BOB, false);
        vm.expectRevert();
        this.burnAs(BOB, id);
        assertEq(token.ownerOf(id), ALICE);
    }

    function test_ARecognisedHolderCanBurn() public {
        if (!_hasBurn()) return;
        uint256 id = _mintAs(ALICE);
        this.burnAs(ALICE, id);
        assertEq(token.balanceOf(ALICE), 0);
    }
}
