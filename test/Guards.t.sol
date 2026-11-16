// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IAgentRegistry} from "../src/IAgentRegistry.sol";
import {AgentAccount} from "../src/AgentAccount.sol";
import {AgentLoan} from "../src/AgentLoan.sol";
import {AgentReputationBadge} from "../src/AgentReputationBadge.sol";
import {AgentStaking} from "../src/AgentStaking.sol";
import {AgentSwap} from "../src/AgentSwap.sol";
import {AttestedAgentRegistry} from "../src/AttestedAgentRegistry.sol";
import {AgentOnlyBase, MockUSDC} from "./AgentOnly.t.sol";

/// One test per check that systematic mutation testing found unguarded on 16 November 2026:
/// each of these checks could be removed from the contracts without any test failing.
/// See tools/mutate.py.
contract GuardsTest is AgentOnlyBase {
    bytes32 constant EVIDENCE = keccak256("evidence");
    address constant KEY = address(0xABCD);
    address constant ISSUER = address(0xB07);
    uint256 constant DEPOSIT = 0.05 ether;

    AgentStaking staking;
    AgentReputationBadge badges;

    function setUp() public override {
        super.setUp();
        staking = new AgentStaking(nft, usdc, address(this), 7 days);
        _venue(address(staking));
        badges = new AgentReputationBadge(IAgentRegistry(address(reg)), DEPOSIT, 3, 30 days);
        vm.deal(ISSUER, 1 ether);
        vm.prank(ISSUER);
        badges.registerIssuer{value: DEPOSIT}();
    }

    function _attesters() internal pure returns (address[] memory att) {
        att = new address[](3);
        (att[0], att[1], att[2]) = (vm.addr(A1), vm.addr(A2), vm.addr(A3));
    }

    function _deploy(address[] memory att, uint256 threshold, uint64 ttl) internal returns (AttestedAgentRegistry) {
        return new AttestedAgentRegistry(att, threshold, BOND, ttl, NOTICE, IERC721(address(0)), address(0));
    }

    /// Two attesters sign the enrollment of `key` for `agent`, asked by `sponsor`.
    function _signed(uint256 agent, address key, address sponsor, uint64 deadline)
        internal
        view
        returns (bytes[] memory)
    {
        return _attest(A1, A2, reg.hashEnrollment(agent, key, EVIDENCE, sponsor, reg.enrollmentNonce(agent), deadline));
    }

    /// The agent's call is expected to fail with `error`.
    function _refused(uint256 pk, AgentAccount acc, address target, bytes memory data, bytes4 error) internal {
        vm.prank(vm.addr(pk));
        vm.expectRevert(error);
        acc.execute(target, 0, data);
    }

    // ------------------------------------------------------------ registry: deployment

    function test_RegistryRefusesABadConfiguration() public {
        address[] memory att = _attesters();
        vm.expectRevert(AttestedAgentRegistry.BadConfig.selector); // nobody has to sign
        _deploy(att, 0, TTL);
        vm.expectRevert(AttestedAgentRegistry.BadConfig.selector); // more signatures than attesters
        _deploy(att, 4, TTL);
        vm.expectRevert(AttestedAgentRegistry.BadConfig.selector); // keys that expire at once
        _deploy(att, 2, 0);

        att[2] = att[0]; // the same attester twice would let it count for two
        vm.expectRevert(AttestedAgentRegistry.BadConfig.selector);
        _deploy(att, 2, TTL);
        att[2] = address(0);
        vm.expectRevert(AttestedAgentRegistry.BadConfig.selector);
        _deploy(att, 2, TTL);
    }

    // ------------------------------------------------------------ registry: enrollment

    function test_EnrollmentRefusesBadInputEvenWhenSigned() public {
        bytes[] memory sigs = _signed(0, KEY, SPONSOR1, FAR);
        vm.prank(SPONSOR1);
        vm.expectRevert(AttestedAgentRegistry.BadInput.selector); // agent id 0 means "no agent"
        reg.enroll{value: BOND}(0, KEY, EVIDENCE, FAR, sigs);

        sigs = _signed(9, address(0), SPONSOR1, FAR);
        vm.prank(SPONSOR1);
        vm.expectRevert(AttestedAgentRegistry.BadInput.selector); // no key
        reg.enroll{value: BOND}(9, address(0), EVIDENCE, FAR, sigs);

        uint64 past = uint64(block.timestamp) - 1;
        sigs = _signed(9, KEY, SPONSOR1, past);
        vm.prank(SPONSOR1);
        vm.expectRevert(AttestedAgentRegistry.Expired.selector); // signatures past their deadline
        reg.enroll{value: BOND}(9, KEY, EVIDENCE, past, sigs);
    }

    function test_FirstEnrollmentTakesExactlyTheBondAndARotationNone() public {
        bytes[] memory sigs = _signed(9, KEY, SPONSOR1, FAR);
        uint256[3] memory wrong = [uint256(0), BOND - 1, BOND + 1];
        for (uint256 i; i < 3; ++i) {
            vm.prank(SPONSOR1);
            vm.expectRevert(AttestedAgentRegistry.BadBond.selector);
            reg.enroll{value: wrong[i]}(9, KEY, EVIDENCE, FAR, sigs);
        }
        vm.prank(SPONSOR1);
        reg.enroll{value: BOND}(9, KEY, EVIDENCE, FAR, sigs);

        sigs = _signed(9, address(0xABCE), SPONSOR1, FAR);
        vm.prank(SPONSOR1);
        vm.expectRevert(AttestedAgentRegistry.BadBond.selector);
        reg.enroll{value: 1}(9, address(0xABCE), EVIDENCE, FAR, sigs);
    }

    function test_AttesterSignaturesCoverEveryFieldOfAnEnrollment() public {
        bytes[] memory sigs = _signed(9, KEY, SPONSOR1, FAR);
        vm.startPrank(SPONSOR1);
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector); // another agent
        reg.enroll{value: BOND}(8, KEY, EVIDENCE, FAR, sigs);
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector); // another key
        reg.enroll{value: BOND}(9, address(0xABCE), EVIDENCE, FAR, sigs);
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector); // another evidence
        reg.enroll{value: BOND}(9, KEY, keccak256("other"), FAR, sigs);
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector); // a later deadline
        reg.enroll{value: BOND}(9, KEY, EVIDENCE, FAR + 1, sigs);
        vm.stopPrank();
        vm.prank(SPONSOR2);
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector); // another sponsor
        reg.enroll{value: BOND}(9, KEY, EVIDENCE, FAR, sigs);

        vm.prank(SPONSOR1);
        reg.enroll{value: BOND}(9, KEY, EVIDENCE, FAR, sigs);
        assertEq(reg.keyOf(9), KEY);
    }

    function test_OneAttesterDoesNotCountTwice() public {
        bytes32 d = reg.hashEnrollment(9, KEY, EVIDENCE, SPONSOR1, 0, FAR);
        bytes[] memory sigs = new bytes[](2);
        (sigs[0], sigs[1]) = (_sign(A1, d), _sign(A1, d));
        vm.prank(SPONSOR1);
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector);
        reg.enroll{value: BOND}(9, KEY, EVIDENCE, FAR, sigs);

        // Two attesters, but not in increasing order of address: refused as well, which is
        // what makes the duplicate check sound.
        sigs = _attest(A1, A2, d);
        (sigs[0], sigs[1]) = (sigs[1], sigs[0]);
        vm.prank(SPONSOR1);
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector);
        reg.enroll{value: BOND}(9, KEY, EVIDENCE, FAR, sigs);
    }

    // ------------------------------------------------------------ registry: sponsor and closing

    function test_OnlyTheSponsorRotatesFreezesAndRetires() public {
        // Even with attesters signing a rotation asked by someone else.
        bytes[] memory sigs = _signed(1, KEY, SPONSOR2, FAR);
        vm.startPrank(SPONSOR2);
        vm.expectRevert(AttestedAgentRegistry.NotSponsor.selector);
        reg.enroll(1, KEY, EVIDENCE, FAR, sigs);
        vm.expectRevert(AttestedAgentRegistry.NotSponsor.selector);
        reg.setFrozen(1, true);
        vm.expectRevert(AttestedAgentRegistry.NotSponsor.selector);
        reg.retire(1);
        vm.stopPrank();
        assertTrue(reg.isAgent(address(acc1)));
        assertEq(reg.keyOf(1), vm.addr(K1));
    }

    function test_AClosedAgentNeverComesBack() public {
        vm.prank(SPONSOR1);
        reg.retire(1);
        bytes[] memory sigs = _signed(1, KEY, SPONSOR1, FAR);
        vm.startPrank(SPONSOR1);
        vm.expectRevert(AttestedAgentRegistry.Closed.selector);
        reg.enroll(1, KEY, EVIDENCE, FAR, sigs);
        vm.expectRevert(AttestedAgentRegistry.Closed.selector); // nor can the exit delay be restarted
        reg.retire(1);
        vm.stopPrank();

        reg.revoke(2, _attest(A1, A2, reg.hashRevocation(2)));
        sigs = _signed(2, KEY, SPONSOR2, FAR);
        vm.startPrank(SPONSOR2);
        vm.expectRevert(AttestedAgentRegistry.Closed.selector);
        reg.enroll(2, KEY, EVIDENCE, FAR, sigs);
        vm.expectRevert(AttestedAgentRegistry.Closed.selector);
        reg.retire(2);
        vm.stopPrank();
    }

    /// The bond is what a sponsor loses if its agent is revoked: it stays while the agent lives.
    function test_BondOfALiveAgentCannotBeWithdrawn() public {
        skip(reg.EXIT_DELAY());
        vm.prank(SPONSOR1);
        vm.expectRevert(AttestedAgentRegistry.Closed.selector);
        reg.withdrawBond(1);
        assertEq(address(reg).balance, 2 * BOND);
    }

    function test_RevocationNamesOneExistingAgent() public {
        bytes[] memory sigs = _attest(A1, A2, reg.hashRevocation(1));
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector); // signed for agent 1, used on agent 2
        reg.revoke(2, sigs);
        assertTrue(reg.isAgent(address(acc2)));

        sigs = _attest(A1, A2, reg.hashRevocation(77));
        vm.expectRevert(AttestedAgentRegistry.Closed.selector); // an id nobody enrolled cannot be closed in advance
        reg.revoke(77, sigs);
    }

    function test_AttesterSignaturesCoverEveryFieldOfAVenueDecision() public {
        address venue = address(0xBEEF);
        bytes32 why = keccak256("code");
        bytes[] memory approval = _attest(A1, A2, reg.hashVenue(venue, true, why));
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector); // another venue
        reg.setVenue(address(0xBAD), true, why, approval);
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector); // another evidence
        reg.setVenue(venue, true, keccak256("other"), approval);
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector); // an approval used as a removal
        reg.setVenue(venue, false, why, approval);

        bytes[] memory removal = _attest(A1, A2, reg.hashVenue(venue, false, why));
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector); // a removal used as an approval
        reg.setVenue(venue, true, why, removal);
        assertEq(reg.venueSince(venue), 0);
    }

    // ------------------------------------------------------------ account

    /// A relayer submits the order exactly as the key signed it, or not at all.
    function test_ARelayedOrderCannotBeAltered() public {
        MockUSDC other = new MockUSDC();
        other.mint(address(acc1), 1_000);
        vm.deal(address(acc1), 1 ether);
        uint64 deadline = uint64(block.timestamp) + 60;
        bytes memory data = abi.encodeCall(usdc.transfer, (address(acc2), 1));
        bytes memory sig = _sign(K1, acc1.execDigest(address(usdc), 0, data, acc1.nonce(), deadline));

        vm.expectRevert(AgentAccount.NotKey.selector); // another target
        acc1.executeBySig(address(other), 0, data, deadline, sig);
        vm.expectRevert(AgentAccount.NotKey.selector); // another amount in the call
        acc1.executeBySig(address(usdc), 0, abi.encodeCall(usdc.transfer, (address(acc2), 1_000)), deadline, sig);
        vm.expectRevert(AgentAccount.NotKey.selector); // a later deadline
        acc1.executeBySig(address(usdc), 0, data, deadline + 1 days, sig);

        // An order to call acc2 with no ETH cannot be turned into a payment.
        bytes memory ping = _sign(K1, acc1.execDigest(address(acc2), 0, "", acc1.nonce(), deadline));
        vm.expectRevert(AgentAccount.NotKey.selector);
        acc1.executeBySig(address(acc2), 1 ether, "", deadline, ping);

        acc1.executeBySig(address(usdc), 0, data, deadline, sig);
        assertEq(usdc.balanceOf(address(acc2)), 1_001);
        assertEq(address(acc1).balance, 1 ether);
    }

    // ------------------------------------------------------------ sale

    function test_OnlyTheSellerCancelsAndASoldListingIsGone() public {
        uint256 id = _mint(K1, acc1);
        _do(K1, acc1, address(nft), abi.encodeCall(nft.approve, (address(swap), id)));
        _do(K1, acc1, address(swap), abi.encodeCall(swap.list, (nft, id, usdc, 5, address(0))));
        _refused(K2, acc2, address(swap), abi.encodeCall(swap.cancel, (nft, id)), AgentSwap.NotOwner.selector);

        _do(K2, acc2, address(usdc), abi.encodeCall(usdc.approve, (address(swap), 5)));
        _do(K2, acc2, address(swap), abi.encodeCall(swap.buy, (nft, id, usdc, 5)));
        (address seller,,,) = swap.listings(nft, id);
        assertEq(seller, address(0));
    }

    // ------------------------------------------------------------ loan

    function _offer(uint256 id) internal {
        _do(K1, acc1, address(nft), abi.encodeCall(nft.approve, (address(loan), id)));
        _do(K1, acc1, address(loan), abi.encodeCall(loan.offer, (nft, id, usdc, 400, 440, 900)));
    }

    function _fund(uint256 id) internal {
        _do(K2, acc2, address(usdc), abi.encodeCall(usdc.approve, (address(loan), 400)));
        _do(K2, acc2, address(loan), abi.encodeCall(loan.fund, (nft, id, usdc, 400, 440, 900)));
    }

    function test_OnlyTheBorrowerCancelsAndOnlyBeforeFunding() public {
        uint256 id = _mint(K1, acc1);
        _offer(id);
        // Another agent cancelling would walk away with the token.
        _refused(K2, acc2, address(loan), abi.encodeCall(loan.cancel, (nft, id)), AgentLoan.NotParty.selector);
        // An offer in place cannot be replaced by another one.
        _refused(
            K1, acc1, address(loan), abi.encodeCall(loan.offer, (nft, id, usdc, 1, 1, 1)), AgentLoan.BadState.selector
        );
        _fund(id);
        // Funded, the borrower cannot take the token back and keep the money.
        _refused(K1, acc1, address(loan), abi.encodeCall(loan.cancel, (nft, id)), AgentLoan.BadState.selector);
        assertEq(nft.ownerOf(id), address(loan));
    }

    function test_ALoanIsFundedOnceAndOnItsExactTerms() public {
        uint256 id = _mint(K1, acc1);
        // Nothing offered: nothing to fund.
        _refused(
            K2, acc2, address(loan), abi.encodeCall(loan.fund, (nft, id, usdc, 0, 0, 0)), AgentLoan.BadState.selector
        );
        _offer(id);
        MockUSDC other = new MockUSDC();
        bytes4 changed = AgentLoan.TermsChanged.selector;
        _refused(K2, acc2, address(loan), abi.encodeCall(loan.fund, (nft, id, other, 400, 440, 900)), changed);
        _refused(K2, acc2, address(loan), abi.encodeCall(loan.fund, (nft, id, usdc, 401, 440, 900)), changed);
        _refused(K2, acc2, address(loan), abi.encodeCall(loan.fund, (nft, id, usdc, 400, 439, 900)), changed);
        _refused(K2, acc2, address(loan), abi.encodeCall(loan.fund, (nft, id, usdc, 400, 440, 901)), changed);
        _fund(id);
        // A second lender would erase the first one's claim.
        _do(K1, acc1, address(usdc), abi.encodeCall(usdc.approve, (address(loan), 400)));
        _refused(
            K1,
            acc1,
            address(loan),
            abi.encodeCall(loan.fund, (nft, id, usdc, 400, 440, 900)),
            AgentLoan.BadState.selector
        );
    }

    function test_OnlyTheBorrowerRepaysAndOnlyAFundedLoan() public {
        uint256 id = _mint(K1, acc1);
        _offer(id);
        _do(K1, acc1, address(usdc), abi.encodeCall(usdc.approve, (address(loan), 440)));
        // Not funded yet: repaying would pay nobody.
        _refused(K1, acc1, address(loan), abi.encodeCall(loan.repay, (nft, id)), AgentLoan.BadState.selector);
        _fund(id);
        // Anyone else repaying would buy the pledged token for the repayment amount.
        _do(K2, acc2, address(usdc), abi.encodeCall(usdc.approve, (address(loan), 440)));
        _refused(K2, acc2, address(loan), abi.encodeCall(loan.repay, (nft, id)), AgentLoan.NotParty.selector);
        assertEq(nft.ownerOf(id), address(loan));
    }

    function test_LenderClaimsOnlyAfterTheDueTimeAndTheLoanIsThenOver() public {
        uint256 id = _mint(K1, acc1);
        _offer(id);
        _fund(id);
        skip(900); // the due time itself still belongs to the borrower
        _refused(K2, acc2, address(loan), abi.encodeCall(loan.claim, (nft, id)), AgentLoan.NotDue.selector);
        skip(1);
        _do(K2, acc2, address(loan), abi.encodeCall(loan.claim, (nft, id)));
        assertEq(nft.ownerOf(id), address(acc2));

        // Nothing is left of the loan: its new holder can pledge the token in turn.
        (address borrower,,,,,,) = loan.loans(nft, id);
        assertEq(borrower, address(0));
        _do(K2, acc2, address(nft), abi.encodeCall(nft.approve, (address(loan), id)));
        _do(K2, acc2, address(loan), abi.encodeCall(loan.offer, (nft, id, usdc, 1, 2, 3)));
    }

    // ------------------------------------------------------------ staking

    function test_StakingRefusesABadConfiguration() public {
        vm.expectRevert(AgentStaking.BadConfig.selector);
        new AgentStaking(IERC721(address(0)), usdc, address(this), 7 days);
        vm.expectRevert(AgentStaking.BadConfig.selector);
        new AgentStaking(nft, IERC20(address(0)), address(this), 7 days);
    }

    function test_UnstakingEndsTheStake() public {
        uint256 id = _mint(K1, acc1);
        _do(K1, acc1, address(nft), abi.encodeCall(nft.approve, (address(staking), id)));
        _do(K1, acc1, address(staking), abi.encodeCall(staking.stake, (id)));
        usdc.mint(address(this), 7_000 ether);
        usdc.approve(address(staking), 7_000 ether);
        staking.notifyRewardAmount(7_000 ether);
        skip(1 days);
        _do(K1, acc1, address(staking), abi.encodeCall(staking.unstake, (id)));

        assertEq(staking.stakerOf(id), address(0));
        assertEq(staking.stakedBy(address(acc1)), 0);
        assertEq(staking.totalStaked(), 0);
        skip(1 days); // the stream goes on, but no longer for this agent
        assertEq(staking.earned(address(acc1)), 0);
    }

    // ------------------------------------------------------------ badges

    function test_BadgeContractRefusesABadConfiguration() public {
        vm.expectRevert(AgentReputationBadge.WrongDeposit.selector); // issuers with nothing at stake
        new AgentReputationBadge(IAgentRegistry(address(reg)), 0, 3, 30 days);
        vm.expectRevert(AgentReputationBadge.WrongDeposit.selector); // issuers that can never issue
        new AgentReputationBadge(IAgentRegistry(address(reg)), DEPOSIT, 0, 30 days);
    }

    function test_IssuerRegistersOnceRetiresOnceAndWaitsForItsDeposit() public {
        vm.prank(ISSUER);
        vm.expectRevert(AgentReputationBadge.AlreadyRegistered.selector); // a second deposit would erase the first
        badges.registerIssuer{value: DEPOSIT}();
        vm.expectRevert(AgentReputationBadge.NotIssuer.selector); // a stranger has nothing to retire
        badges.retireIssuer();

        vm.startPrank(ISSUER);
        skip(30 days);
        vm.expectRevert(AgentReputationBadge.NotIssuer.selector); // no deposit back without retiring first
        badges.withdrawDeposit();
        badges.retireIssuer();
        vm.expectRevert(AgentReputationBadge.NotIssuer.selector); // retiring again would restart the delay
        badges.retireIssuer();
        vm.stopPrank();
    }

    function test_AClaimedBadgeCannotBeCancelled() public {
        vm.prank(ISSUER);
        uint256 id = badges.offer(address(acc1), keccak256("code"), keccak256("pr/1"), "pr/1");
        _do(K1, acc1, address(badges), abi.encodeCall(badges.claim, (id)));
        // Cancelling it as if it were still an offer would erase what the badge says.
        vm.prank(ISSUER);
        vm.expectRevert(AgentReputationBadge.NoSuchOffer.selector);
        badges.cancelOffer(id);
        assertEq(badges.badge(id).issuer, ISSUER);
        assertEq(badges.tokenURI(id), "pr/1");
    }
}
