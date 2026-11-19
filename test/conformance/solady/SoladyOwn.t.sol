// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC721} from "solady/tokens/ERC721.sol";
import {IAgentRegistry} from "../../../src/IAgentRegistry.sol";
import {IERC721AgentOnly} from "../../../src/IERC721AgentOnly.sol";
import {SoladyAgentOnly} from "./SoladyAgentOnly.sol";
import {SoladyCollection} from "./SoladyCollection.sol";

contract MockRegistry is IAgentRegistry {
    mapping(address => bool) public agent;
    mapping(address => bool) public venue;
    bool public broken;

    function setAgent(address a, bool v) external {
        agent[a] = v;
    }

    function setVenue(address a, bool v) external {
        venue[a] = v;
    }

    function setBroken(bool v) external {
        broken = v;
    }

    function isAgent(address a) external view returns (bool) {
        require(!broken, "registry down");
        return agent[a];
    }

    function isVenue(address a) external view returns (bool) {
        require(!broken, "registry down");
        return venue[a];
    }
}

/// Test harness exposing internal Solady paths, to show they are still enforced (rule 6).
contract Harness is SoladyCollection {
    constructor(IAgentRegistry r) SoladyCollection(r) {}

    function mintTo(address to, uint256 id) external {
        _mint(to, id);
    }

    function safeMintTo(address to, uint256 id) external {
        _safeMint(to, id);
    }

    function mintExtra(address to, uint256 id) external {
        _mintAndSetExtraDataUnchecked(to, id, 7);
    }

    function rawTransfer(address from, address to, uint256 id) external {
        _transfer(from, to, id);
    }

    function rawBurn(uint256 id) external {
        _burn(id);
    }

    function rawApprove(address to, uint256 id) external {
        _approve(to, id);
    }

    function rawApproveAll(address owner, address op, bool v) external {
        _setApprovalForAll(owner, op, v);
    }

    function rawApproveBy(address by, address to, uint256 id) external {
        _approve(by, to, id);
    }

    function rawTransferBy(address by, address from, address to, uint256 id) external {
        _transfer(by, from, to, id);
    }
}

/// A venue contract: pulls tokens it is approved for, holds them, delivers them.
contract Venue {
    function pull(ERC721 t, address from, uint256 id) external {
        t.safeTransferFrom(from, address(this), id);
    }

    function deliver(ERC721 t, address to, uint256 id) external {
        t.safeTransferFrom(address(this), to, id);
    }

    function move(ERC721 t, address from, address to, uint256 id) external {
        t.transferFrom(from, to, id);
    }

    function burnIt(SoladyCollection t, uint256 id) external {
        t.burn(id);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}

/// A contract agent that pulls with safeTransferFrom.
contract AgentWallet {
    function pull(ERC721 t, address from, uint256 id) external {
        t.safeTransferFrom(from, address(this), id);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}

contract NoReceiver {
    function pull(ERC721 t, address from, uint256 id) external {
        t.safeTransferFrom(from, address(this), id);
    }
}

/// The second implementation's own tests, written by its author from the text of the proposal.
contract SoladyOwnTest is Test {
    MockRegistry reg;
    Harness tok;
    Venue venue;
    address alice = makeAddr("alice"); // agent
    address bob = makeAddr("bob"); // agent
    address carol = makeAddr("carol"); // agent, used as operator
    address human = makeAddr("human"); // never recognised

    function setUp() public {
        reg = new MockRegistry();
        tok = new Harness(reg);
        venue = new Venue();
        reg.setAgent(alice, true);
        reg.setAgent(bob, true);
        reg.setAgent(carol, true);
        reg.setVenue(address(venue), true);
    }

    function _mintAs(address who) internal returns (uint256 id) {
        vm.prank(who);
        id = tok.mint();
    }

    // ------------------------------------------------------------ Rule 1
    function test_rule1_supportsInterface() public view {
        assertTrue(tok.supportsInterface(type(IERC721AgentOnly).interfaceId));
        assertTrue(tok.supportsInterface(0x80ac58cd)); // ERC-721
        assertTrue(tok.supportsInterface(0x01ffc9a7)); // ERC-165
        assertTrue(tok.supportsInterface(0x5b5e139f)); // ERC-721 Metadata
        assertFalse(tok.supportsInterface(0xffffffff));
        assertEq(type(IERC721AgentOnly).interfaceId, IERC721AgentOnly.agentRegistry.selector);
    }

    function test_rule1_fullErc721Surface() public {
        uint256 id = _mintAs(alice);
        assertEq(tok.ownerOf(id), alice);
        assertEq(tok.balanceOf(alice), 1);
        assertEq(tok.getApproved(id), address(0));
        assertFalse(tok.isApprovedForAll(alice, bob));
        assertEq(tok.name(), "Agent Only");
        assertEq(tok.symbol(), "AGO");
        assertEq(tok.tokenURI(id), "agent-only://1");
    }

    // ------------------------------------------------------------ Rule 2
    function test_rule2_unrecognisedCannotMint() public {
        vm.prank(human);
        vm.expectRevert(abi.encodeWithSelector(SoladyAgentOnly.CallerNotRecognised.selector, human));
        tok.mint();
    }

    function test_rule2_operatorDerecognisedCannotBurn() public {
        uint256 id = _mintAs(alice);
        vm.prank(alice);
        tok.setApprovalForAll(carol, true);
        reg.setAgent(carol, false);
        vm.prank(carol);
        vm.expectRevert(abi.encodeWithSelector(SoladyAgentOnly.CallerNotRecognised.selector, carol));
        tok.burn(id);
    }

    function test_rule2_singleApprovedDerecognisedCannotBurnOrPull() public {
        uint256 id = _mintAs(alice);
        vm.prank(alice);
        tok.approve(carol, id);
        reg.setAgent(carol, false);
        vm.startPrank(carol);
        vm.expectRevert(abi.encodeWithSelector(SoladyAgentOnly.CallerNotRecognised.selector, carol));
        tok.burn(id);
        vm.expectRevert(abi.encodeWithSelector(SoladyAgentOnly.CallerNotRecognised.selector, carol));
        tok.transferFrom(alice, carol, id);
        vm.stopPrank();
    }

    function test_rule2_unrecognisedCannotTransfer() public {
        uint256 id = _mintAs(alice);
        vm.prank(human);
        vm.expectRevert(abi.encodeWithSelector(SoladyAgentOnly.CallerNotRecognised.selector, human));
        tok.transferFrom(alice, human, id);
    }

    function test_rule2_internalPathsUseCaller() public {
        // _transfer(address(0),..) / _burn(id) skip Solady's auth, but the hook still checks msg.sender.
        uint256 id = _mintAs(alice);
        vm.prank(human);
        vm.expectRevert(abi.encodeWithSelector(SoladyAgentOnly.CallerNotRecognised.selector, human));
        tok.rawBurn(id);
        vm.prank(human);
        vm.expectRevert(abi.encodeWithSelector(SoladyAgentOnly.CallerNotRecognised.selector, human));
        tok.rawTransfer(alice, human, id);
        vm.prank(human);
        vm.expectRevert(abi.encodeWithSelector(SoladyAgentOnly.CallerNotRecognised.selector, human));
        tok.mintExtra(human, 99);
    }

    function test_burnByHolderAndOperator() public {
        uint256 a = _mintAs(alice);
        uint256 b = _mintAs(alice);
        vm.prank(alice);
        tok.burn(a);
        vm.prank(alice);
        tok.setApprovalForAll(carol, true);
        vm.prank(carol);
        tok.burn(b);
        assertEq(tok.balanceOf(alice), 0);
        vm.prank(bob);
        vm.expectRevert(ERC721.TokenDoesNotExist.selector);
        tok.burn(a);
    }

    function test_burnByStrangerAgentReverts() public {
        uint256 id = _mintAs(alice);
        vm.prank(bob);
        vm.expectRevert(ERC721.NotOwnerNorApproved.selector);
        tok.burn(id);
    }

    // ------------------------------------------------------------ Rule 3
    function test_rule3_venueCannotDeliverToUnrecognised() public {
        uint256 id = _mintAs(alice);
        vm.prank(alice);
        tok.approve(address(venue), id);
        vm.expectRevert(abi.encodeWithSelector(SoladyAgentOnly.RecipientNotRecognised.selector, human));
        venue.move(tok, alice, human, id);
    }

    function test_rule3_venueCannotMintToUnrecognised() public {
        vm.prank(address(venue));
        vm.expectRevert(abi.encodeWithSelector(SoladyAgentOnly.RecipientNotRecognised.selector, human));
        tok.mintTo(human, 5);
    }

    function test_rule3_derecognisedRecipientCannotPull() public {
        uint256 id = _mintAs(alice);
        vm.prank(alice);
        tok.approve(bob, id);
        reg.setAgent(bob, false);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(SoladyAgentOnly.CallerNotRecognised.selector, bob));
        tok.transferFrom(alice, bob, id);
    }

    // ------------------------------------------------------------ Rule 4
    function test_rule4_holderCannotPush() public {
        uint256 id = _mintAs(alice);
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(SoladyAgentOnly.RecipientNotCaller.selector, bob));
        tok.transferFrom(alice, bob, id);
        vm.expectRevert(abi.encodeWithSelector(SoladyAgentOnly.RecipientNotCaller.selector, bob));
        tok.safeTransferFrom(alice, bob, id);
        vm.expectRevert(abi.encodeWithSelector(SoladyAgentOnly.RecipientNotCaller.selector, bob));
        tok.safeTransferFrom(alice, bob, id, "");
        vm.stopPrank();
    }

    function test_rule4_holderCannotPushIntoVenue() public {
        // The venue is the recipient, not the caller: no exception.
        uint256 id = _mintAs(alice);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(SoladyAgentOnly.RecipientNotCaller.selector, address(venue)));
        tok.transferFrom(alice, address(venue), id);
    }

    function test_rule4_operatorCannotPushToThirdParty() public {
        uint256 id = _mintAs(alice);
        vm.prank(alice);
        tok.setApprovalForAll(carol, true);
        vm.prank(carol);
        vm.expectRevert(abi.encodeWithSelector(SoladyAgentOnly.RecipientNotCaller.selector, bob));
        tok.transferFrom(alice, bob, id);
    }

    function test_rule4_agentCannotMintToOther() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(SoladyAgentOnly.RecipientNotCaller.selector, bob));
        tok.mintTo(bob, 5);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(SoladyAgentOnly.RecipientNotCaller.selector, bob));
        tok.safeMintTo(bob, 5);
    }

    function test_rule4_pullWithSingleApproval() public {
        uint256 id = _mintAs(alice);
        vm.prank(alice);
        tok.approve(bob, id);
        vm.prank(bob);
        tok.transferFrom(alice, bob, id);
        assertEq(tok.ownerOf(id), bob);
        assertEq(tok.getApproved(id), address(0));
    }

    function test_rule4_pullWithOperatorApproval() public {
        uint256 id = _mintAs(alice);
        vm.prank(alice);
        tok.setApprovalForAll(carol, true);
        vm.prank(carol);
        tok.safeTransferFrom(alice, carol, id);
        assertEq(tok.ownerOf(id), carol);
    }

    function test_rule4_contractAgentPullsSafely() public {
        AgentWallet w = new AgentWallet();
        reg.setAgent(address(w), true);
        uint256 id = _mintAs(alice);
        vm.prank(alice);
        tok.approve(address(w), id);
        w.pull(tok, alice, id);
        assertEq(tok.ownerOf(id), address(w));
    }

    function test_rule4_safePullStillChecksReceiver() public {
        NoReceiver n = new NoReceiver();
        reg.setAgent(address(n), true);
        uint256 id = _mintAs(alice);
        vm.prank(alice);
        tok.approve(address(n), id);
        vm.expectRevert(ERC721.TransferToNonERC721ReceiverImplementer.selector);
        n.pull(tok, alice, id);
    }

    function test_rule4_selfTransferAllowed() public {
        uint256 id = _mintAs(alice);
        vm.prank(alice);
        tok.transferFrom(alice, alice, id);
        assertEq(tok.ownerOf(id), alice);
    }

    function test_rule4_venueAsSenderAndHolder() public {
        uint256 id = _mintAs(alice);
        vm.prank(alice);
        tok.approve(address(venue), id);
        venue.pull(tok, alice, id); // venue pulls into escrow
        assertEq(tok.ownerOf(id), address(venue));
        venue.deliver(tok, bob, id); // venue delivers to a third party
        assertEq(tok.ownerOf(id), bob);
    }

    function test_rule4_venueMovesDirectlyBetweenAgents() public {
        uint256 id = _mintAs(alice);
        vm.prank(alice);
        tok.setApprovalForAll(address(venue), true);
        venue.move(tok, alice, bob, id);
        assertEq(tok.ownerOf(id), bob);
    }

    function test_rule4_venueMintsToAgent() public {
        vm.prank(address(venue));
        tok.mintTo(bob, 5);
        assertEq(tok.ownerOf(5), bob);
    }

    function test_rule4_agentPullsFromVenueHolder() public {
        uint256 id = _mintAs(alice);
        vm.prank(alice);
        tok.approve(address(venue), id);
        venue.pull(tok, alice, id);
        // A venue holder could approve an agent which then pulls.
        vm.prank(address(venue));
        tok.approve(bob, id);
        vm.prank(bob);
        tok.transferFrom(address(venue), bob, id);
        assertEq(tok.ownerOf(id), bob);
    }

    function test_venueBurnsHeldToken() public {
        uint256 id = _mintAs(alice);
        vm.prank(alice);
        tok.approve(address(venue), id);
        venue.pull(tok, alice, id);
        venue.burnIt(tok, id);
        assertEq(tok.balanceOf(address(venue)), 0);
    }

    // ------------------------------------------------------------ Rule 5
    function test_rule5_cannotApproveUnrecognised() public {
        uint256 id = _mintAs(alice);
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(SoladyAgentOnly.OperatorNotRecognised.selector, human));
        tok.approve(human, id);
        vm.expectRevert(abi.encodeWithSelector(SoladyAgentOnly.OperatorNotRecognised.selector, human));
        tok.setApprovalForAll(human, true);
        vm.stopPrank();
    }

    function test_rule5_unrecognisedCallerCannotGrant() public {
        uint256 id = _mintAs(alice);
        reg.setAgent(alice, false); // frozen holder
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(SoladyAgentOnly.CallerNotRecognised.selector, alice));
        tok.approve(bob, id);
        vm.expectRevert(abi.encodeWithSelector(SoladyAgentOnly.CallerNotRecognised.selector, alice));
        tok.setApprovalForAll(bob, true);
        vm.stopPrank();
        vm.prank(human);
        vm.expectRevert(abi.encodeWithSelector(SoladyAgentOnly.CallerNotRecognised.selector, human));
        tok.setApprovalForAll(bob, true);
    }

    function test_rule5_operatorGrantsSingleApproval() public {
        uint256 id = _mintAs(alice);
        vm.prank(alice);
        tok.setApprovalForAll(carol, true);
        vm.prank(carol);
        tok.approve(bob, id);
        assertEq(tok.getApproved(id), bob);
        // Derecognised operator can no longer grant, but can still clear.
        reg.setAgent(carol, false);
        vm.prank(carol);
        vm.expectRevert(abi.encodeWithSelector(SoladyAgentOnly.CallerNotRecognised.selector, carol));
        tok.approve(bob, id);
        vm.prank(carol);
        tok.approve(address(0), id);
        assertEq(tok.getApproved(id), address(0));
    }

    function test_rule5_venueAsOperator() public {
        uint256 id = _mintAs(alice);
        vm.prank(alice);
        tok.approve(address(venue), id);
        assertEq(tok.getApproved(id), address(venue));
    }

    function test_rule5_clearingAlwaysPossible_frozenAndRegistryDown() public {
        uint256 id = _mintAs(alice);
        vm.startPrank(alice);
        tok.approve(bob, id);
        tok.setApprovalForAll(carol, true);
        vm.stopPrank();
        reg.setAgent(alice, false);
        reg.setBroken(true); // clearing makes no registry call at all
        vm.startPrank(alice);
        tok.approve(address(0), id);
        tok.setApprovalForAll(carol, false);
        vm.stopPrank();
        assertEq(tok.getApproved(id), address(0));
        assertFalse(tok.isApprovedForAll(alice, carol));
        // Anyone (even unrecognised) can clear its own operator approvals.
        vm.prank(human);
        tok.setApprovalForAll(bob, false);
    }

    function test_rule5_clearingStillNeedsErc721Auth() public {
        uint256 id = _mintAs(alice);
        vm.prank(human);
        vm.expectRevert(ERC721.NotOwnerNorApproved.selector);
        tok.approve(address(0), id);
    }

    function test_rule5_internalApprovalPathsEnforced() public {
        uint256 id = _mintAs(alice);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(SoladyAgentOnly.OperatorNotRecognised.selector, human));
        tok.rawApprove(human, id);
        vm.prank(human);
        vm.expectRevert(abi.encodeWithSelector(SoladyAgentOnly.CallerNotRecognised.selector, human));
        tok.rawApproveAll(alice, bob, true);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(SoladyAgentOnly.OperatorNotRecognised.selector, human));
        tok.rawApproveAll(alice, human, true);
        // Derived code granting for a frozen `by` is refused even if msg.sender is recognised.
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(SoladyAgentOnly.HolderNotRecognised.selector, human));
        tok.rawApproveAll(human, carol, true);
    }

    // ------------------------------------------------------------ Rule 6
    function test_rule6_registryFixed() public {
        assertEq(address(tok.agentRegistry()), address(reg));
        _mintAs(alice);
        assertEq(address(tok.agentRegistry()), address(reg));
    }

    function test_rule6_zeroRegistryRejected() public {
        vm.expectRevert(SoladyAgentOnly.ZeroRegistry.selector);
        new Harness(IAgentRegistry(address(0)));
    }

    function test_rule6_registryDownBlocksMovement() public {
        uint256 id = _mintAs(alice);
        reg.setBroken(true);
        vm.prank(alice);
        vm.expectRevert(bytes("registry down"));
        tok.transferFrom(alice, alice, id);
        vm.prank(alice);
        vm.expectRevert(bytes("registry down"));
        tok.mint();
    }

    // ------------------------------------------------------------ Rule 7
    function test_rule7_frozenHolderTokensStayAndResume() public {
        uint256 id = _mintAs(alice);
        vm.prank(alice);
        tok.approve(bob, id);
        vm.prank(alice);
        tok.setApprovalForAll(address(venue), true);
        reg.setAgent(alice, false); // freeze

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(SoladyAgentOnly.HolderNotRecognised.selector, alice));
        tok.transferFrom(alice, bob, id);
        vm.expectRevert(abi.encodeWithSelector(SoladyAgentOnly.HolderNotRecognised.selector, alice));
        venue.move(tok, alice, bob, id);
        vm.expectRevert(abi.encodeWithSelector(SoladyAgentOnly.HolderNotRecognised.selector, alice));
        venue.burnIt(tok, id);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(SoladyAgentOnly.CallerNotRecognised.selector, alice));
        tok.burn(id);
        assertEq(tok.ownerOf(id), alice);

        reg.setAgent(alice, true); // unfreeze
        vm.prank(bob);
        tok.transferFrom(alice, bob, id);
        assertEq(tok.ownerOf(id), bob);
    }

    function test_rule7_frozenVenueHolder() public {
        uint256 id = _mintAs(alice);
        vm.prank(alice);
        tok.approve(address(venue), id);
        venue.pull(tok, alice, id);
        vm.prank(address(venue));
        tok.approve(bob, id);
        reg.setVenue(address(venue), false);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(SoladyAgentOnly.HolderNotRecognised.selector, address(venue)));
        tok.transferFrom(address(venue), bob, id);
    }

    function test_rule7_holderRecognisedAsVenueOnly() public {
        // A holder recognised only via isVenue counts as recognised.
        address v2 = makeAddr("v2");
        reg.setVenue(v2, true);
        vm.prank(v2);
        uint256 id = tok.mint();
        vm.prank(v2);
        tok.approve(bob, id);
        vm.prank(bob);
        tok.transferFrom(v2, bob, id);
        assertEq(tok.ownerOf(id), bob);
    }

    // ------------------------------------------------- eligibility source
    function test_codeIsIrrelevant() public {
        // An EOA agent and a contract agent are treated the same; a contract that is not
        // recognised is rejected even though it has code.
        NoReceiver n = new NoReceiver();
        vm.prank(address(n));
        vm.expectRevert(abi.encodeWithSelector(SoladyAgentOnly.CallerNotRecognised.selector, address(n)));
        tok.mint();
    }

    function test_wrongFromStillReverts() public {
        uint256 id = _mintAs(alice);
        vm.prank(bob);
        vm.expectRevert(ERC721.NotOwnerNorApproved.selector); // rule 8 in the hook
        tok.transferFrom(bob, bob, id);
        vm.prank(alice);
        vm.expectRevert(ERC721.TransferFromIncorrectOwner.selector); // authorised, wrong `from`
        tok.transferFrom(bob, alice, id);
        vm.prank(bob);
        vm.expectRevert(ERC721.TokenAlreadyExists.selector); // from = 0 looks like a mint
        tok.transferFrom(address(0), bob, id);
    }

    function test_transferToZeroReverts() public {
        uint256 id = _mintAs(alice);
        vm.prank(alice);
        vm.expectRevert(ERC721.TransferToZeroAddress.selector);
        tok.transferFrom(alice, address(0), id);
    }

    // ------------------------------------------------- revised rule 5: holder recognised
    function test_rule5_frozenHoldersOperatorCannotGrant() public {
        uint256 id = _mintAs(alice);
        vm.prank(alice);
        tok.setApprovalForAll(carol, true);
        reg.setAgent(alice, false); // holder stops being recognised
        vm.prank(carol);
        vm.expectRevert(abi.encodeWithSelector(SoladyAgentOnly.HolderNotRecognised.selector, alice));
        tok.approve(bob, id);
        // The operator can still clear.
        vm.prank(carol);
        tok.approve(address(0), id);
        // Once unfrozen, the operator may grant again.
        reg.setAgent(alice, true);
        vm.prank(carol);
        tok.approve(bob, id);
        assertEq(tok.getApproved(id), bob);
    }

    function test_rule5_frozenOwnerCannotSetOperator() public {
        reg.setAgent(alice, false);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(SoladyAgentOnly.CallerNotRecognised.selector, alice));
        tok.setApprovalForAll(bob, true);
    }

    function test_rule8_derivedGrantWithoutAuthRefused() public {
        // `_approve(account, id)` (by = 0) by a recognised non-owner must not hand out rights.
        uint256 id = _mintAs(alice);
        vm.prank(bob);
        vm.expectRevert(ERC721.NotOwnerNorApproved.selector);
        tok.rawApprove(bob, id);
        vm.prank(address(venue));
        vm.expectRevert(ERC721.NotOwnerNorApproved.selector);
        tok.rawApprove(address(venue), id);
        vm.prank(alice);
        tok.rawApprove(bob, id); // the holder may
        assertEq(tok.getApproved(id), bob);
    }

    function test_rule5_derivedGrantForFrozenHolderRefused() public {
        uint256 id = _mintAs(alice);
        vm.prank(alice);
        tok.setApprovalForAll(bob, true);
        reg.setAgent(alice, false);
        vm.prank(bob); // recognised operator, internal path with by = 0
        vm.expectRevert(abi.encodeWithSelector(SoladyAgentOnly.HolderNotRecognised.selector, alice));
        tok.rawApprove(carol, id);
    }

    function test_rule5_derivedGrantByFrozenOperatorRefused() public {
        // A permit-like path: recognised relayer, holder recognised, signer `by` = a frozen operator.
        uint256 id = _mintAs(alice);
        vm.prank(alice);
        tok.setApprovalForAll(carol, true);
        reg.setAgent(carol, false);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(SoladyAgentOnly.CallerNotRecognised.selector, carol));
        tok.rawApproveBy(carol, bob, id);
    }

    function test_rule5_grantOnMissingToken() public {
        vm.prank(alice);
        vm.expectRevert(ERC721.TokenDoesNotExist.selector);
        tok.approve(bob, 42);
    }

    function test_rule5_frozenVenueHolderCannotGrant() public {
        uint256 id = _mintAs(alice);
        vm.prank(alice);
        tok.approve(address(venue), id);
        venue.pull(tok, alice, id);
        reg.setVenue(address(venue), false);
        vm.prank(address(venue));
        vm.expectRevert(abi.encodeWithSelector(SoladyAgentOnly.CallerNotRecognised.selector, address(venue)));
        tok.approve(bob, id);
    }

    // ------------------------------------------------- rule 8: ERC-721 authorisation everywhere
    function test_rule8_venueCannotMoveUnapprovedToken() public {
        uint256 id = _mintAs(alice);
        vm.expectRevert(ERC721.NotOwnerNorApproved.selector);
        venue.move(tok, alice, bob, id);
    }

    function test_rule8_internalTransferWithoutAuthRefused() public {
        uint256 id = _mintAs(alice);
        // _transfer(address(0), ..) skips Solady's check; the hook still enforces rule 8.
        vm.prank(address(venue));
        vm.expectRevert(ERC721.NotOwnerNorApproved.selector);
        tok.rawTransfer(alice, bob, id);
        vm.prank(bob);
        vm.expectRevert(ERC721.NotOwnerNorApproved.selector);
        tok.rawTransfer(alice, bob, id);
        // `by` named by derived code does not replace the caller.
        vm.prank(address(venue));
        vm.expectRevert(ERC721.NotOwnerNorApproved.selector);
        tok.rawTransferBy(alice, alice, bob, id);
    }

    function test_rule8_internalBurnWithoutAuthRefused() public {
        uint256 id = _mintAs(alice);
        vm.prank(address(venue));
        vm.expectRevert(ERC721.NotOwnerNorApproved.selector);
        tok.rawBurn(id);
        vm.prank(bob);
        vm.expectRevert(ERC721.NotOwnerNorApproved.selector);
        tok.rawBurn(id);
        vm.prank(alice);
        tok.rawBurn(id); // the holder may
        assertEq(tok.balanceOf(alice), 0);
    }

    function test_rule8_internalPathsWithApproval() public {
        uint256 id = _mintAs(alice);
        vm.prank(alice);
        tok.setApprovalForAll(address(venue), true);
        vm.prank(address(venue));
        tok.rawTransfer(alice, bob, id);
        assertEq(tok.ownerOf(id), bob);
    }

    function test_rule8_mintCannotOverwrite() public {
        uint256 id = _mintAs(alice);
        // Solady's _mintAndSetExtraDataUnchecked does not check existence; the hook does.
        vm.prank(bob);
        vm.expectRevert(ERC721.TokenAlreadyExists.selector);
        tok.mintExtra(bob, id);
        vm.prank(address(venue));
        vm.expectRevert(ERC721.TokenAlreadyExists.selector);
        tok.mintTo(bob, id);
        assertEq(tok.ownerOf(id), alice);
        assertEq(tok.balanceOf(bob), 0);
        vm.prank(bob);
        tok.mintExtra(bob, 77); // a fresh id is fine
        assertEq(tok.ownerOf(77), bob);
    }

    function test_interfaceIdValue() public pure {
        assertEq(type(IERC721AgentOnly).interfaceId, bytes4(0x0d1cfcae));
    }

    function test_staleApprovalStillReported() public {
        uint256 id = _mintAs(alice);
        vm.startPrank(alice);
        tok.approve(bob, id);
        tok.setApprovalForAll(carol, true);
        vm.stopPrank();
        reg.setAgent(bob, false);
        reg.setAgent(carol, false);
        assertEq(tok.getApproved(id), bob);
        assertTrue(tok.isApprovedForAll(alice, carol));
    }

    // ------------------------------------------------- fuzz: no push by non-venues
    function testFuzz_nonVenueNeverPushes(address caller, address to) public {
        vm.assume(caller != address(0) && caller != to && to != address(0) && caller != address(venue));
        vm.assume(!reg.venue(caller));
        reg.setAgent(caller, true);
        reg.setAgent(to, true);
        vm.prank(caller);
        uint256 id = tok.mint();
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(SoladyAgentOnly.RecipientNotCaller.selector, to));
        tok.transferFrom(caller, to, id);
    }
}
