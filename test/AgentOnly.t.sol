// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAgentRegistry} from "../src/IAgentRegistry.sol";
import {ERC721AgentOnly} from "../src/ERC721AgentOnly.sol";
import {IERC721AgentOnly} from "../src/IERC721AgentOnly.sol";
import {AgentAccount} from "../src/AgentAccount.sol";
import {AttestedAgentRegistry} from "../src/AttestedAgentRegistry.sol";
import {AgentSwap} from "../src/AgentSwap.sol";
import {AgentLoan} from "../src/AgentLoan.sol";

contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// Stands in for the ERC-8004 identity registry: a plain ERC-721.
contract MockIdentity is ERC721 {
    constructor() ERC721("Agent Identity", "AID") {}

    function register(address to, uint256 id) external {
        _mint(to, id);
    }
}

/// Any collection adopting the standard: one line of inheritance.
contract AnyCollection is ERC721AgentOnly {
    uint256 public lastId;
    mapping(uint256 => bytes32) public contentHash;

    constructor(IAgentRegistry r) ERC721("Any Agent Asset", "AAA") ERC721AgentOnly(r) {}

    function mint(bytes32 content) external returns (uint256 id) {
        id = ++lastId;
        contentHash[id] = content;
        _mint(msg.sender, id);
    }

    function burn(uint256 id) external {
        _checkAuthorized(_ownerOf(id), msg.sender, id);
        _burn(id);
    }
}

/// An unapproved contract trying to wrap the token to resell it to humans.
contract RogueWrapper {
    function grab(IERC721 nft, address from, uint256 id) external {
        nft.transferFrom(from, address(this), id);
    }
}

/// Shared setup: a registry with three attesters, two enrolled agents, a sale and a loan venue.
abstract contract AgentOnlyBase is Test {
    AttestedAgentRegistry reg;
    AnyCollection nft;
    AgentSwap swap;
    AgentLoan loan;
    MockUSDC usdc;
    AgentAccount acc1;
    AgentAccount acc2;

    uint256 constant K1 = 0x0101010101010101010101010101010101010101010101010101010101010101;
    uint256 constant K2 = 0x0202020202020202020202020202020202020202020202020202020202020202;
    uint256 constant HUMAN_PK = 0x0909090909090909090909090909090909090909090909090909090909090909;
    uint256 constant A1 = 0xA1;
    uint256 constant A2 = 0xA2;
    uint256 constant A3 = 0xA3;
    address constant SPONSOR1 = address(0x101);
    address constant SPONSOR2 = address(0x102);
    address human;
    uint64 constant NOW = 1_000;
    uint64 constant FAR = 10_000_000;
    uint256 constant BOND = 0.01 ether;
    uint64 constant TTL = 30 days;

    function setUp() public virtual {
        vm.chainId(8453);
        vm.warp(NOW);
        human = vm.addr(HUMAN_PK);
        address[] memory att = new address[](3);
        att[0] = vm.addr(A1);
        att[1] = vm.addr(A2);
        att[2] = vm.addr(A3);
        reg = new AttestedAgentRegistry(att, 2, BOND, TTL, IERC721(address(0)));
        nft = new AnyCollection(IAgentRegistry(address(reg)));
        swap = new AgentSwap();
        loan = new AgentLoan();
        usdc = new MockUSDC();

        vm.deal(SPONSOR1, 1 ether);
        vm.deal(SPONSOR2, 1 ether);
        _enroll(reg, SPONSOR1, 1, vm.addr(K1), BOND);
        _enroll(reg, SPONSOR2, 2, vm.addr(K2), BOND);
        acc1 = AgentAccount(payable(reg.accountOf(1)));
        acc2 = AgentAccount(payable(reg.accountOf(2)));
        usdc.mint(address(acc1), 1_000);
        usdc.mint(address(acc2), 1_000);

        _venue(address(swap));
        _venue(address(loan));
    }

    // ------------------------------------------------------------ helpers

    function _sign(uint256 pk, bytes32 digest) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    function _attest(uint256 pkA, uint256 pkB, bytes32 digest) internal pure returns (bytes[] memory sigs) {
        if (vm.addr(pkA) > vm.addr(pkB)) (pkA, pkB) = (pkB, pkA);
        sigs = new bytes[](2);
        sigs[0] = _sign(pkA, digest);
        sigs[1] = _sign(pkB, digest);
    }

    function _enroll(AttestedAgentRegistry r, address sponsor, uint256 agent, address key, uint256 value) internal {
        bytes32 d = r.hashEnrollment(agent, key, keccak256("evidence"), sponsor, r.enrollmentNonce(agent), FAR);
        bytes[] memory sigs = _attest(A1, A2, d);
        vm.prank(sponsor);
        r.enroll{value: value}(agent, key, keccak256("evidence"), FAR, sigs);
    }

    function _venue(address v) internal {
        reg.setVenue(v, true, keccak256("code"), _attest(A1, A2, reg.hashVenue(v, true, keccak256("code"))));
    }

    /// The agent acts: its session key calls its account.
    function _do(uint256 pk, AgentAccount acc, address target, bytes memory data) internal returns (bytes memory) {
        vm.prank(vm.addr(pk));
        return acc.execute(target, 0, data);
    }

    function _mint(uint256 pk, AgentAccount acc) internal returns (uint256) {
        return abi.decode(_do(pk, acc, address(nft), abi.encodeCall(nft.mint, (bytes32(uint256(7))))), (uint256));
    }

    function _expectNotAgent(address who) internal {
        vm.expectRevert(abi.encodeWithSelector(ERC721AgentOnly.NotAgent.selector, who));
    }
}

contract AgentOnlyTest is AgentOnlyBase {
    // ------------------------------------------------------------ a classic NFT, between agents

    function test_ClassicBehaviourBetweenAgents() public {
        uint256 id = _mint(K1, acc1);
        assertEq(nft.ownerOf(id), address(acc1));
        assertEq(nft.balanceOf(address(acc1)), 1);

        // Transfer: the holder approves, the recipient pulls.
        _do(K1, acc1, address(nft), abi.encodeCall(nft.approve, (address(acc2), id)));
        assertEq(nft.getApproved(id), address(acc2));
        _do(K2, acc2, address(nft), abi.encodeCall(nft.transferFrom, (address(acc1), address(acc2), id)));
        assertEq(nft.ownerOf(id), address(acc2));

        // safeTransferFrom works too, and so does burn.
        _do(K2, acc2, address(nft), abi.encodeCall(nft.approve, (address(acc1), id)));
        _do(
            K1, acc1, address(nft), abi.encodeWithSignature("safeTransferFrom(address,address,uint256)", acc2, acc1, id)
        );
        assertEq(nft.ownerOf(id), address(acc1));
        _do(K1, acc1, address(nft), abi.encodeCall(nft.burn, (id)));
        assertEq(nft.balanceOf(address(acc1)), 0);
    }

    // ------------------------------------------------------------ no human

    function test_HumanCannotMintHoldOrBeApproved() public {
        _expectNotAgent(human);
        vm.prank(human);
        nft.mint(bytes32(0));

        uint256 id = _mint(K1, acc1);

        // Send to a human.
        _expectNotAgent(human);
        _do(K1, acc1, address(nft), abi.encodeCall(nft.transferFrom, (address(acc1), human, id)));

        // Approve a human, or an unapproved marketplace contract.
        _expectNotAgent(human);
        _do(K1, acc1, address(nft), abi.encodeCall(nft.approve, (human, id)));
        address seaport = address(0x5EA9027);
        _expectNotAgent(seaport);
        _do(K1, acc1, address(nft), abi.encodeCall(nft.setApprovalForAll, (seaport, true)));

        // A human key cannot drive an agent's account.
        vm.prank(human);
        vm.expectRevert(AgentAccount.NotKey.selector);
        acc1.execute(address(nft), 0, abi.encodeCall(nft.burn, (id)));
        assertEq(nft.ownerOf(id), address(acc1));
    }

    function test_NoUnsolicitedToken() public {
        uint256 id = _mint(K1, acc1);
        // The holder cannot push a token to another agent.
        vm.expectRevert(ERC721AgentOnly.NotPulledByRecipient.selector);
        _do(K1, acc1, address(nft), abi.encodeCall(nft.transferFrom, (address(acc1), address(acc2), id)));
    }

    function test_UnapprovedContractCannotWrap() public {
        uint256 id = _mint(K1, acc1);
        RogueWrapper w = new RogueWrapper();
        _expectNotAgent(address(w));
        _do(K1, acc1, address(nft), abi.encodeCall(nft.approve, (address(w), id)));
        _expectNotAgent(address(w));
        w.grab(nft, address(acc1), id);
    }

    function testFuzz_NonAgentNeverReceives(address anyone) public {
        vm.assume(anyone != address(0) && anyone != address(acc1) && anyone != address(acc2));
        vm.assume(anyone != address(swap) && anyone != address(loan));
        uint256 id = _mint(K1, acc1);
        _expectNotAgent(anyone);
        _do(K1, acc1, address(nft), abi.encodeCall(nft.approve, (anyone, id)));
        vm.prank(anyone);
        vm.expectRevert();
        nft.transferFrom(address(acc1), anyone, id);
        assertEq(nft.ownerOf(id), address(acc1));
    }

    // ------------------------------------------------------------ buy and sell

    function test_BuyAndSell() public {
        uint256 id = _mint(K1, acc1);
        _do(K1, acc1, address(nft), abi.encodeCall(nft.approve, (address(swap), id)));
        _do(K1, acc1, address(swap), abi.encodeCall(swap.list, (nft, id, usdc, 300, address(0))));

        // A human with USDC tries to buy: the token rejects them.
        usdc.mint(human, 300);
        vm.startPrank(human);
        usdc.approve(address(swap), 300);
        _expectNotAgent(human);
        swap.buy(nft, id, usdc, 300);
        vm.stopPrank();
        assertEq(nft.ownerOf(id), address(acc1));
        assertEq(usdc.balanceOf(human), 300);

        // An agent buys: NFT and USDC move in the same transaction.
        _do(K2, acc2, address(usdc), abi.encodeCall(usdc.approve, (address(swap), 300)));
        _do(K2, acc2, address(swap), abi.encodeCall(swap.buy, (nft, id, usdc, 300)));
        assertEq(nft.ownerOf(id), address(acc2));
        assertEq(usdc.balanceOf(address(acc1)), 1_300);
        assertEq(usdc.balanceOf(address(acc2)), 700);
    }

    // ------------------------------------------------------------ collateralised loan

    function test_LoanRepaidThenDefault() public {
        uint256 id = _mint(K1, acc1);
        _do(K1, acc1, address(nft), abi.encodeCall(nft.approve, (address(loan), id)));
        _do(K1, acc1, address(loan), abi.encodeCall(loan.offer, (nft, id, usdc, 400, 440, 900)));
        assertEq(nft.ownerOf(id), address(loan));

        _do(K2, acc2, address(usdc), abi.encodeCall(usdc.approve, (address(loan), 400)));
        _do(K2, acc2, address(loan), abi.encodeCall(loan.fund, (nft, id, usdc, 400, 440, 900)));
        assertEq(usdc.balanceOf(address(acc1)), 1_400);

        _do(K1, acc1, address(usdc), abi.encodeCall(usdc.approve, (address(loan), 440)));
        _do(K1, acc1, address(loan), abi.encodeCall(loan.repay, (nft, id)));
        assertEq(nft.ownerOf(id), address(acc1));
        assertEq(usdc.balanceOf(address(acc2)), 1_040);

        // Second loan, not repaid: the lender claims the token after the due date.
        _do(K1, acc1, address(nft), abi.encodeCall(nft.approve, (address(loan), id)));
        _do(K1, acc1, address(loan), abi.encodeCall(loan.offer, (nft, id, usdc, 100, 110, 500)));
        _do(K2, acc2, address(usdc), abi.encodeCall(usdc.approve, (address(loan), 100)));
        _do(K2, acc2, address(loan), abi.encodeCall(loan.fund, (nft, id, usdc, 100, 110, 500)));
        vm.expectRevert(AgentLoan.NotDue.selector);
        _do(K2, acc2, address(loan), abi.encodeCall(loan.claim, (nft, id)));
        vm.warp(NOW + 501);
        _do(K2, acc2, address(loan), abi.encodeCall(loan.claim, (nft, id)));
        assertEq(nft.ownerOf(id), address(acc2));
    }

    // ------------------------------------------------------------ keys, relayers, signatures

    function test_KeyRotationKeepsAssets() public {
        uint256 id = _mint(K1, acc1);
        uint256 k1b = 0x0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b;
        _enroll(reg, SPONSOR1, 1, vm.addr(k1b), 0);
        assertEq(reg.accountOf(1), address(acc1));
        assertEq(nft.ownerOf(id), address(acc1));

        vm.prank(vm.addr(K1));
        vm.expectRevert(AgentAccount.NotKey.selector);
        acc1.execute(address(nft), 0, abi.encodeCall(nft.burn, (id)));

        // Expired key: the account is no longer an agent until it is re-enrolled.
        vm.warp(NOW + TTL);
        assertFalse(reg.isAgent(address(acc1)));
        _enroll(reg, SPONSOR1, 1, vm.addr(K1), 0);
        _do(K1, acc1, address(nft), abi.encodeCall(nft.burn, (id)));
    }

    function test_RelayedCallAndOffchainSignature() public {
        bytes memory data = abi.encodeCall(nft.mint, (bytes32(uint256(7))));
        bytes32 d = acc1.execDigest(address(nft), 0, data, acc1.nonce(), FAR);
        bytes memory sig = _sign(K1, d);

        // Anyone can relay; the agent needs no ETH.
        vm.prank(address(0xBEEF));
        acc1.executeBySig(address(nft), 0, data, FAR, sig);
        assertEq(nft.balanceOf(address(acc1)), 1);
        vm.expectRevert(AgentAccount.NotKey.selector);
        acc1.executeBySig(address(nft), 0, data, FAR, sig);

        bytes memory humanSig = _sign(HUMAN_PK, acc1.execDigest(address(nft), 0, data, 1, FAR));
        vm.expectRevert(AgentAccount.NotKey.selector);
        acc1.executeBySig(address(nft), 0, data, FAR, humanSig);

        // ERC-1271: the account validates its session key's signatures, and only those.
        bytes32 h = keccak256("order");
        assertEq(acc1.isValidSignature(h, _sign(K1, acc1.messageDigest(h))), bytes4(0x1626ba7e));
        assertEq(acc1.isValidSignature(h, _sign(HUMAN_PK, acc1.messageDigest(h))), bytes4(0xffffffff));
    }

    // ------------------------------------------------------------ registry

    function test_EnrollmentNeedsAttesters() public {
        address key = human;
        bytes32 d = reg.hashEnrollment(9, key, keccak256("evidence"), address(this), 0, FAR);
        vm.deal(address(this), 1 ether);

        bytes[] memory one = new bytes[](1);
        one[0] = _sign(A1, d);
        vm.expectRevert(AttestedAgentRegistry.NotEnoughAttesters.selector);
        reg.enroll{value: BOND}(9, key, keccak256("evidence"), FAR, one);

        // A human signing their own enrollment is not an attester.
        bytes[] memory fake = _attest(A1, HUMAN_PK, d);
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector);
        reg.enroll{value: BOND}(9, key, keccak256("evidence"), FAR, fake);

        // Nor is a venue approved by them alone.
        bytes[] memory v = new bytes[](1);
        v[0] = _sign(HUMAN_PK, reg.hashVenue(human, true, bytes32(0)));
        vm.expectRevert(AttestedAgentRegistry.NotEnoughAttesters.selector);
        reg.setVenue(human, true, bytes32(0), v);
    }

    function test_FrozenAndRevokedAgentsStop() public {
        uint256 id = _mint(K1, acc1);
        vm.prank(SPONSOR1);
        reg.setFrozen(1, true);
        // Frozen, the agent can no longer make its account act, and nobody can send it a token.
        vm.prank(vm.addr(K1));
        vm.expectRevert(AgentAccount.NotKey.selector);
        acc1.execute(address(nft), 0, abi.encodeCall(nft.burn, (id)));
        uint256 id2 = _mint(K2, acc2);
        _do(K2, acc2, address(nft), abi.encodeCall(nft.approve, (address(swap), id2)));
        _do(K2, acc2, address(swap), abi.encodeCall(swap.list, (nft, id2, usdc, 0, address(acc1))));
        vm.prank(address(acc1));
        _expectNotAgent(address(acc1));
        swap.buy(nft, id2, usdc, 0);
        vm.prank(SPONSOR1);
        reg.setFrozen(1, false);

        reg.revoke(1, _attest(A1, A3, reg.hashRevocation(1)));
        assertFalse(reg.isAgent(address(acc1)));
        assertEq(nft.ownerOf(id), address(acc1));
    }

    function test_Erc8004IdentityMustBelongToSponsor() public {
        MockIdentity ids = new MockIdentity();
        address[] memory att = new address[](3);
        att[0] = vm.addr(A1);
        att[1] = vm.addr(A2);
        att[2] = vm.addr(A3);
        AttestedAgentRegistry r = new AttestedAgentRegistry(att, 2, BOND, TTL, IERC721(address(ids)));
        ids.register(SPONSOR1, 42);

        // Anyone other than the owner of identity 42 cannot enroll it.
        bytes32 d = r.hashEnrollment(42, vm.addr(K2), keccak256("evidence"), SPONSOR2, 0, FAR);
        bytes[] memory sigs = _attest(A1, A2, d);
        vm.prank(SPONSOR2);
        vm.expectRevert(AttestedAgentRegistry.NotIdentityOwner.selector);
        r.enroll{value: BOND}(42, vm.addr(K2), keccak256("evidence"), FAR, sigs);

        _enroll(r, SPONSOR1, 42, vm.addr(K1), BOND);
        assertTrue(r.isAgent(r.accountOf(42)));
    }

    // ------------------------------------------------------------ hardening
    // Each test below replays an attack that worked before the review of 13 November 2026.

    function test_VenueDecisionCannotBeReplayed() public {
        address rogue = address(0xBAD);
        bytes[] memory approval = _attest(A1, A2, reg.hashVenue(rogue, true, keccak256("code")));
        reg.setVenue(rogue, true, keccak256("code"), approval);
        reg.setVenue(rogue, false, keccak256("code"), _attest(A1, A2, reg.hashVenue(rogue, false, keccak256("code"))));
        assertFalse(reg.isVenue(rogue));
        // Anyone replays the old approval: refused.
        vm.prank(human);
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector);
        reg.setVenue(rogue, true, keccak256("code"), approval);
        assertFalse(reg.isVenue(rogue));
    }

    function test_FrozenHolderTokensDoNotMove() public {
        uint256 id = _mint(K1, acc1);
        _do(K1, acc1, address(nft), abi.encodeCall(nft.approve, (address(swap), id)));
        _do(K1, acc1, address(swap), abi.encodeCall(swap.list, (nft, id, usdc, 1, address(0))));
        _do(K2, acc2, address(usdc), abi.encodeCall(usdc.approve, (address(swap), 1)));
        // Emergency stop: the listing left behind can no longer be bought.
        vm.prank(SPONSOR1);
        reg.setFrozen(1, true);
        vm.prank(vm.addr(K2));
        _expectNotAgent(address(acc1));
        acc2.execute(address(swap), 0, abi.encodeCall(swap.buy, (nft, id, usdc, 1)));
        assertEq(nft.ownerOf(id), address(acc1));
        // Unfrozen, the sale goes through.
        vm.prank(SPONSOR1);
        reg.setFrozen(1, false);
        _do(K2, acc2, address(swap), abi.encodeCall(swap.buy, (nft, id, usdc, 1)));
        assertEq(nft.ownerOf(id), address(acc2));
    }

    function test_SellerCannotSwitchCurrency() public {
        MockUSDC junk = new MockUSDC();
        junk.mint(address(acc2), 300);
        uint256 id = _mint(K1, acc1);
        _do(K1, acc1, address(nft), abi.encodeCall(nft.approve, (address(swap), id)));
        _do(K1, acc1, address(swap), abi.encodeCall(swap.list, (nft, id, junk, 300, address(0))));
        _do(K2, acc2, address(junk), abi.encodeCall(junk.approve, (address(swap), 300)));
        _do(K2, acc2, address(usdc), abi.encodeCall(usdc.approve, (address(swap), 1_000)));
        // The seller re-lists at the same number in another currency, just before the purchase.
        _do(K1, acc1, address(swap), abi.encodeCall(swap.list, (nft, id, usdc, 300, address(0))));
        vm.prank(vm.addr(K2));
        vm.expectRevert(AgentSwap.TermsChanged.selector);
        acc2.execute(address(swap), 0, abi.encodeCall(swap.buy, (nft, id, junk, 300)));
        assertEq(usdc.balanceOf(address(acc2)), 1_000);
    }

    function test_BorrowerCannotSwitchTerms() public {
        uint256 id = _mint(K1, acc1);
        _do(K1, acc1, address(nft), abi.encodeCall(nft.approve, (address(loan), id)));
        _do(K1, acc1, address(loan), abi.encodeCall(loan.offer, (nft, id, usdc, 100, 110, 30 days)));
        _do(K2, acc2, address(usdc), abi.encodeCall(usdc.approve, (address(loan), 1_000)));
        // The borrower replaces its offer just before the funding.
        _do(K1, acc1, address(loan), abi.encodeCall(loan.cancel, (nft, id)));
        _do(K1, acc1, address(nft), abi.encodeCall(nft.approve, (address(loan), id)));
        _do(K1, acc1, address(loan), abi.encodeCall(loan.offer, (nft, id, usdc, 1_000, 0, 1)));
        vm.prank(vm.addr(K2));
        vm.expectRevert(AgentLoan.TermsChanged.selector);
        acc2.execute(address(loan), 0, abi.encodeCall(loan.fund, (nft, id, usdc, 100, 110, 30 days)));
        assertEq(usdc.balanceOf(address(acc2)), 1_000);
    }

    function test_SignaturesAreBoundToTheirPurpose() public {
        bytes memory data = abi.encodeCall(usdc.transfer, (human, 1_000));
        bytes32 order = acc1.execDigest(address(usdc), 0, data, acc1.nonce(), FAR);
        // The agent approves `order` as an off-chain message (ERC-1271)...
        bytes memory messageSig = _sign(K1, acc1.messageDigest(order));
        assertEq(acc1.isValidSignature(order, messageSig), bytes4(0x1626ba7e));
        // ... which cannot be turned into an execution.
        vm.expectRevert(AgentAccount.NotKey.selector);
        acc1.executeBySig(address(usdc), 0, data, FAR, messageSig);
        // A raw signature over a hash is not an approval of that hash.
        assertEq(acc1.isValidSignature(order, _sign(K1, order)), bytes4(0xffffffff));
        // A message approved on one account means nothing on another.
        assertEq(acc2.isValidSignature(order, messageSig), bytes4(0xffffffff));
        assertEq(usdc.balanceOf(human), 0);
    }

    function test_BatchIsAllOrNothing() public {
        uint256 id = _mint(K1, acc1);
        _do(K1, acc1, address(nft), abi.encodeCall(nft.approve, (address(swap), id)));
        _do(K1, acc1, address(swap), abi.encodeCall(swap.list, (nft, id, usdc, 300, address(0))));
        AgentAccount.Call[] memory calls = new AgentAccount.Call[](2);
        calls[0] = AgentAccount.Call(address(usdc), 0, abi.encodeCall(usdc.approve, (address(swap), 300)));
        calls[1] = AgentAccount.Call(address(swap), 0, abi.encodeCall(swap.buy, (nft, id, usdc, 999)));
        // The second call fails: the first one is undone too.
        vm.prank(vm.addr(K2));
        vm.expectRevert(AgentSwap.TermsChanged.selector);
        acc2.executeBatch(calls);
        assertEq(usdc.allowance(address(acc2), address(swap)), 0);
        // A human cannot batch on the agent's behalf.
        vm.prank(human);
        vm.expectRevert(AgentAccount.NotKey.selector);
        acc2.executeBatch(calls);
        // Relayed batch: signed by the key, submitted by anyone.
        calls[1].data = abi.encodeCall(swap.buy, (nft, id, usdc, 300));
        bytes memory data = abi.encodeCall(acc2.executeBatch, (calls));
        bytes memory sig = _sign(K2, acc2.execDigest(address(acc2), 0, data, acc2.nonce(), FAR));
        vm.prank(address(0xBEEF));
        acc2.executeBySig(address(acc2), 0, data, FAR, sig);
        assertEq(nft.ownerOf(id), address(acc2));
    }

    function test_InterfaceIsAdvertised() public view {
        assertTrue(nft.supportsInterface(type(IERC721AgentOnly).interfaceId));
        assertTrue(nft.supportsInterface(type(IERC721).interfaceId));
        assertEq(address(IERC721AgentOnly(address(nft)).agentRegistry()), address(reg));
    }
}
