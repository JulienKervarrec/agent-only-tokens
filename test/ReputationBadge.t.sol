// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IAgentRegistry} from "../src/IAgentRegistry.sol";
import {IERC721AgentOnly} from "../src/IERC721AgentOnly.sol";
import {ERC721AgentOnly} from "../src/ERC721AgentOnly.sol";
import {AgentAccount} from "../src/AgentAccount.sol";
import {AgentReputationBadge, IERC5192} from "../src/AgentReputationBadge.sol";
import {AgentOnlyBase} from "./AgentOnly.t.sol";

contract ReputationBadgeTest is AgentOnlyBase {
    AgentReputationBadge badges;
    address bot = address(0xB07); // a repository bot: an ordinary address, not an agent
    bytes32 constant CODE = keccak256("code-contribution");
    uint256 constant DEPOSIT = 0.05 ether;

    function setUp() public override {
        super.setUp();
        badges = new AgentReputationBadge(IAgentRegistry(address(reg)), DEPOSIT, 3, 30 days);
        vm.deal(bot, 1 ether);
        vm.prank(bot);
        badges.registerIssuer{value: DEPOSIT}();
    }

    function _offer(address agent, string memory pr) internal returns (uint256) {
        vm.prank(bot);
        return badges.offer(agent, CODE, keccak256(bytes(pr)), pr);
    }

    function _claim(uint256 pk, AgentAccount acc, uint256 offerId) internal returns (uint256) {
        return abi.decode(_do(pk, acc, address(badges), abi.encodeCall(badges.claim, (offerId))), (uint256));
    }

    function test_AgentClaimsItsBadge() public {
        uint256 offerId = _offer(address(acc1), "github.com/org/repo/pull/1");
        assertEq(badges.balanceOf(address(acc1)), 0); // nothing arrives unsolicited
        vm.expectEmit(address(badges));
        emit IERC5192.Locked(1);
        uint256 id = _claim(K1, acc1, offerId);

        assertEq(badges.ownerOf(id), address(acc1));
        assertTrue(badges.locked(id));
        AgentReputationBadge.Badge memory b = badges.badge(id);
        assertEq(b.issuer, bot);
        assertEq(b.category, CODE);
        assertEq(b.evidenceHash, keccak256("github.com/org/repo/pull/1"));
        assertEq(b.issuedAt, NOW);
        assertFalse(b.revoked);
        assertEq(badges.tokenURI(id), "github.com/org/repo/pull/1");
        assertTrue(badges.supportsInterface(type(IERC5192).interfaceId));
        assertTrue(badges.supportsInterface(type(IERC721AgentOnly).interfaceId));
        assertTrue(badges.supportsInterface(type(IERC721).interfaceId));
    }

    function test_OnlyTheNamedAgentCanClaim() public {
        uint256 offerId = _offer(address(acc1), "pr/2");
        vm.prank(vm.addr(K2));
        vm.expectRevert(AgentReputationBadge.NotYours.selector);
        acc2.execute(address(badges), 0, abi.encodeCall(badges.claim, (offerId)));
        vm.prank(human);
        vm.expectRevert(AgentReputationBadge.NotYours.selector);
        badges.claim(offerId);
        _claim(K1, acc1, offerId);
        vm.prank(vm.addr(K1));
        vm.expectRevert(AgentReputationBadge.NoSuchOffer.selector);
        acc1.execute(address(badges), 0, abi.encodeCall(badges.claim, (offerId)));
    }

    function test_OfferToAHumanCanNeverBeClaimed() public {
        uint256 offerId = _offer(human, "pr/3");
        vm.prank(human);
        vm.expectRevert(abi.encodeWithSelector(ERC721AgentOnly.NotAgent.selector, human));
        badges.claim(offerId);
    }

    function test_FrozenAgentCannotClaim() public {
        uint256 offerId = _offer(address(acc1), "pr/4");
        vm.prank(SPONSOR1);
        reg.setFrozen(1, true);
        vm.prank(vm.addr(K1));
        vm.expectRevert(AgentAccount.NotKey.selector);
        acc1.execute(address(badges), 0, abi.encodeCall(badges.claim, (offerId)));
    }

    function test_BadgeNeverMoves() public {
        uint256 id = _claim(K1, acc1, _offer(address(acc1), "pr/5"));
        bytes[4] memory calls = [
            abi.encodeCall(badges.transferFrom, (address(acc1), address(acc2), id)),
            abi.encodeWithSignature("safeTransferFrom(address,address,uint256)", address(acc1), address(acc2), id),
            abi.encodeCall(badges.approve, (address(acc2), id)),
            abi.encodeCall(badges.setApprovalForAll, (address(acc2), true))
        ];
        for (uint256 i; i < 4; ++i) {
            vm.prank(vm.addr(K1));
            vm.expectRevert(AgentReputationBadge.Soulbound.selector);
            acc1.execute(address(badges), 0, calls[i]);
        }
        assertEq(badges.ownerOf(id), address(acc1));
    }

    function test_IssuerRevokes() public {
        uint256 id = _claim(K1, acc1, _offer(address(acc1), "pr/6"));
        vm.prank(human);
        vm.expectRevert(AgentReputationBadge.NotIssuer.selector);
        badges.revoke(id);
        vm.prank(bot);
        badges.revoke(id);
        assertTrue(badges.badge(id).revoked);
        assertEq(badges.ownerOf(id), address(acc1)); // the record stays
    }

    function test_IssuerRulesAgainstSpam() public {
        // No deposit, no issuing.
        vm.prank(human);
        vm.expectRevert(AgentReputationBadge.NotIssuer.selector);
        badges.offer(address(acc1), CODE, keccak256("x"), "x");
        vm.deal(human, 1 ether);
        vm.prank(human);
        vm.expectRevert(AgentReputationBadge.WrongDeposit.selector);
        badges.registerIssuer{value: DEPOSIT - 1}();
        // The same evidence earns one badge per issuer.
        _offer(address(acc1), "pr/7");
        vm.prank(bot);
        vm.expectRevert(AgentReputationBadge.EvidenceAlreadyUsed.selector);
        badges.offer(address(acc2), CODE, keccak256("pr/7"), "pr/7");
        // Daily quota: 3 offers, the 4th waits for the next day.
        _offer(address(acc1), "pr/8");
        _offer(address(acc1), "pr/9");
        vm.prank(bot);
        vm.expectRevert(AgentReputationBadge.QuotaExceeded.selector);
        badges.offer(address(acc1), CODE, keccak256("pr/10"), "pr/10");
        vm.warp(NOW + 1 days);
        _offer(address(acc1), "pr/10");
    }

    function test_IssuerCancelsOffer() public {
        uint256 offerId = _offer(address(acc1), "pr/11");
        vm.prank(human);
        vm.expectRevert(AgentReputationBadge.NotIssuer.selector);
        badges.cancelOffer(offerId);
        vm.prank(bot);
        badges.cancelOffer(offerId);
        vm.prank(vm.addr(K1));
        vm.expectRevert(AgentReputationBadge.NoSuchOffer.selector);
        acc1.execute(address(badges), 0, abi.encodeCall(badges.claim, (offerId)));
    }

    function test_IssuerRetiresThenWithdraws() public {
        uint256 id = _claim(K1, acc1, _offer(address(acc1), "pr/12"));
        vm.startPrank(bot);
        badges.retireIssuer();
        vm.expectRevert(AgentReputationBadge.NotIssuer.selector);
        badges.offer(address(acc1), CODE, keccak256("pr/13"), "pr/13");
        vm.expectRevert(AgentReputationBadge.TooEarly.selector);
        badges.withdrawDeposit();
        vm.warp(NOW + 30 days);
        uint256 before = bot.balance;
        badges.withdrawDeposit();
        assertEq(bot.balance, before + DEPOSIT);
        vm.expectRevert(AgentReputationBadge.NotIssuer.selector);
        badges.withdrawDeposit();
        vm.expectRevert(AgentReputationBadge.AlreadyRegistered.selector);
        badges.registerIssuer{value: DEPOSIT}();
        vm.stopPrank();
        // Badges already issued keep their issuer, who can still revoke them.
        vm.prank(bot);
        badges.revoke(id);
        assertTrue(badges.badge(id).revoked);
    }

    function testFuzz_OnlyTheNamedAgentEverHoldsABadge(address caller) public {
        vm.assume(caller != address(acc1) && caller != address(0));
        uint256 offerId = _offer(address(acc1), "pr/fuzz");
        vm.prank(caller);
        vm.expectRevert();
        badges.claim(offerId);
        assertEq(badges.balanceOf(caller), 0);
    }
}
